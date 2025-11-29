local requests = require("nurl.requests")
local responses = require("nurl.responses")
local config = require("nurl.config")
local winbar = require("nurl.ui.winbar")
local projects = require("nurl.projects")
local environments = require("nurl.environments")
local ResponseWindow = require("nurl.ui.response_window")
local history = require("nurl.data.history")
local Stack = require("nurl.utils.stack")
local pickers = require("nurl.pickers")
local variables = require("nurl.variables")

local M = {}

M.winbar = winbar

M.lazy = variables.lazy

M.env = environments

---@type nurl.Stack
M.last_requests = Stack:new(5)
---@type nurl.Stack
M.last_request_wins = Stack:new(5)

---@class nurl.RequestOpts
---@field win? integer | nil
---@field on_response? fun(response: nurl.Response | nil, curl: nurl.Curl) | nil

---@param request nurl.SuperRequest | nurl.Request
---@param opts? nurl.RequestOpts | nil
function M.send(request, opts)
    opts = opts or {}

    local response_window

    local win = opts.win

    local function next_function()
        local expanded_request = requests.expand(request)

        M.last_requests:push(expanded_request)

        local curl = requests.build_curl(expanded_request)

        local should_prepare_response_ui = opts.on_response == nil
        if should_prepare_response_ui then
            response_window = ResponseWindow:new({
                win = win,
                request = expanded_request,
                curl = curl,
            })
            win = response_window:open()
            M.last_request_wins:push(win)
        end

        local function default_on_response(response, _curl)
            response_window:update(response, _curl)
        end

        curl:run(function(system_completed)
            local stdout = vim.split(system_completed.stdout, "\n")
            local stderr = vim.split(system_completed.stderr, "\n")

            local response = nil
            if system_completed.code == 0 then
                response = responses.parse(stdout, stderr)
            end

            vim.schedule(function()
                if expanded_request.post_hook ~= nil then
                    local status, result = pcall(
                        expanded_request.post_hook,
                        expanded_request,
                        response
                    )

                    if not status then
                        vim.notify(
                            "Request post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                local env_post_hook = environments.get_post_hook()
                if env_post_hook ~= nil then
                    local status, result =
                        pcall(env_post_hook, expanded_request, response)

                    if not status then
                        vim.notify(
                            "Environment post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                if opts.on_response then
                    opts.on_response(response, curl)
                else
                    default_on_response(response, curl)
                end

                local request_was_sent = response ~= nil
                    and curl.result.code == 0
                if request_was_sent and config.history.enabled then
                    local status, error = pcall(
                        history.insert_history_entry,
                        expanded_request,
                        response,
                        curl
                    )
                    if not status then
                        vim.notify(
                            ("Failed to save request in history: %s"):format(
                                error
                            ),
                            vim.log.levels.ERROR
                        )
                    end
                end
            end)
        end)
    end

    local function env_next_function()
        if request.pre_hook ~= nil then
            request.pre_hook(next_function, request)
        else
            next_function()
        end
    end

    local env_pre_hook = environments.get_pre_hook()
    if env_pre_hook == nil then
        env_next_function()
    else
        env_pre_hook(env_next_function, request)
    end
end

function M.resend_last_request(index)
    index = index or -1

    local request = M.last_requests:get(index)
    if not request then
        vim.notify("No last request at position: " .. index)
        return
    end

    M.send(request, { win = M.last_request_wins:get(index) })
end

function M.send_buffer_request()
    local buffer_requests = dofile(vim.fn.expand("%"))

    pickers.pick_request("Nurl: send", buffer_requests, function(request)
        M.send(request)
    end)
end

function M.send_project_request()
    local project_requests = projects.requests()
    pickers.pick_project_request_item(
        "Nurl: send",
        project_requests,
        function(item)
            M.send(item.request)
        end
    )
end

function M.jump_to_project_request()
    local project_requests = projects.requests()
    pickers.pick_project_request_item("Nurl: jump", project_requests)
end

---@param cursor_row integer
---@param cursor_col integer
---@param request nurl.ProjectRequestItem
local function is_cursor_contained_in_request_item(
    cursor_row,
    cursor_col,
    request
)
    return (
        request.start_row <= cursor_row
        and request.end_row >= cursor_row
        and (cursor_row ~= request.end_row or cursor_col < request.end_col)
        and (cursor_row ~= request.start_row or cursor_col >= request.start_col)
    )
end

function M.send_request_at_cursor()
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local project_requests = projects.requests()

    for _, request in ipairs(project_requests) do
        local request_contains_cursor =
            is_cursor_contained_in_request_item(cursor_row, cursor_col, request)

        if request_contains_cursor then
            M.send(request.request)
            return
        end
    end
end

function M.yank_curl_at_cursor()
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local project_requests = projects.requests()

    for _, request in ipairs(project_requests) do
        local request_contains_cursor =
            is_cursor_contained_in_request_item(cursor_row, cursor_col, request)

        if request_contains_cursor then
            local expanded_request = requests.expand(request.request)

            local curl = requests.build_curl(expanded_request)

            vim.fn.setreg("+", curl:string())
            vim.notify("Yanked curl command to clipboard")

            return
        end
    end
end

function M.activate_env()
    vim.ui.select(
        vim.tbl_keys(environments.project_envs),
        { prompt = "Activate environment" },
        function(choice)
            if choice ~= nil then
                environments.activate(choice)
                vim.cmd.redrawstatus() -- in case the user is showing the active env in statusline
            end
        end
    )
end

function M.open_environments_file()
    local environments_file =
        vim.fs.joinpath(config.dir, config.environments_file)
    vim.cmd.edit(environments_file)
end

function M.get_active_env()
    return environments.project_active_env
end

function M.open_history()
    local history_items = history.all()

    pickers.pick_request_history_item(
        "Nurl: history",
        history_items,
        function(item)
            local request, response, curl = unpack(item)

            local window = ResponseWindow:new({
                request = request,
                response = response,
                curl = curl,
            })
            window:open({ enter = true })
        end
    )
end

return M

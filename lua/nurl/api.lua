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
local override = require("nurl.override")
local util = require("nurl.util")

local M = {}

M.winbar = winbar

M.lazy = variables.lazy

M.env = environments

M.util = util

---@type nurl.Stack
M.last_requests = Stack:new(5)
---@type nurl.Stack
M.last_request_wins = Stack:new(5)

---@class nurl.RequestOpts
---@field win? integer | nil
---@field on_complete? fun(out: nurl.RequestOut) | nil

---@param request nurl.SuperRequest | nurl.Request
---@param opts? nurl.RequestOpts | nil
function M.send(request, opts)
    opts = opts or {}

    local response_window

    local win = opts.win

    local expanded_request = requests.expand(request)

    -- Request is already fully expanded here.
    ---@cast expanded_request nurl.Request

    ---@type nurl.RequestInput
    local input = { request = expanded_request }

    local function next_function()
        M.last_requests:push(expanded_request)

        local curl = requests.build_curl(expanded_request)

        local should_prepare_response_ui = opts.on_complete == nil
        if should_prepare_response_ui then
            response_window = ResponseWindow:new({
                win = win,
                request = expanded_request,
                curl = curl,
            })
            win = response_window:open()
        end

        -- Push vim.NIL in case no window was opened
        M.last_request_wins:push(win or vim.NIL)

        local function default_on_complete(out)
            response_window:update(out.response, out.curl)
        end

        curl:run(function(system_completed)
            local stdout = vim.split(system_completed.stdout, "\n")
            local stderr = vim.split(system_completed.stderr, "\n")

            local response = nil

            local curl_success = system_completed.code == 0
                and system_completed.signal == 0

            if curl_success then
                response = responses.parse(stdout, stderr)

                if not responses.is_displayable(response) then
                    response, curl = responses.move_body_to_file(response, curl)
                end
            end

            vim.schedule(function()
                ---@type nurl.RequestOut
                local out = {
                    request = expanded_request,
                    response = response,
                    curl = curl,
                    win = win,
                }

                if expanded_request.post_hook ~= nil then
                    local status, result =
                        pcall(expanded_request.post_hook, out)

                    if not status then
                        vim.notify(
                            "Request post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                local env_post_hook = environments.get_post_hook()
                if env_post_hook ~= nil then
                    local status, result = pcall(env_post_hook, out)

                    if not status then
                        vim.notify(
                            "Environment post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                if opts.on_complete then
                    opts.on_complete(out)
                else
                    default_on_complete(out)
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

        if response_window ~= nil then
            -- Update to add the curl PID
            response_window:update(nil, curl)
        end
    end

    local function env_next_function()
        if expanded_request.pre_hook ~= nil then
            expanded_request.pre_hook(next_function, input)
        else
            next_function()
        end
    end

    local env_pre_hook = environments.get_pre_hook()
    if env_pre_hook == nil then
        env_next_function()
    else
        env_pre_hook(env_next_function, input)
    end
end

function M.resend_last_request(index, overrides)
    index = index or -1
    overrides = overrides or {}

    local request = M.last_requests:get(index)
    if not request then
        vim.notify("No last request at position: " .. index)
        return
    end

    local win = M.last_request_wins:get(index)
    if win == vim.NIL then -- vim.NIL is pushed when no window was opened
        win = nil
    end

    override(request, overrides)
    -- TODO: previous on_complete won't be passed
    M.send(request, { win = win })
end

function M.pick_resend(overrides)
    overrides = overrides or {}

    local recent_requests = M.last_requests.items

    if #recent_requests == 0 then
        vim.notify("No recent requests to resend", vim.log.levels.WARN)
        return
    end

    pickers.pick_request("Nurl: resend", recent_requests, function(request)
        override(request, overrides)
        M.send(request)
    end)
end

function M.send_project_request(overrides)
    overrides = overrides or {}

    local project_requests = projects.requests()
    pickers.pick_project_request_item(
        "Nurl: send",
        project_requests,
        function(item)
            override(item.request, overrides)
            M.send(item.request)
        end
    )
end

function M.send_file_request(filepath, overrides)
    filepath = vim.fn.expand(filepath)
    overrides = overrides or {}

    local file_requests = dofile(filepath)
    if #file_requests == 1 then
        override(file_requests[1], overrides)
        M.send(file_requests[1])
    else
        pickers.pick_request("Nurl: send", file_requests, function(request)
            override(request, overrides)
            M.send(request)
        end)
    end
end

function M.jump_to_project_request()
    local project_requests = projects.requests()
    pickers.pick_project_request_item("Nurl: jump", project_requests)
end

function M.jump_to_file_request(filepath)
    filepath = vim.fn.expand(filepath)
    local file_requests = projects.file_requests(filepath)
    if #file_requests == 1 then
        projects.jump_to(file_requests[1])
    else
        pickers.pick_project_request_item("Nurl: jump", file_requests)
    end
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

function M.send_request_at_cursor(overrides)
    overrides = overrides or {}

    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local file_requests = projects.file_requests(vim.fn.expand("%"))

    for _, request in ipairs(file_requests) do
        local request_contains_cursor =
            is_cursor_contained_in_request_item(cursor_row, cursor_col, request)

        if request_contains_cursor then
            override(request.request, overrides)
            M.send(request.request)
            return
        end
    end
end

local function yank_curl(request)
    local expanded_request = requests.expand(request)
    -- Request is already fully expanded here.
    ---@cast expanded_request nurl.Request
    local curl = requests.build_curl(expanded_request)
    vim.fn.setreg("+", curl:string())
    vim.notify("Yanked curl command to clipboard")
end

function M.yank_curl_at_cursor(overrides)
    overrides = overrides or {}

    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local file_requests = projects.file_requests(vim.fn.expand("%"))

    for _, request in ipairs(file_requests) do
        local request_contains_cursor =
            is_cursor_contained_in_request_item(cursor_row, cursor_col, request)

        if request_contains_cursor then
            override(request.request, overrides)
            yank_curl(request.request)
            return
        end
    end
end

function M.yank_project_request(overrides)
    overrides = overrides or {}

    local project_requests = projects.requests()
    pickers.pick_project_request_item(
        "Nurl: yank",
        project_requests,
        function(item)
            override(item.request, overrides)
            yank_curl(item.request)
        end
    )
end

function M.yank_file_request(filepath, overrides)
    filepath = vim.fn.expand(filepath)
    overrides = overrides or {}

    local file_requests = dofile(filepath)
    if #file_requests == 1 then
        override(file_requests[1], overrides)
        yank_curl(file_requests[1])
    else
        pickers.pick_request("Nurl: yank", file_requests, function(request)
            override(request, overrides)
            yank_curl(request)
        end)
    end
end

function M.pick_env()
    vim.ui.select(
        vim.tbl_keys(environments.project_envs),
        { prompt = "Nurl: activate environment" },
        function(choice)
            if choice ~= nil then
                environments.activate(choice)
                vim.cmd.redrawstatus() -- in case the user is showing the active env in statusline
            end
        end
    )
end

---@param env string to activate
function M.activate_env(env)
    environments.activate(env)
    vim.cmd.redrawstatus() -- in case the user is showing the active env in statusline
end

function M.open_environments_file()
    local environments_file =
        vim.fs.joinpath(config.dir, config.environments_file)
    vim.cmd.edit(environments_file)
end

function M.get_active_env()
    return environments.project_active_env
end

function M.pick_history()
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

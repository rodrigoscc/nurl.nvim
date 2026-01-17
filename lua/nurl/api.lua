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
local TestReport = require("nurl.test.report")
local ctx = require("nurl.test.ctx")
local RequestHandle = require("nurl.request_handle")
local registry = require("nurl.registry")

local M = {}

M.winbar = winbar

M.lazy = variables.lazy

M.env = environments

M.util = util

M.registry = registry

---@type nurl.Stack
M.last_requests = Stack:new(5)

---@class nurl.LastItem
---@field request nurl.Request
---@field win integer

---@class nurl.SendDisplayOpts
---@field win? integer Reuse existing window
---@field focus_buffer? nurl.BufferType

---@class nurl.SendOpts
---@field display? nurl.SendDisplayOpts|boolean Show UI (default: false)

---@param request nurl.SuperRequest | nurl.Request
---@param opts_or_callback? nurl.SendOpts | fun(out: nurl.RequestOut)
---@param callback? fun(out: nurl.RequestOut)
---@return nurl.RequestHandle
function M.send(request, opts_or_callback, callback)
    local opts = {}

    if type(opts_or_callback) == "function" then
        callback = opts_or_callback
    elseif type(opts_or_callback) == "table" then
        opts = opts_or_callback
    end

    local response_window

    if opts.display ~= nil and opts.display == true then
        opts.display = {}
    end

    local win = nil

    local expanded_request = requests.expand(request)

    -- Request is already fully expanded here.
    ---@cast expanded_request nurl.Request

    ---@type nurl.RequestInput
    local input = { request = expanded_request }

    local handle = RequestHandle:new(expanded_request)

    ---@type nurl.RegistryEntry
    local entry = { handle = handle }

    local function next_function()
        registry:push(entry)

        if opts.display then
            response_window = ResponseWindow:new({
                win = opts.display.win,
                handle_id = handle.id,
            })
            win = response_window:open({
                focus_buffer = opts.display.focus_buffer,
            })
        end

        -- Last request feature is targetted only to resend displayed requests
        if opts.display then
            M.last_requests:push({ request = expanded_request, win = win })
        end

        local curl = requests.build_curl(expanded_request)

        local curl_handle = curl:run(function(system_completed)
            local stdout = vim.split(system_completed.stdout, "\n")
            local stderr = vim.split(system_completed.stderr, "\n")

            local response = nil

            local curl_success = system_completed.code == 0
                and system_completed.signal == 0
            local curl_interrupted = system_completed.signal ~= 0

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
                    test_report = nil,
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

                if expanded_request.test and curl_success then
                    out.test_report = TestReport:new()
                    local test_ctx = ctx.build_ctx(out.test_report)
                    local ok, err =
                        pcall(expanded_request.test, test_ctx, response)
                    if not ok then
                        out.test_report:error(err)
                    end
                end

                if callback then
                    callback(out)
                end

                if curl_interrupted then
                    handle:_cancelled(out.response, out.curl, out.test_report)
                elseif curl_success then
                    handle:_resolve(out.response, out.curl, out.test_report)
                else
                    handle:_failed(out.response, out.curl, out.test_report)
                end

                if opts.display then
                    response_window:update()
                    response_window:on_buffers_unloaded(function()
                        registry:remove(handle.id)
                    end)
                else
                    registry:remove(handle.id)
                end

                local request_was_sent = curl_success
                if request_was_sent and config.history.enabled then
                    local status, error =
                        pcall(history.insert_history_entry, handle)
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

        handle:_started(curl_handle.pid)
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

    return handle
end

function M.resend_last_request(index, overrides)
    index = index or -1
    overrides = overrides or {}

    local last = M.last_requests:get(index)
    if not last then
        vim.notify("No last request at position: " .. index)
        return
    end

    local win = last.win
    if win == vim.NIL or not vim.api.nvim_win_is_valid(win) then -- vim.NIL is pushed when no window was opened
        win = nil
    end

    local focus_buffer = nil
    if win ~= nil then
        local buf = vim.api.nvim_win_get_buf(win)
        focus_buffer = vim.b[buf].nurl_data.buffer_type
    end

    local request = override(last.request, overrides)
    -- TODO: previous on_complete won't be passed
    M.send(request, { display = { win = win, focus_buffer = focus_buffer } })
end

function M.pick_resend(overrides)
    overrides = overrides or {}

    local last_items = M.last_requests.items

    if #last_items == 0 then
        vim.notify("No recent requests to resend", vim.log.levels.WARN)
        return
    end

    local recent_requests = vim.tbl_map(function(r)
        return r.request
    end, last_items)

    pickers.pick_request("Nurl: resend", recent_requests, function(request)
        request = override(request, overrides)
        M.send(request, { display = true })
    end)
end

function M.send_project_request(overrides)
    overrides = overrides or {}

    local project_requests = projects.requests()
    pickers.pick_project_request_item(
        "Nurl: send",
        project_requests,
        function(item)
            local request = override(item.request, overrides)
            M.send(request, { display = true })
        end
    )
end

function M.send_file_request(filepath, overrides)
    filepath = vim.fn.expand(filepath)
    overrides = overrides or {}

    local file_requests = dofile(filepath)
    if #file_requests == 1 then
        local request = override(file_requests[1], overrides)
        M.send(request, { display = true })
    else
        pickers.pick_request("Nurl: send", file_requests, function(request)
            request = override(request, overrides)
            M.send(request, { display = true })
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

    local at_nurl_buffer = vim.b.nurl_data ~= nil

    if at_nurl_buffer then
        local entry = registry:get(vim.b.nurl_data.handle_id)
        local buffer_request = entry.handle.request
        buffer_request = override(buffer_request, overrides)
        M.send(
            buffer_request,
            { display = { win = vim.api.nvim_get_current_win() } }
        )
    else
        local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

        local file_requests = projects.file_requests(vim.fn.expand("%"))

        for _, item in ipairs(file_requests) do
            local request_contains_cursor = is_cursor_contained_in_request_item(
                cursor_row,
                cursor_col,
                item
            )

            if request_contains_cursor then
                local request = override(item.request, overrides)
                M.send(request, { display = true })
                return
            end
        end

        vim.notify("No request found at cursor", vim.log.levels.ERROR)
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

    local is_at_nurl_buffer = vim.b.nurl_data ~= nil

    if is_at_nurl_buffer then
        local entry = registry.get(vim.b.nurl_data.handle_id)
        local buffer_request = entry.handle.request
        buffer_request = override(buffer_request, overrides)
        yank_curl(buffer_request)
    else
        local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

        local file_requests = projects.file_requests(vim.fn.expand("%"))

        for _, item in ipairs(file_requests) do
            local request_contains_cursor = is_cursor_contained_in_request_item(
                cursor_row,
                cursor_col,
                item
            )

            if request_contains_cursor then
                local request = override(item.request, overrides)
                yank_curl(request)
                return
            end
        end

        vim.notify("No request found at cursor", vim.log.levels.ERROR)
    end
end

function M.yank_project_request(overrides)
    overrides = overrides or {}

    local project_requests = projects.requests()
    pickers.pick_project_request_item(
        "Nurl: yank",
        project_requests,
        function(item)
            local request = override(item.request, overrides)
            yank_curl(request)
        end
    )
end

function M.yank_file_request(filepath, overrides)
    filepath = vim.fn.expand(filepath)
    overrides = overrides or {}

    local file_requests = dofile(filepath)
    if #file_requests == 1 then
        local request = override(file_requests[1], overrides)
        yank_curl(request)
    else
        pickers.pick_request("Nurl: yank", file_requests, function(request)
            request = override(request, overrides)
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
            local exec_datetime, request, response, curl = unpack(item)

            local item_handle =
                RequestHandle:rebuild(exec_datetime, request, response, curl)

            local entry = { handle = item_handle }
            registry:push(entry)

            local response_window = ResponseWindow:new({
                handle_id = item_handle.id,
            })
            response_window:open({ enter = true })
        end
    )
end

return M

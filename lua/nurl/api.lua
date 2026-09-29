local requests = require("nurl.requests")
local config = require("nurl.config")
local winbar = require("nurl.ui.response_view.winbar")
local projects = require("nurl.projects")
local environments = require("nurl.environments")
local ResponseView = require("nurl.ui.response_view")
local history = require("nurl.data.history")
local Stack = require("nurl.utils.stack")
local pickers = require("nurl.pickers")
local variables = require("nurl.variables")
local override = require("nurl.override")
local helpers = require("nurl.helpers")
local RequestHandle = require("nurl.app.handle")
local runner = require("nurl.app.runner")
local convert = require("nurl.convert")

local M = {}

M.winbar = winbar

M.lazy = variables.lazy

M.env = environments

M.helpers = helpers

M.json_to_lua = convert.json_to_lua

M.lua_to_json = convert.lua_to_json

---@type nurl.Stack
M.last_requests = Stack:new(5, {
    key_fn = function(item)
        local request = vim.deepcopy(item.request)

        request.pre_hook = nil
        request.post_hook = nil
        request.test = nil

        return request
    end,
})

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

    if opts.display ~= nil and opts.display == true then
        opts.display = {}
    end

    local view

    return runner.run(request, {
        callback = callback,
        on_start = function(handle)
            if not opts.display then
                return nil
            end

            view = ResponseView.open(handle, {
                win = opts.display.win,
                focus_buffer = opts.display.focus_buffer,
            })

            -- Last request feature is targetted only to resend displayed requests
            M.last_requests:push({ request = handle.request, win = view.win })

            return view.win
        end,
        on_complete = function(handle)
            -- The window may show another request by now.
            if view and view.handle == handle then
                view:update()
            end

            if
                handle.status == "completed"
                and config.history.enabled
                and handle.request.save_history ~= false
            then
                local status, error =
                    pcall(history.insert_history_entry, handle)
                if not status then
                    vim.notify(
                        ("Failed to save request in history: %s"):format(error),
                        vim.log.levels.ERROR
                    )
                end
            end
        end,
    })
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
    local view = win and ResponseView.for_win(win)
    if view then
        focus_buffer = view:type_of(vim.api.nvim_win_get_buf(win))
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

    local view = ResponseView.for_buf(vim.api.nvim_get_current_buf())

    if view then
        local buffer_request = view.handle.request
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

    local view = ResponseView.for_buf(vim.api.nvim_get_current_buf())

    if view then
        local buffer_request = view.handle.request
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
    require("nurl.ui.history_explorer").open()
end

---@param item nurl.HistoryItem
---@param win? integer Existing response window to reuse
---@return integer win, nurl.ResponseView view
function M.open_history_item(item, win)
    local exec_datetime, request, response, curl = unpack(item)

    local item_handle =
        RequestHandle:rebuild(exec_datetime, request, response, curl)

    local view = ResponseView.open(item_handle, { win = win, enter = true })
    return view.win, view
end

return M

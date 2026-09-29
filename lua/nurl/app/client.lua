local config = require("nurl.config")
local history = require("nurl.history")
local requests = require("nurl.core.request")
local Curl = require("nurl.core.curl")
local override = require("nurl.core.override")
local runner = require("nurl.app.runner")
local RequestHandle = require("nurl.app.handle")
local ResponseView = require("nurl.ui.response_view")
local Stack = require("nurl.utils.stack")

---@class nurl.app.client
local M = {}

---@class nurl.RecentRequest
---@field request nurl.Request
---@field win integer

---The requests last shown in a response window, to send them again.
---@type nurl.Stack
M.recent = Stack:new(5, {
    key_fn = function(item)
        local request = vim.deepcopy(item.request)

        request.pre_hook = nil
        request.post_hook = nil
        request.test = nil

        return request
    end,
})

---@class nurl.SendDisplayOpts
---@field win? integer Reuse existing window
---@field focus_buffer? nurl.BufferType

---@class nurl.SendOpts
---@field display? nurl.SendDisplayOpts|boolean Show UI (default: false)

---@param handle nurl.RequestHandle
local function save_to_history(handle)
    if
        handle.status ~= "completed"
        or not config.history.enabled
        or handle.request.save_history == false
    then
        return
    end

    local status, error = pcall(history.insert_history_entry, handle)
    if not status then
        vim.notify(
            ("Failed to save request in history: %s"):format(error),
            vim.log.levels.ERROR
        )
    end
end

---Send a request, showing it in a response window if asked to, and save it
---to history once done.
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
            M.recent:push({ request = handle.request, win = view.win })

            return view.win
        end,
        on_complete = function(handle)
            -- The window may show another request by now.
            if view and view.handle == handle then
                view:update()
            end

            save_to_history(handle)
        end,
    })
end

---Send one of the recent requests again, in its window if still open.
---@param index? integer position from the end, -1 being the last
---@param overrides? nurl.Override[]
function M.resend(index, overrides)
    index = index or -1

    local last = M.recent:get(index)
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

    local request = override(last.request, overrides or {})
    -- TODO: previous on_complete won't be passed
    M.send(request, { display = { win = win, focus_buffer = focus_buffer } })
end

---Show a request saved in history.
---@param item nurl.HistoryItem
---@param win? integer Existing response window to reuse
---@return nurl.ResponseView
function M.open_history_item(item, win)
    local exec_datetime, request, response, curl = unpack(item)

    local handle = RequestHandle:rebuild(exec_datetime, request, response, curl)

    return ResponseView.open(handle, { win = win, enter = true })
end

---Copy the curl command of a request to the clipboard.
---@param request nurl.SuperRequest | nurl.Request
function M.yank(request)
    local expanded_request = requests.expand(request)
    -- Request is already fully expanded here.
    ---@cast expanded_request nurl.Request
    local curl = Curl.build(expanded_request)
    vim.fn.setreg("+", curl:string())
    vim.notify("Yanked curl command to clipboard")
end

---The request shown in a response buffer.
---@param bufnr? integer Default: the current buffer
---@return nurl.Request?
function M.request_in(bufnr)
    local view = ResponseView.for_buf(bufnr or vim.api.nvim_get_current_buf())
    return view and view.handle.request
end

return M

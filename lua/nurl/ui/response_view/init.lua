local buffers = require("nurl.ui.buffers")
local actions = require("nurl.ui.response_view.actions")
local winbar = require("nurl.ui.response_view.winbar")
local SecondaryWindow = require("nurl.ui.response_view.secondary")
local ElapsedTimeFloating = require("nurl.ui.elapsed_time")
local config = require("nurl.config")

local M = {}

---Set on every response buffer, so that statuslines and user mappings can
---tell them apart.
---@class nurl.BufferData
---@field buffer_type nurl.BufferType

---A window showing a request and its response, one buffer per part. It owns
---its buffers: they are replaced when another request is shown in the window
---and deleted when the window closes.
---@class nurl.ResponseView
---@field win integer
---@field handle nurl.RequestHandle
---@field buffers table<nurl.BufferType, integer>
---@field private secondary? nurl.SecondaryWindow
---@field private elapsed_time? nurl.ElapsedTimeFloating
---@field private closed boolean
local View = {}
View.__index = View

---@type table<integer, nurl.ResponseView>
local views_by_buf = {}

---@type table<integer, nurl.ResponseView>
local views_by_win = {}

---@param bufnr integer
---@return nurl.ResponseView?
function M.for_buf(bufnr)
    return views_by_buf[bufnr]
end

---@param win integer
---@return nurl.ResponseView?
function M.for_win(win)
    return views_by_win[win]
end

---@param action string|nurl.BufferAction|fun()
---@param view nurl.ResponseView
---@return fun()
local function keymap_rhs(action, view)
    if type(action) == "string" then
        return actions.builtin[action](view)
    elseif type(action) == "table" and type(action[1]) == "string" then
        return actions.builtin[action[1]](view, action.opts)
    end

    return action
end

---Delete buffers, leaving any still displayed in another window to be wiped
---once hidden.
---@param bufnrs table<nurl.BufferType, integer>
local function delete_buffers(bufnrs)
    for _, bufnr in pairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            if #vim.fn.win_findbuf(bufnr) == 0 then
                vim.api.nvim_buf_delete(bufnr, { force = true })
            else
                vim.bo[bufnr].bufhidden = "wipe"
            end
        end
    end
end

---@param bufnr integer
---@return nurl.BufferType?
function View:type_of(bufnr)
    for type, view_bufnr in pairs(self.buffers) do
        if view_bufnr == bufnr then
            return type
        end
    end
end

---Show a part of the response in a window.
---@param win integer
---@param type nurl.BufferType
function View:switch(win, type)
    local bufnr = self.buffers[type]
    if bufnr ~= nil then
        vim.api.nvim_win_set_buf(win, bufnr)
    end
end

---Show the next part of the response in a window, or the previous one with a
---negative step, in the configured order.
---@param win integer
---@param step integer
function View:cycle(win, step)
    local current = self:type_of(vim.api.nvim_win_get_buf(win))

    for i, buffer in ipairs(config.buffers) do
        if buffer[1] == current then
            local next_index = (i - 1 + step) % #config.buffers + 1
            self:switch(win, config.buffers[next_index][1])
            return
        end
    end
end

---@param type nurl.BufferType
---@param win_config table
function View:toggle_secondary(type, win_config)
    if self.secondary and self.secondary:is_open() then
        self.secondary:close()
        return
    end

    local bufnr = self.buffers[type]
    if bufnr == nil then
        return
    end

    self.secondary = SecondaryWindow:new(win_config)
    self.secondary:open(bufnr, type)
end

---Create the buffers for the handle, with their mappings.
function View:_create_buffers()
    self.buffers = buffers.create(self.handle)

    local keys = {}
    for _, buffer in ipairs(config.buffers) do
        keys[buffer[1]] = buffer.keys
    end

    for type, bufnr in pairs(self.buffers) do
        views_by_buf[bufnr] = self
        vim.b[bufnr].nurl_data = { buffer_type = type }

        for lhs, action in pairs(keys[type] or {}) do
            vim.keymap.set(
                "n",
                lhs,
                keymap_rhs(action, self),
                { buffer = bufnr }
            )
        end

        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = bufnr,
            callback = function()
                -- Windows copy the winbar of the window they split from, so
                -- a split showing this buffer would show it too. Keep it to
                -- the response window.
                if vim.api.nvim_get_current_win() == self.win then
                    vim.wo[0].winbar = winbar.winbar()
                else
                    -- This is very important for the toggle_split action.
                    -- For some reason, the winbar will be shown in any window
                    -- this buffer is entered. Yes, even tho I set the winbar
                    -- in self.win only. I don't want the split window to
                    -- display the winbar too, so let's set it to an empty
                    -- string when the window isn't the main response window.
                    vim.wo[0].winbar = ""
                end
            end,
        })

        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = bufnr,
            once = true,
            callback = function()
                views_by_buf[bufnr] = nil
            end,
        })
    end
end

function View:_start_timer()
    if not self.handle:is_done() then
        self.elapsed_time = ElapsedTimeFloating:new(self.win)
        self.elapsed_time:start()
    end
end

function View:_stop_timer()
    if self.elapsed_time then
        self.elapsed_time:stop()
        self.elapsed_time = nil
    end
end

---Show another request in the window, replacing the buffers of the previous
---one.
---@param handle nurl.RequestHandle
---@param focus_buffer? nurl.BufferType
function View:show(handle, focus_buffer)
    local previous = self.buffers

    self:_stop_timer()
    self.handle = handle
    self:_create_buffers()

    vim.api.nvim_win_set_buf(
        self.win,
        self.buffers[focus_buffer or config.buffers[1][1]]
    )
    if self.secondary then
        self.secondary:show(self.buffers)
    end

    delete_buffers(previous)
    self:_start_timer()
end

---Render the request again, such as once it is done.
function View:update()
    if self.handle:is_done() then
        self:_stop_timer()
    end

    buffers.update(self.handle, self.buffers)
    vim.cmd.redrawstatus() -- make sure the winbar updates

    local raw = self.buffers[buffers.Buffer.Raw]
    if
        self.handle:is_failed()
        and raw
        and vim.api.nvim_win_is_valid(self.win)
    then
        vim.api.nvim_win_set_buf(self.win, raw)
    end
end

function View:close()
    if self.closed then
        return
    end
    self.closed = true

    self:_stop_timer()
    if self.secondary then
        self.secondary:close()
    end

    views_by_win[self.win] = nil
    delete_buffers(self.buffers)
end

---@class nurl.ResponseViewOpts
---@field win? integer window to show the request in, instead of a new one
---@field focus_buffer? nurl.BufferType
---@field enter? boolean

---Show a request, in a new window or in opts.win. A window that already
---shows a request is reused.
---@param handle nurl.RequestHandle
---@param opts? nurl.ResponseViewOpts
---@return nurl.ResponseView
function M.open(handle, opts)
    opts = opts or {}
    assert(#config.buffers > 0, "Must configure at least one response buffer")

    local existing = opts.win and views_by_win[opts.win]
    if existing then
        existing:show(handle, opts.focus_buffer)
        if opts.enter then
            vim.api.nvim_set_current_win(existing.win)
        end

        return existing
    end

    local view = setmetatable({ handle = handle, closed = false }, View)
    view:_create_buffers()

    local bufnr = view.buffers[opts.focus_buffer or config.buffers[1][1]]
    if opts.win and vim.api.nvim_win_is_valid(opts.win) then
        view.win = opts.win
        vim.api.nvim_win_set_buf(view.win, bufnr)
    else
        view.win = vim.api.nvim_open_win(bufnr, false, config.win_config)
    end

    views_by_win[view.win] = view

    vim.wo[view.win].winbar = winbar.winbar()

    vim.api.nvim_create_autocmd("WinClosed", {
        once = true,
        pattern = tostring(view.win),
        callback = function()
            -- The window is still open while WinClosed runs.
            vim.schedule(function()
                view:close()
            end)
        end,
    })

    if opts.enter then
        vim.api.nvim_set_current_win(view.win)
    end

    view:_start_timer()

    return view
end

return M

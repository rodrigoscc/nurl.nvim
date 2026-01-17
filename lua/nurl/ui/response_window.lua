local buffers = require("nurl.ui.buffers")
local winbar = require("nurl.ui.winbar")
local ElapsedTimeFloating = require("nurl.ui.elapsed_time")
local config = require("nurl.config")
local registry = require("nurl.registry")

---@class nurl.ResponseWindow
---@field private win integer | nil
---@field private handle_id integer
---@field private elapsed_time nurl.ElapsedTimeFloating | nil
---@field private buffers table<nurl.BufferType, integer> | nil
local ResponseWindow = {}

function ResponseWindow:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@class ResponseWindowOpts
---@field enter? boolean
---@field focus_buffer? nurl.BufferType

---@param opts? ResponseWindowOpts
function ResponseWindow:open(opts)
    opts = opts or {}

    local entry = registry:get(self.handle_id)

    self.buffers = buffers.create(self.handle_id)

    assert(#config.buffers > 0, "Must configure at least one response buffer")

    local focus_buffer = opts.focus_buffer or config.buffers[1][1]

    if self.win ~= nil and vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_set_buf(self.win, self.buffers[focus_buffer])
    else
        self.win = vim.api.nvim_open_win(
            self.buffers[focus_buffer],
            false,
            config.win_config
        )
    end

    entry.buffers = self.buffers
    entry.win = self.win

    if opts.enter then
        vim.api.nvim_set_current_win(self.win)
    end

    vim.wo[self.win].winbar = winbar.winbar()

    for _, bufnr in pairs(self.buffers) do
        vim.api.nvim_create_autocmd("BufWinEnter", {
            callback = function()
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
            buffer = bufnr,
        })
    end

    if entry.handle.response == nil then
        self.elapsed_time = ElapsedTimeFloating:new(self.win)
        self.elapsed_time:start()
    end

    -- Stop timer if parent window is closed
    vim.api.nvim_create_autocmd("WinClosed", {
        once = true,
        pattern = tostring(self.win),
        callback = function()
            if self.elapsed_time ~= nil then
                self.elapsed_time:stop()
            end
        end,
    })

    return self.win
end

function ResponseWindow:update()
    local entry = registry:get(self.handle_id)

    if entry.handle:is_done() and self.elapsed_time ~= nil then
        self.elapsed_time:stop()
    end

    assert(self.buffers ~= nil, "Buffers must already exist")
    buffers.update(self.handle_id, self.buffers)
    vim.cmd.redrawstatus() -- make sure the winbar updates

    if entry.handle:is_failed() and self.buffers[buffers.Buffer.Raw] then
        assert(self.win ~= nil, "Window should have been created already")
        vim.api.nvim_win_set_buf(self.win, self.buffers[buffers.Buffer.Raw])
    end
end

function ResponseWindow:on_buffers_unloaded(fn)
    for _, bufnr in pairs(self.buffers) do
        vim.api.nvim_create_autocmd("BufDelete", {
            buffer = bufnr,
            once = true,
            callback = function()
                for _, entry_bufnr in pairs(self.buffers) do
                    if
                        entry_bufnr ~= bufnr -- BufDelete buffer isn't considered unloaded just yet
                        and vim.api.nvim_buf_is_loaded(entry_bufnr)
                    then
                        return
                    end
                end

                fn()
            end,
        })
    end
end

return ResponseWindow

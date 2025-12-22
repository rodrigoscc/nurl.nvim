---@class nurl.SecondaryWindow
---@field win integer | nil
---@field buffers table<nurl.BufferType, integer> | nil
---@field win_config any
local SecondaryWindow = {}

function SecondaryWindow:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function SecondaryWindow:validate_win()
    if self.win ~= nil then
        if not vim.api.nvim_win_is_valid(self.win) then
            self.win = nil
        end
    end
end

function SecondaryWindow:close()
    if self.win == nil then
        return
    end

    if vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_close(self.win, true)
    end

    self.win = nil
end

function SecondaryWindow:toggle(buffer)
    self:validate_win()

    if self.win == nil then
        local new_buffer = self.buffers[buffer]
        if new_buffer == nil then
            return
        end

        self.win = vim.api.nvim_open_win(new_buffer, false, self.win_config)
        vim.wo[self.win].wrap = true

        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            pattern = tostring(vim.api.nvim_get_current_win()),
            callback = function()
                self:close()
            end,
        })
    else
        self:close()
    end
end

return SecondaryWindow

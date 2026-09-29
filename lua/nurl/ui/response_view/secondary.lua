---A split showing one more part of the response, such as the info next to
---the body.
---@class nurl.SecondaryWindow
---@field win integer | nil
---@field type nurl.BufferType | nil the part it shows
---@field win_config table
local SecondaryWindow = {}
SecondaryWindow.__index = SecondaryWindow

---@param win_config table
---@return nurl.SecondaryWindow
function SecondaryWindow:new(win_config)
    return setmetatable({ win_config = win_config }, self)
end

---@return boolean
function SecondaryWindow:is_open()
    return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

---Open the split next to the current window.
---@param bufnr integer
---@param type nurl.BufferType
function SecondaryWindow:open(bufnr, type)
    self.type = type
    self.win = vim.api.nvim_open_win(bufnr, false, self.win_config)
    vim.wo[self.win].wrap = true

    vim.api.nvim_create_autocmd("WinClosed", {
        once = true,
        pattern = tostring(vim.api.nvim_get_current_win()),
        callback = function()
            self:close()
        end,
    })
end

function SecondaryWindow:close()
    if self:is_open() then
        vim.api.nvim_win_close(self.win, true)
    end

    self.win = nil
end

---Show the same part of new buffers, such as after the request is sent again.
---@param buffers table<nurl.BufferType, integer>
function SecondaryWindow:show(buffers)
    if not self:is_open() then
        return
    end

    local bufnr = buffers[self.type]
    if bufnr then
        vim.api.nvim_win_set_buf(self.win, bufnr)
    else
        self:close()
    end
end

return SecondaryWindow

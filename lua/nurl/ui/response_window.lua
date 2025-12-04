local buffers = require("nurl.ui.buffers")
local winbar = require("nurl.ui.winbar")
local ElapsedTimeFloating = require("nurl.ui.elapsed_time")
local config = require("nurl.config")

---@class nurl.ResponseWindow
---@field win integer | nil
---@field request nurl.Request
---@field response? nurl.Response | nil
---@field curl nurl.Curl
---@field elapsed_time nurl.ElapsedTimeFloating | nil
---@field buffers table<nurl.BufferType, integer> | nil
local ResponseWindow = {}

function ResponseWindow:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@class ResponseWindowOpts
---@field enter? boolean

---@param opts? ResponseWindowOpts
function ResponseWindow:open(opts)
    opts = opts or {}

    self.buffers = buffers.create(self.request, self.response, self.curl)

    assert(#config.buffers > 0, "Must configure at least one response buffer")
    local first_buffer_type = config.buffers[1][1]

    if self.win ~= nil and vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_set_buf(self.win, self.buffers[first_buffer_type])
    else
        self.win = vim.api.nvim_open_win(
            self.buffers[first_buffer_type],
            false,
            config.win_config
        )
    end

    if opts.enter then
        vim.api.nvim_set_current_win(self.win)
    end

    vim.wo[self.win].winbar = winbar.winbar()

    for _, bufnr in pairs(self.buffers) do
        vim.api.nvim_create_autocmd("BufWinEnter", {
            once = true,
            callback = function()
                -- Use 0 instead of self.win here so that the correct win is used
                -- in case the user enters the buffers on other win.
                vim.wo[0].winbar = winbar.winbar()
            end,
            buffer = bufnr,
        })
    end

    if self.response == nil then
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

function ResponseWindow:update(response, curl)
    local curl_completed = curl.result ~= nil
    if curl_completed and self.elapsed_time ~= nil then
        self.elapsed_time:stop()
    end

    assert(self.buffers ~= nil, "Buffers must already exist")
    buffers.update(self.request, response, curl, self.buffers)
    vim.cmd.redrawstatus() -- make sure the winbar updates

    local curl_failed = curl_completed and curl.result.code ~= 0
    if curl_failed and self.buffers[buffers.Buffer.Raw] then
        assert(self.win ~= nil, "Window should have been created already")
        vim.api.nvim_win_set_buf(self.win, self.buffers[buffers.Buffer.Raw])
    end
end

return ResponseWindow

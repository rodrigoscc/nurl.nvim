local http_message = require("nurl.ui.http_message")

local M = {}

---The request as an HTTP message.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    local lines = http_message.request_to_http_message(handle.request)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_set_option_value("filetype", "http", { buf = bufnr })
end

return M

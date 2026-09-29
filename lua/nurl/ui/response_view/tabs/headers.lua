local responses = require("nurl.responses")

local M = {}

---The response status line and headers.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    local response = handle.response
    if response == nil then
        return
    end

    local headers_lines = {
        table.concat({
            response.protocol,
            response.status_code,
            response.reason_phrase,
        }, " "),
    }

    vim.list_extend(headers_lines, responses.header_lines(response))

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, headers_lines)
    vim.api.nvim_set_option_value("filetype", "http", { buf = bufnr })
end

return M

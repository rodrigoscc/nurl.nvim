local http = require("nurl.http")

local M = {}

---@param request nurl.Request
---@param response? nurl.Response
---@return string[]
function M.render(request, response)
    local lines = {}

    local request_lines = http.request_to_http_message(request)
    vim.list_extend(lines, request_lines)

    if response then
        local response_lines = http.response_to_http_message(response)
        vim.list_extend(lines, { "", "###", "" })
        vim.list_extend(lines, response_lines)
    end

    return lines
end

return M

local requests = require("nurl.requests")

---@class nurl.util
local M = {}

---@param url string | (string | number)[]
---@return string
function M.url(url)
    return requests.build_url(url)
end

---@param response nurl.Response
---@return table
function M.json(response)
    return vim.json.decode(response.body)
end

return M

local request_model = require("nurl.core.request")

---Text to show a request by, in pickers, previews and the winbar.
local M = {}

---@param url string
---@param query? table<string, any>
---@return string
local function with_query(url, query)
    if not query then
        return url
    end

    local items = {}
    for k, v in pairs(query) do
        for _, value in ipairs(type(v) == "table" and v or { v }) do
            table.insert(items, k .. "=" .. value)
        end
    end

    local separator = url:find("?", 1, true) and "&" or "?"
    return url .. separator .. table.concat(items, "&")
end

---The URL of a request, with its query.
---@param request nurl.Request
---@return string
function M.full_url(request)
    return with_query(request_model.build_url(request.url), request.query)
end

---@class nurl.RequestTextOpts
---@field prefix? string
---@field suffix? string

---The title of a request, or its method and full URL.
---Assumes no lazy objects remain in the request.
---@param request nurl.Request
---@param opts? nurl.RequestTextOpts
---@return string
function M.text(request, opts)
    opts = opts or {}

    local text = request.title
        or string.format("%s %s", request.method, M.full_url(request))

    if opts.suffix then
        text = text .. " " .. opts.suffix
    end

    if opts.prefix then
        text = opts.prefix .. " " .. text
    end

    return text
end

return M

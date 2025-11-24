local Curl = require("nurl.curl")
local variables = require("nurl.variables")

---@class nurl.Request
---@field method string
---@field url string
---@field headers table<string, string>
---@field data? string | table<string, any>
---@field form? table<string, string>
---@field data_urlencode? table<string, any>
---@field pre_hook? fun(next: fun()) | nil
---@field post_hook? fun(request: nurl.Request, response: nurl.Response | nil) | nil

---@class nurl.SuperRequest
---@field url string | table<string, any> | fun(): string | table<string, any>
---@field method? string
---@field headers? table<string, string> | fun(): table<string, string>
---@field data? string | table<string, any> | fun(): string | table<string, any>
---@field form? table<string, any> | fun(): table<string, any>
---@field data_urlencode? table<string, any> | fun(): table<string, any>
---@field pre_hook? fun(next: fun()) | nil
---@field post_hook? fun(request: nurl.Request, response: nurl.Response) | nil

local M = {}

---@param parts table<string, string | fun(): string>
local function build_url(parts)
    local expanded_parts = {}

    for _, v in pairs(parts) do
        if type(v) == "string" then
            local part = v:gsub("^/+", ""):gsub("/+$", "")
            table.insert(expanded_parts, part)
        elseif type(v) == "function" then
            local part = v()
            part = part:gsub("^/+", ""):gsub("/+$", "")
            table.insert(expanded_parts, part)
        end
    end

    return table.concat(expanded_parts, "/")
end

---@param request nurl.SuperRequest | nurl.Request
function M.expand(request)
    -- TODO: validate table

    assert(
        (not request.data and not request.form and not request.data_urlencode)
            or (request.data and not request.form and not request.data_urlencode)
            or (not request.data and request.form and not request.data_urlencode)
            or (
                not request.data
                and not request.form
                and request.data_urlencode
            ),
        "Only a single body field at the time is allowed"
    )

    local request_url = variables.expand(request.url)

    assert(request_url ~= nil, "Request must have a URL")

    ---@type string
    local url
    if type(request_url) == "string" then
        url = request_url
    else
        url = build_url(request_url)
    end

    local headers = variables.expand(request.headers)
    local data = variables.expand(request.data)
    local form = variables.expand(request.form)
    local data_urlencode = variables.expand(request.data_urlencode)

    ---@type nurl.Request
    local req = {
        url = url,
        method = request.method or "GET",
        headers = headers or {},
        data = data,
        form = form,
        data_urlencode = data_urlencode,
        pre_hook = request.pre_hook,
        post_hook = request.post_hook,
    }

    return req
end

---@param request nurl.Request
---@return nurl.Curl
function M.build_curl(request)
    local args = { "--request", request.method, request.url }

    if request.data then
        local data

        if type(request.data) == "table" then
            data = vim.json.encode(request.data)
        else
            data = request.data
        end

        table.insert(args, "--data")
        table.insert(args, data)
    elseif request.form then
        local form_items = {}

        for k, v in pairs(request.form) do
            table.insert(form_items, k .. "=" .. v)
        end

        for _, item in ipairs(form_items) do
            table.insert(args, "--form")
            table.insert(args, item)
        end
    elseif request.data_urlencode then
        local data_items = {}

        for k, v in pairs(request.data_urlencode) do
            table.insert(data_items, k .. "=" .. vim.uri_encode(v))
        end

        for _, item in ipairs(data_items) do
            table.insert(args, "--data-urlencode")
            table.insert(args, item)
        end
    end

    for k, v in pairs(request.headers) do
        local header = k .. ": " .. v
        table.insert(args, "--header")
        table.insert(args, header)
    end

    table.insert(args, "--include")
    table.insert(args, "--no-progress-meter")

    table.insert(args, "--write-out")
    table.insert(
        args,
        "%{stderr}%{time_appconnect},%{time_connect},%{time_namelookup},%{time_pretransfer},%{time_redirect},%{time_starttransfer},%{time_total},%{size_download},%{size_header},%{size_request},%{size_upload},%{speed_download},%{speed_upload}"
    )

    return Curl:new({ args = args })
end

return M

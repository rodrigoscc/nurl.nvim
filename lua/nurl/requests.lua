local Curl = require("nurl.curl")
local variables = require("nurl.variables")

---@class nurl.Request
---@field method string
---@field url string
---@field title? string
---@field headers table<string, string>
---@field data? string | table<string, any>
---@field form? table<string, string>
---@field data_urlencode? table<string, any>
---@field curl_args? string[]
---@field pre_hook? fun(next: fun(), request: nurl.Request | nurl.SuperRequest) | nil
---@field post_hook? fun(request: nurl.Request, response: nurl.Response | nil) | nil

---@class nurl.SuperRequest
---@field [1]? string
---@field url? string | table<string, any> | fun(): string | table<string, any>
---@field title? string | fun(): string
---@field method? string
---@field headers? table<string, string> | fun(): table<string, string>
---@field data? string | table<string, any> | fun(): string | table<string, any>
---@field form? table<string, any> | fun(): table<string, any>
---@field data_urlencode? table<string, any> | fun(): table<string, any>
---@field curl_args? string[] | fun(): string[]
---@field pre_hook? fun(next: fun(), request: nurl.Request | nurl.SuperRequest) | nil
---@field post_hook? fun(request: nurl.Request, response: nurl.Response) | nil

local M = {}

---@param parts table<string, string | fun(): string>
local function build_url(parts)
    local expanded_parts = {}

    for _, v in pairs(parts) do
        if type(v) == "string" then
            local part = v:gsub("^/+", ""):gsub("/+$", "")
            table.insert(expanded_parts, part)
        elseif type(v) == "number" then
            table.insert(expanded_parts, tostring(v))
        end
    end

    return table.concat(expanded_parts, "/")
end

---@param request nurl.SuperRequest | nurl.Request
---@param opts? nurl.ExpandOpts
function M.expand(request, opts)
    opts = opts or {}

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

    assert(
        (request[1] and not request.url and type(request[1]) == "string")
            or (request.url and not request[1]),
        "The request must have one and only one URL field"
    )

    local super_url
    if request[1] then
        super_url = request[1]
    else
        super_url = variables.expand(request.url, opts)
    end

    assert(super_url ~= nil, "Request must have a URL")

    local url
    if type(super_url) == "table" and not opts.lazy then
        url = build_url(super_url)
    else
        url = super_url
    end

    local headers = variables.expand(request.headers, opts)
    local data = variables.expand(request.data, opts)
    local form = variables.expand(request.form, opts)
    local data_urlencode = variables.expand(request.data_urlencode, opts)

    local title = variables.expand(request.title, opts)

    local curl_args = variables.expand(request.curl_args, opts)

    assert(
        title == nil or type(title) == "string",
        "Request title must be a string"
    )

    local method = "GET"
    if request.method ~= nil then
        method = request.method:upper()
    end

    ---@type nurl.Request|nurl.SuperRequest
    local req = {
        url = url,
        title = title,
        method = method,
        headers = headers or {},
        data = data,
        form = form,
        data_urlencode = data_urlencode,
        curl_args = curl_args,
        pre_hook = request.pre_hook,
        post_hook = request.post_hook,
    }

    return req
end

---@param request nurl.SuperRequest | nurl.Request
function M.stringify_lazy(request)
    local super_url
    if request[1] then
        super_url = request[1]
    else
        super_url = variables.stringify_lazy(request.url)
    end

    assert(super_url ~= nil, "Request must have a URL")

    ---@type string
    local url
    if type(super_url) == "string" then
        url = super_url
    else
        url = build_url(super_url)
    end

    local headers = variables.stringify_lazy(request.headers)
    local data = variables.stringify_lazy(request.data)
    local form = variables.stringify_lazy(request.form)
    local data_urlencode = variables.stringify_lazy(request.data_urlencode)

    local title = variables.stringify_lazy(request.title)

    local curl_args = variables.stringify_lazy(request.curl_args)

    -- Make sure the fields that are expected to be tables are still tables after calling stringify_lazy
    if type(headers) == "string" then
        headers = { [variables.LAZY_PLACEHOLDER] = variables.LAZY_PLACEHOLDER }
    end
    if type(form) == "string" then
        form = { [variables.LAZY_PLACEHOLDER] = variables.LAZY_PLACEHOLDER }
    end
    if type(data_urlencode) == "string" then
        data_urlencode =
            { [variables.LAZY_PLACEHOLDER] = variables.LAZY_PLACEHOLDER }
    end

    local method = "GET"
    if request.method ~= nil then
        method = request.method:upper()
    end

    ---@type nurl.Request
    local req = {
        url = url,
        title = title,
        method = method,
        headers = headers or {},
        data = data,
        form = form,
        data_urlencode = data_urlencode,
        curl_args = curl_args,
        pre_hook = request.pre_hook,
        post_hook = request.post_hook,
    }

    return req
end

local OUTPUT_FLAGS = {
    -- Redirect output
    "-o",
    "--output",
    "-O",
    "--remote-name",
    "-J",
    "--remote-header-name",

    -- Add extra output
    "-v",
    "--verbose",
    "--trace",
    "--trace-ascii",
    "-D",
    "--dump-header",

    -- Conflict with internal flags
    "-w",
    "--write-out",
    "--no-include",
    "--progress-meter",
}

local function contains_output_flags(extra_args)
    return vim.tbl_contains(OUTPUT_FLAGS, function(output_flag)
        return vim.tbl_contains(extra_args, function(arg)
            -- consider either --flag or --flag=something
            return arg == output_flag or string.find(arg, output_flag .. "=")
        end, { predicate = true })
    end, { predicate = true })
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

    if request.curl_args ~= nil then
        if contains_output_flags(request.curl_args) then
            error(
                "Blocked curl flags detected: these flags interfere with response parsing"
            )
        end

        vim.list_extend(args, request.curl_args)
    end

    return Curl:new({ args = args })
end

---@class nurl.RequestTextOpts
---@field prefix? string
---@field suffix? string

--- text computes the string representation of the request parameter
--- Assumes no lazy objects remain in the request.
---@param request nurl.Request
---@param opts? nurl.RequestTextOpts
---@return string
function M.text(request, opts)
    opts = opts or {}

    local title

    if request.title then
        title = request.title
    else
        title = string.format("%s %s", request.method, request.url)
    end

    if opts.suffix then
        title = title .. " " .. opts.suffix
    end

    if opts.prefix then
        title = opts.prefix .. " " .. title
    end

    return title
end

return M

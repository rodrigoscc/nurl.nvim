local Curl = require("nurl.curl")
local variables = require("nurl.variables")
local tables = require("nurl.utils.tables")

---@class nurl.RequestInput
---@field request nurl.Request

---@class nurl.RequestOut
---@field curl nurl.Curl
---@field request nurl.Request
---@field response? nurl.Response
---@field win? integer

---@class nurl.Request
---@field method string
---@field url string | (string | number)[]
---@field query? table<string, any>
---@field title? string
---@field headers table<string, string>
---@field data? string | table<string, any>
---@field form? table<string, string>
---@field data_urlencode? table<string, any>
---@field curl_args? string[]
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput) | nil
---@field post_hook? fun(out: nurl.RequestOut) | nil

---@class nurl.SuperRequest
---@field [1]? string
---@field url? string | (string | number | fun(): string | number)[] | fun(): string | (string | number)[]
---@field query? table<string, any> | fun(): table<string, any>
---@field title? string | fun(): string
---@field method? string
---@field headers? table<string, string> | fun(): table<string, string>
---@field data? string | table<string, any> | fun(): string | table<string, any>
---@field form? table<string, any> | fun(): table<string, any>
---@field data_urlencode? table<string, any> | fun(): table<string, any>
---@field curl_args? string[] | fun(): string[]
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput) | nil
---@field post_hook? fun(out: nurl.RequestOut) | nil

local M = {}

---@param url string | (string | number)[]
function M.build_url(url)
    if type(url) == "string" then
        return url
    end

    local expanded_parts = {}

    for _, v in ipairs(url) do
        if type(v) == "string" then
            local part = v:gsub("^/+", ""):gsub("/+$", "")
            table.insert(expanded_parts, part)
        elseif type(v) == "number" then
            table.insert(expanded_parts, tostring(v))
        end
    end

    return table.concat(expanded_parts, "/")
end

---@param url string
---@return string, table<string, any>?
function M.extract_query(url)
    local query_start = url:find("?")
    if not query_start then
        return url, nil
    end

    local url_only = url:sub(1, query_start - 1)
    local query_str = url:sub(query_start + 1)

    local query_items = vim.split(query_str, "&")

    local query = {}
    for _, item in ipairs(query_items) do
        local k, v = unpack(vim.split(item, "="))
        query = tables.collect_value(query, k, v)
    end

    return url_only, query
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
        "The request must have one and at most one URL field"
    )

    assert(
        type(request.url) ~= "table" or vim.islist(request.url),
        "A table url must be a list, not a dict"
    )

    local url, url_query
    if request[1] then
        url = request[1]
        ---@cast url string
        url, url_query = M.extract_query(url)

        url_query = variables.uri_encode(url_query)
    else
        url = variables.expand(request.url, opts)
    end

    url = variables.uri_encode(url)

    local query = variables.expand(request.query, opts)

    if url_query then
        query = tables.shallow_extend(url_query, query)
    end

    query = variables.uri_encode(query)

    assert(url ~= nil, "Request must have a URL")

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
        query = query,
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

    local url = M.build_url(super_url)
    ---@cast url string

    local query = variables.stringify_lazy(request.query)
    query = variables.uri_encode(query)

    local headers = variables.stringify_lazy(request.headers)
    local data = variables.stringify_lazy(request.data)
    local form = variables.stringify_lazy(request.form)
    local data_urlencode = variables.stringify_lazy(request.data_urlencode)

    local title = variables.stringify_lazy(request.title)
    ---@cast title string

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
        query = query,
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
    local url = M.build_url(request.url)
    local args = { "--request", request.method, url }

    if request.query then
        local query_items = {}
        for k, v in pairs(request.query) do
            if type(v) == "table" then
                for _, value_item in ipairs(v) do
                    table.insert(query_items, k .. "=" .. value_item)
                end
            else
                table.insert(query_items, k .. "=" .. v)
            end
        end

        for _, item in ipairs(query_items) do
            table.insert(args, "--url-query")
            table.insert(args, item)
        end
    end

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
            table.insert(data_items, k .. "=" .. variables.uri_encode(v))
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
        title = string.format("%s %s", request.method, M.build_url(request.url))
    end

    if opts.suffix then
        title = title .. " " .. opts.suffix
    end

    if opts.prefix then
        title = opts.prefix .. " " .. title
    end

    return title
end

---@param request nurl.Request
---@return string
function M.full_url(request)
    local url = M.build_url(request.url)

    if request.query then
        if url:match("?") then
            url = url .. "&"
        else
            url = url .. "?"
        end

        local query_items = {}

        for k, v in pairs(request.query) do
            if type(v) == "table" then
                for _, value_item in ipairs(v) do
                    table.insert(query_items, k .. "=" .. value_item)
                end
            else
                table.insert(query_items, k .. "=" .. v)
            end
        end

        url = url .. table.concat(query_items, "&")
    end

    return url
end

---@param request nurl.Request
---@return string
function M.title(request)
    if request.title then
        return request.title
    else
        return M.full_url(request)
    end
end

return M

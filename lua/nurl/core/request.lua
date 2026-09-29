local variables = require("nurl.core.variables")
local tables = require("nurl.utils.tables")

---@class nurl.RequestInput
---@field request nurl.Request

---@class nurl.RequestOut
---@field curl nurl.Curl
---@field request nurl.Request
---@field response? nurl.Response
---@field test_report? nurl.TestReport
---@field win? integer

---@class nurl.BasicAuth
---@field type "basic"
---@field username string
---@field password string

---@class nurl.Request
---@field method string
---@field url string | (string | number)[]
---@field query? table<string, any>
---@field title? string
---@field headers table<string, string | string[]>
---@field auth? nurl.BasicAuth
---@field data? string | table<string, any>
---@field form? table<string, string>
---@field data_urlencode? table<string, string>
---@field curl_args? string[]
---@field save_history? boolean
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput) | nil
---@field post_hook? fun(out: nurl.RequestOut) | nil
---@field test? fun(ctx: nurl.TestContext, response: nurl.Response)

---@class nurl.SuperRequest
---@field [1]? string
---@field url? string | (string | number | fun(): string | number)[] | fun(): string | (string | number)[]
---@field query? table<string, any> | fun(): table<string, any>
---@field title? string | fun(): string
---@field method? string
---@field headers? table<string, string | string[]> | fun(): table<string, string | string[]>
---@field auth? nurl.BasicAuth | fun(): nurl.BasicAuth
---@field data? string | table<string, any> | fun(): string | table<string, any>
---@field form? table<string, any> | fun(): table<string, any>
---@field data_urlencode? table<string, any> | fun(): table<string, any>
---@field curl_args? string[] | fun(): string[]
---@field save_history? boolean | fun(): boolean
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput) | nil
---@field post_hook? fun(out: nurl.RequestOut) | nil
---@field test? fun(ctx: nurl.TestContext, response: nurl.Response)

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
    else
        url = variables.expand(request.url, opts)
    end

    local query = variables.expand(request.query, opts)

    if url_query then
        query = tables.shallow_extend(url_query, query)
    end

    assert(url ~= nil, "Request must have a URL")

    local auth = variables.expand(request.auth, opts)

    local headers = variables.expand(request.headers, opts)
    local data = variables.expand(request.data, opts)
    local form = variables.expand(request.form, opts)
    local data_urlencode = variables.expand(request.data_urlencode, opts)

    local title = variables.expand(request.title, opts)

    local curl_args = variables.expand(request.curl_args, opts)
    local save_history = variables.expand(request.save_history, opts)

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
        auth = auth,
        headers = headers or {},
        data = data,
        form = form,
        data_urlencode = data_urlencode,
        curl_args = curl_args,
        save_history = save_history,
        pre_hook = request.pre_hook,
        post_hook = request.post_hook,
        test = request.test,
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

    local auth = variables.stringify_lazy(request.auth)

    local headers = variables.stringify_lazy(request.headers)
    local data = variables.stringify_lazy(request.data)
    local form = variables.stringify_lazy(request.form)
    local data_urlencode = variables.stringify_lazy(request.data_urlencode)

    local title = variables.stringify_lazy(request.title)
    ---@cast title string

    local curl_args = variables.stringify_lazy(request.curl_args)
    local save_history = variables.stringify_lazy(request.save_history)

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
        auth = auth,
        headers = headers or {},
        data = data,
        form = form,
        data_urlencode = data_urlencode,
        curl_args = curl_args,
        save_history = save_history,
        pre_hook = request.pre_hook,
        post_hook = request.post_hook,
        test = request.test,
    }

    return req
end

return M

local requests = require("nurl.requests")
local variables = require("nurl.variables")
local config = require("nurl.config")
local responses = require("nurl.responses")

local M = {}

---@param headers table<string, string>
---@param content_type string
---@return table<string, string>
local function ensure_content_type(headers, content_type)
    for name, _ in pairs(headers) do
        if string.lower(name) == "content-type" then
            return headers
        end
    end

    local new_headers = vim.deepcopy(headers)
    new_headers["Content-Type"] = content_type
    return new_headers
end

---@param form table<string, any>
---@return string
local function format_form_body(form)
    local lines = {}

    for k, v in pairs(form) do
        table.insert(lines, k .. "=" .. v)
    end

    return table.concat(lines, "\n")
end

---@param data table<string, any>
---@return string
local function format_urlencoded_body(data)
    local parts = {}

    for k, v in pairs(data) do
        table.insert(parts, k .. "=" .. variables.uri_encode(v))
    end

    return table.concat(parts, "&")
end

---@param content string
---@param headers table<string, string>
---@return string
local function format_body(content, headers)
    local file_type = responses.guess_file_type(headers)

    local formatter = config.formatters[file_type]
    if
        formatter ~= nil
        and (formatter.available == nil or formatter.available())
    then
        local result = vim.fn.system(formatter.cmd, content)
        if vim.v.shell_error == 0 then
            return vim.trim(result)
        end
    end

    return content
end

---@param request nurl.Request
---@return string[]
function M.request_to_http_message(request)
    local lines = {}

    local url = requests.full_url(request)
    table.insert(lines, request.method .. " " .. url)

    local headers = request.headers or {}
    local body = nil

    if request.data then
        if type(request.data) == "table" then
            -- we use --json in curl, which adds json content type
            headers = ensure_content_type(headers, "application/json")
            body = format_body(vim.json.encode(request.data), headers)
        else
            body = format_body(tostring(request.data), headers)
        end
    elseif request.form then
        -- we use --form in curl, which adds form content type
        headers = ensure_content_type(headers, "multipart/form-data")
        body = format_form_body(request.form)
    elseif request.data_urlencode then
        -- we use --data-urlencode in curl, which adds urlencode content type
        headers =
            ensure_content_type(headers, "application/x-www-form-urlencoded")
        body = format_urlencoded_body(request.data_urlencode)
    end

    for name, value in pairs(headers) do
        table.insert(lines, name .. ": " .. value)
    end

    if body then
        table.insert(lines, "") -- separation line

        local body_lines = vim.split(body, "\n")
        vim.list_extend(lines, body_lines)
    end

    return lines
end

---@param response nurl.Response
---@return string[]
function M.response_to_http_message(response)
    local lines = {}

    local start_line = response.protocol .. " "

    start_line = start_line .. tostring(response.status_code)

    if response.reason_phrase and response.reason_phrase ~= "" then
        start_line = start_line .. " " .. response.reason_phrase
    end

    table.insert(lines, start_line)

    for name, value in pairs(response.headers) do
        table.insert(lines, name .. ": " .. value)
    end

    if response.body ~= nil then
        table.insert(lines, "") -- separation line

        local body = format_body(response.body, response.headers)
        local body_lines = vim.split(body, "\n")

        vim.list_extend(lines, body_lines)
    elseif response.body_file then
        table.insert(lines, "") -- separation line
        table.insert(
            lines,
            "[Body saved to file: " .. response.body_file .. "]"
        )
    end

    return lines
end

return M

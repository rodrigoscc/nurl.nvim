local actions = require("nurl.actions")
local config = require("nurl.config")
local tables = require("nurl.utils.tables")

---@enum nurl.BufferType
local Buffer = {
    Body = "body",
    Headers = "headers",
    Raw = "raw",
}

---@class nurl.BufferAction
---@field [1] string
---@field opts table

---@class nurl.Buffer
---@field [1] nurl.BufferType?
---@field keys table<string, string|nurl.BufferAction>

local M = {}

---@param action string|nurl.BufferAction
local function expand_keymap_rhs(action)
    local rhs
    if type(action) == "string" then
        rhs = actions.builtin[action]()
    elseif type(action) == "table" and type(action[1]) == "string" then
        rhs = actions.builtin[action[1]](action.opts)
    else
        rhs = action
    end

    return rhs
end

local function get_content_type(headers)
    for name, value in pairs(headers) do
        if string.lower(name) == "content-type" then
            return value
        end
    end

    return nil
end

local function guess_file_type(headers)
    local content_type = get_content_type(headers)
    if content_type == nil then
        return "text"
    elseif
        string.find(content_type, "application/json")
        or string.find(content_type, "text/json")
    then
        return "json"
    elseif
        string.find(content_type, "application/xml")
        or string.find(content_type, "text/xml")
    then
        return "xml"
    elseif
        string.find(content_type, "application/html")
        or string.find(content_type, "text/html")
    then
        return "html"
    end

    return "text"
end

local function populate_body_buffer(bufnr, response)
    local body_lines = vim.split(response.body, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, body_lines)

    local file_type = guess_file_type(response.headers)
    vim.api.nvim_set_option_value("filetype", file_type, { buf = bufnr })
end

local function populate_headers_buffer(bufnr, response)
    local headers_lines = {
        table.concat({
            response.protocol,
            response.status_code,
            response.reason_phrase,
        }, " "),
    }

    for name, value in pairs(response.headers) do
        table.insert(headers_lines, name .. ": " .. value)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, headers_lines)
    vim.api.nvim_set_option_value("filetype", "http", { buf = bufnr })
end

local function populate_raw_buffer(bufnr, curl)
    local raw_lines = {}
    table.insert(raw_lines, curl:string())

    if curl.result then
        if curl.result.stdout then
            local stdout_lines = vim.split(curl.result.stdout, "\n")
            tables.extend(raw_lines, stdout_lines)
        end
        if curl.result.stderr then
            local stderr_lines = vim.split(curl.result.stderr, "\n")
            tables.extend(raw_lines, stderr_lines)
        end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, raw_lines)
end

---@param buffer nurl.Buffer
---@param request nurl.Request
---@param response nurl.Response | nil
---@param curl nurl.Curl
---@return integer bufnr the created buffer number
function M.create_buffer(buffer, request, response, curl)
    local buf = vim.api.nvim_create_buf(true, true)

    if buffer[1] == "body" then
        if response ~= nil then
            populate_body_buffer(buf, response)
        end
    elseif buffer[1] == "headers" then
        if response ~= nil then
            populate_headers_buffer(buf, response)
        end
    elseif buffer[1] == "raw" then
        populate_raw_buffer(buf, curl)
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = buf })
    end

    return buf
end

---@param buf integer
---@param buffer nurl.Buffer
---@param request nurl.Request
---@param response nurl.Response
---@param curl nurl.Curl
function M.update_buffer(buf, buffer, request, response, curl)
    if buffer[1] == "body" then
        populate_body_buffer(buf, response)
    elseif buffer[1] == "headers" then
        populate_headers_buffer(buf, response)
    elseif buffer[1] == "raw" then
        populate_raw_buffer(buf, curl)
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = buf })
    end

    return buf
end

---@param request nurl.Request
---@param response nurl.Response | nil
---@param curl nurl.Curl
---@return table<nurl.BufferType, integer>
function M.create(request, response, curl)
    ---@type table<nurl.BufferType, integer>
    local buffers = {}

    for _, buffer in ipairs(config.buffers) do
        local buf = M.create_buffer(buffer, request, response, curl)

        vim.b[buf].nurl_buffer_type = buffer[1]

        buffers[buffer[1]] = buf
    end

    for _, bufnr in pairs(buffers) do
        vim.b[bufnr].nurl_request = request
        vim.b[bufnr].nurl_response = response
        vim.b[bufnr].nurl_buffers = buffers
    end

    return buffers
end

---@param request nurl.Request
---@param response nurl.Response
---@param curl nurl.Curl
---@param buffers table<nurl.BufferType, integer>
function M.update(request, response, curl, buffers)
    for _, buffer in ipairs(config.buffers) do
        local buf = buffers[buffer[1]]
        M.update_buffer(buf, buffer, request, response, curl)

        for _, bufnr in pairs(buffers) do
            vim.b[bufnr].nurl_request = request
            vim.b[bufnr].nurl_response = response
            vim.b[bufnr].nurl_buffers = buffers
        end
    end
end

return M

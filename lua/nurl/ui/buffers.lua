local actions = require("nurl.actions")
local config = require("nurl.config")
local responses = require("nurl.responses")
local info_buffer = require("nurl.ui.info_buffer")

local M = {}

---@enum nurl.BufferType
M.Buffer = {
    Body = "body",
    Headers = "headers",
    Info = "info",
    Raw = "raw",
}

---@class nurl.BufferAction
---@field [1] string
---@field opts table

---@class nurl.Buffer
---@field [1] nurl.BufferType
---@field keys table<string, string|nurl.BufferAction>

---@class nurl.BufferData
---@field buffer_type nurl.BufferType
---@field request nurl.Request
---@field curl nurl.Curl
---@field buffers table<nurl.BufferType, integer>
---@field response? nurl.Response

---@param action string|nurl.BufferAction
---@return fun()
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

---@param headers table<string, string>
---@return string
local function guess_file_type(headers)
    local content_type = responses.get_content_type(headers)
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

---@param bufnr integer
---@param content string
---@param file_type string
local function set_body_buffer(bufnr, content, file_type)
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_set_option_value("filetype", file_type, { buf = bufnr })
end

local function open_file_in_buffer(bufnr, file)
    local existing_buffer = vim.fn.bufnr(file)
    if existing_buffer ~= -1 then
        -- Specially important for when the user opens a request in history which buffers are still open.
        vim.api.nvim_buf_delete(existing_buffer, { force = true })
    end

    vim.api.nvim_buf_set_name(bufnr, file)
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit") -- WORKAROUND: Snacks.image won't render the file without this
    end)
end

---@param bufnr integer
---@param response nurl.Response
local function populate_body_buffer(bufnr, response)
    if response.body_file then
        vim.schedule(function()
            open_file_in_buffer(bufnr, response.body_file)
        end)
        return
    end

    local file_type = guess_file_type(response.headers)
    local formatter = config.formatters[file_type]

    if
        formatter ~= nil
        and (formatter.available == nil or formatter.available())
    then
        vim.system(
            formatter.cmd,
            { text = true, stdin = response.body },
            function(out)
                vim.schedule(function()
                    local content
                    if out.code == 0 then
                        content = out.stdout or ""
                    else
                        content = response.body
                        vim.notify(
                            ('Formatter "%s" for "%s" failed: %s\n%s'):format(
                                formatter.cmd[1],
                                file_type,
                                out.stdout,
                                out.stderr
                            ),
                            vim.log.levels.ERROR
                        )
                    end
                    set_body_buffer(bufnr, content, file_type)
                end)
            end
        )
    else
        vim.schedule(function()
            set_body_buffer(bufnr, response.body, file_type)
        end)
    end
end

---@param bufnr integer
---@param response nurl.Response
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

---@param bufnr integer
---@param curl nurl.Curl
local function populate_raw_buffer(bufnr, curl)
    local raw_lines = {}
    table.insert(raw_lines, curl:string())

    if curl.result then
        if curl.result.stdout then
            local stdout_lines = vim.split(curl.result.stdout, "\n")
            vim.list_extend(raw_lines, stdout_lines)
        end
        if curl.result.stderr then
            local stderr_lines = vim.split(curl.result.stderr, "\n")
            vim.list_extend(raw_lines, stderr_lines)
        end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, raw_lines)
end

---@param bufnr integer
---@param request nurl.Request
---@param response nurl.Response
---@param curl nurl.Curl
local function populate_info_buffer(bufnr, request, response, curl)
    info_buffer.render(bufnr, request, response, curl)
end

---@param buffer nurl.Buffer
---@param request nurl.Request
---@param response nurl.Response | nil
---@param curl nurl.Curl
---@return integer bufnr the created buffer number
function M.create_buffer(buffer, request, response, curl)
    local buf = vim.api.nvim_create_buf(true, true)

    local type = buffer[1]

    if type == "body" then
        if response ~= nil then
            populate_body_buffer(buf, response)
        end
    elseif type == "headers" then
        if response ~= nil then
            populate_headers_buffer(buf, response)
        end
    elseif type == "info" then
        if response ~= nil then
            populate_info_buffer(buf, request, response, curl)
        end
    elseif type == "raw" then
        populate_raw_buffer(buf, curl)
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = buf })
    end

    return buf
end

---@param bufnr integer
---@param buffer nurl.Buffer
---@param request nurl.Request
---@param response nurl.Response | nil
---@param curl nurl.Curl
function M.update_buffer(bufnr, buffer, request, response, curl)
    if buffer[1] == "body" then
        if response ~= nil then
            populate_body_buffer(bufnr, response)
        end
    elseif buffer[1] == "headers" then
        if response ~= nil then
            populate_headers_buffer(bufnr, response)
        end
    elseif buffer[1] == "info" then
        if response ~= nil then
            populate_info_buffer(bufnr, request, response, curl)
        end
    elseif buffer[1] == "raw" then
        populate_raw_buffer(bufnr, curl)
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = bufnr })
    end

    return bufnr
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
        local type = buffer[1]
        buffers[type] = buf
    end

    for type, bufnr in pairs(buffers) do
        vim.b[bufnr].nurl_data = {
            request = request,
            response = response,
            curl = curl,
            buffers = buffers,
            buffer_type = type,
        }
    end

    return buffers
end

---@param request nurl.Request
---@param response nurl.Response | nil
---@param curl nurl.Curl
---@param buffers table<nurl.BufferType, integer>
function M.update(request, response, curl, buffers)
    for _, buffer in ipairs(config.buffers) do
        local type = buffer[1]
        local bufnr = buffers[type]
        M.update_buffer(bufnr, buffer, request, response, curl)
    end

    for type, bufnr in pairs(buffers) do
        vim.b[bufnr].nurl_data = {
            request = request,
            response = response,
            curl = curl,
            buffers = buffers,
            buffer_type = type,
        }
    end
end

return M

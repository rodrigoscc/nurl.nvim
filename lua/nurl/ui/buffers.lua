local actions = require("nurl.actions")
local config = require("nurl.config")
local http = require("nurl.http")
local responses = require("nurl.responses")
local info_buffer = require("nurl.ui.info_buffer")
local test_buffer = require("nurl.ui.test_buffer")
local registry = require("nurl.registry")

local M = {}

---@enum nurl.BufferType
M.Buffer = {
    Body = "body",
    Headers = "headers",
    Info = "info",
    Raw = "raw",
    Request = "request",
    Test = "test",
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
---@field has_test_failures boolean

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

    local file_type = responses.guess_file_type(response.headers)
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
                        content = vim.trim(out.stdout) or ""
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
---@param request nurl.Request
local function populate_request_buffer(bufnr, request)
    local lines = http.request_to_http_message(request)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_set_option_value("filetype", "http", { buf = bufnr })
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
        if type(value) == "table" then
            for _, item in ipairs(value) do
                table.insert(headers_lines, name .. ": " .. item)
            end
        else
            table.insert(headers_lines, name .. ": " .. value)
        end
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
---@param exec_datetime string
---@param request nurl.Request
---@param response nurl.Response
local function populate_info_buffer(bufnr, exec_datetime, request, response)
    info_buffer.render(bufnr, exec_datetime, request, response)
end

---@param bufnr integer
---@param test_report? nurl.TestReport
local function populate_test_buffer(bufnr, test_report)
    test_buffer.render(bufnr, test_report)
end

---@param buffer nurl.Buffer
---@param exec_datetime string
---@param request nurl.Request
---@param response? nurl.Response
---@param curl? nurl.Curl
---@param test_report? nurl.TestReport
---@return integer bufnr the created buffer number
local function create_buffer(
    buffer,
    exec_datetime,
    request,
    response,
    curl,
    test_report
)
    local buf = vim.api.nvim_create_buf(true, true)

    local type = buffer[1]

    if type == "body" then
        if response ~= nil then
            populate_body_buffer(buf, response)
        end
    elseif type == "request" then
        populate_request_buffer(buf, request)
    elseif type == "headers" then
        if response ~= nil then
            populate_headers_buffer(buf, response)
        end
    elseif type == "info" then
        if response ~= nil then
            populate_info_buffer(buf, exec_datetime, request, response)
        end
    elseif type == "test" then
        if response ~= nil then
            populate_test_buffer(buf, test_report)
        end
    elseif type == "raw" then
        if curl ~= nil then
            populate_raw_buffer(buf, curl)
        end
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = buf })
    end

    return buf
end

---@param bufnr integer
---@param buffer nurl.Buffer
---@param exec_datetime string
---@param request nurl.Request
---@param response? nurl.Response
---@param curl nurl.Curl
---@param test_report? nurl.TestReport
local function update_buffer(
    bufnr,
    buffer,
    exec_datetime,
    request,
    response,
    curl,
    test_report
)
    if buffer[1] == "body" then
        if response ~= nil then
            populate_body_buffer(bufnr, response)
        end
    elseif buffer[1] == "request" then
        populate_request_buffer(bufnr, request)
    elseif buffer[1] == "headers" then
        if response ~= nil then
            populate_headers_buffer(bufnr, response)
        end
    elseif buffer[1] == "info" then
        if response ~= nil then
            populate_info_buffer(bufnr, exec_datetime, request, response)
        end
    elseif buffer[1] == "test" then
        if response ~= nil then
            populate_test_buffer(bufnr, test_report)
        end
    elseif buffer[1] == "raw" then
        if curl ~= nil then
            populate_raw_buffer(bufnr, curl)
        end
    end

    for lhs, rhs in pairs(buffer.keys) do
        local expanded_rhs = expand_keymap_rhs(rhs)
        vim.keymap.set("n", lhs, expanded_rhs, { buffer = bufnr })
    end

    return bufnr
end

---@param handle_id integer
---@return table<nurl.BufferType, integer>
function M.create(handle_id)
    local entry = registry:get(handle_id)
    local handle = entry.handle

    ---@type table<nurl.BufferType, integer>
    local buffers = {}

    for _, buffer in ipairs(config.buffers) do
        local buf = create_buffer(
            buffer,
            handle.exec_datetime,
            handle.request,
            handle.response,
            handle.curl,
            handle.test_report
        )
        local type = buffer[1]
        buffers[type] = buf
    end

    for type, bufnr in pairs(buffers) do
        vim.b[bufnr].nurl_data = {
            handle_id = handle_id,
            buffer_type = type,
        }
    end

    return buffers
end

---@param handle_id integer
---@param buffers table<nurl.BufferType, integer>
function M.update(handle_id, buffers)
    local entry = registry:get(handle_id)
    local handle = entry.handle

    for _, buffer in ipairs(config.buffers) do
        local type = buffer[1]
        local bufnr = buffers[type]
        update_buffer(
            bufnr,
            buffer,
            handle.exec_datetime,
            handle.request,
            handle.response,
            handle.curl,
            handle.test_report
        )
    end
end

return M

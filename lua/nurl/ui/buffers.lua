local config = require("nurl.config")
local http = require("nurl.http")
local responses = require("nurl.responses")
local info_buffer = require("nurl.ui.info_buffer")
local test_buffer = require("nurl.ui.test_buffer")

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

---@param bufnr integer
---@param content string
---@param file_type string
local function set_body_buffer(bufnr, content, file_type)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_set_option_value("filetype", file_type, { buf = bufnr })
end

local function open_file_in_buffer(bufnr, file)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local existing_buffer = vim.fn.bufnr(file)
    if existing_buffer ~= -1 then
        -- Specially important for when the user opens a request in history which buffers are still open.
        vim.api.nvim_buf_delete(existing_buffer, { force = true })
    end

    vim.api.nvim_buf_set_name(bufnr, file)
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit") -- WORKAROUND: Snacks.image won't render the file without this
    end)
    -- above :edit lists the buffer, so mark it as unlisted again.
    vim.bo[bufnr].buflisted = false
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

    vim.list_extend(headers_lines, responses.header_lines(response))

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

---Fill a buffer with its part of the request. Parts that need the response
---stay empty until the request is done.
---@param bufnr integer
---@param type nurl.BufferType
---@param handle nurl.RequestHandle
local function render(bufnr, type, handle)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local response = handle.response

    if type == M.Buffer.Body then
        if response ~= nil then
            populate_body_buffer(bufnr, response)
        end
    elseif type == M.Buffer.Request then
        populate_request_buffer(bufnr, handle.request)
    elseif type == M.Buffer.Headers then
        if response ~= nil then
            populate_headers_buffer(bufnr, response)
        end
    elseif type == M.Buffer.Info then
        if response ~= nil then
            populate_info_buffer(
                bufnr,
                handle.exec_datetime,
                handle.request,
                response
            )
        end
    elseif type == M.Buffer.Test then
        if response ~= nil then
            populate_test_buffer(bufnr, handle.test_report)
        end
    elseif type == M.Buffer.Raw then
        if handle.curl ~= nil then
            populate_raw_buffer(bufnr, handle.curl)
        end
    end
end

---Create a buffer for every configured part of the request.
---@param handle nurl.RequestHandle
---@return table<nurl.BufferType, integer>
function M.create(handle)
    ---@type table<nurl.BufferType, integer>
    local buffers = {}

    for _, buffer in ipairs(config.buffers) do
        local type = buffer[1]
        local bufnr = vim.api.nvim_create_buf(false, true)
        buffers[type] = bufnr
        render(bufnr, type, handle)
    end

    return buffers
end

---Render the buffers again, such as once the request is done.
---@param handle nurl.RequestHandle
---@param buffers table<nurl.BufferType, integer>
function M.update(handle, buffers)
    for type, bufnr in pairs(buffers) do
        render(bufnr, type, handle)
    end
end

return M

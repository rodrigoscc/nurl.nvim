local tables = require("nurl.utils.tables")

local M = {}

---@class nurl.ResponseTime
---@field time_appconnect number
---@field time_connect number
---@field time_namelookup number
---@field time_pretransfer number
---@field time_redirect number
---@field time_starttransfer number
---@field time_total number

---@class nurl.ResponseSize
---@field size_download number
---@field size_header number
---@field size_request number
---@field size_upload number

---@class nurl.ResponseSpeed
---@field speed_download number
---@field speed_upload number

---@class nurl.Response
---@field status_code integer
---@field reason_phrase string
---@field protocol string
---@field headers table<string, string | string[]>
---@field header_list? [string, string][] headers in the order the server sent them
---@field body string
---@field body_file? string
---@field time nurl.ResponseTime
---@field size nurl.ResponseSize
---@field speed nurl.ResponseSpeed

---@param lines string[]
---@return table<string, string | string[]> headers
---@return [string, string][] header_list headers in the order they were sent
local function parse_headers(lines)
    local headers = {}
    local header_list = {}

    for _, line in ipairs(lines) do
        -- Trim to remove extra space chars, since we're not using {text = true} in vim.system
        local parts = vim.split(vim.trim(line), ": ")
        local name = parts[1]
        local value = table.concat(parts, ": ", 2)

        headers = tables.collect_value(headers, name, value)
        table.insert(header_list, { name, value })
    end

    return headers, header_list
end

---Header lines in the order the server sent them. Responses without a
---recorded order, such as those saved in history by older versions, list
---their headers alphabetically.
---@param response nurl.Response
---@return string[]
function M.header_lines(response)
    local lines = {}

    if response.header_list then
        for _, header in ipairs(response.header_list) do
            table.insert(lines, header[1] .. ": " .. header[2])
        end
        return lines
    end

    local names = vim.tbl_keys(response.headers)
    table.sort(names)
    for _, name in ipairs(names) do
        local value = response.headers[name]
        for _, item in ipairs(type(value) == "table" and value or { value }) do
            table.insert(lines, name .. ": " .. item)
        end
    end

    return lines
end

--- Extracts the protocol, status code and reason phrase from the start line.
---@param line string request line
---@return string, number, string
local function parse_start_line(line)
    local splits = vim.split(line, " ")

    local protocol = splits[1]
    local status_code_str = splits[2]
    local reason_phrase = table.concat(splits, " ", 3)

    local status_code = tonumber(status_code_str)
    if status_code == nil then
        error(("Invalid status line: %q"):format(line), 0)
    end

    return protocol, status_code, reason_phrase or ""
end

---@param headers table<string, string | string[]>
---@return string|nil
function M.get_content_type(headers)
    for name, value in pairs(headers) do
        if
            string.lower(name) == "content-type"
            and type(value) == "string" -- list in content-type header is considered invalid
        then
            return string.lower(value)
        end
    end

    return nil
end

---@param headers table<string, string | string[]>
---@return string
function M.guess_file_type(headers)
    local content_type = M.get_content_type(headers)
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

local displayable_content_types = {
    "application/json",
    "application/xml",
    "application/javascript",
    "application/x-yaml",
    "text/html",
    "text/plain",
    "text/css",
    "text/csv",
    "text/xml",
    "text/javascript",
    "text/markdown",
}

local content_type_to_ext = {
    -- Images
    ["image/png"] = "png",
    ["image/jpeg"] = "jpg",
    ["image/gif"] = "gif",
    ["image/webp"] = "webp",
    ["image/svg+xml"] = "svg",
    ["image/bmp"] = "bmp",
    ["image/tiff"] = "tiff",
    ["image/x-icon"] = "ico",

    -- Documents
    ["application/pdf"] = "pdf",
    ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = "xlsx",
    ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = "docx",
    ["application/vnd.openxmlformats-officedocument.presentationml.presentation"] = "pptx",
    ["application/vnd.ms-excel"] = "xls",
    ["application/vnd.ms-powerpoint"] = "ppt",
    ["application/msword"] = "doc",

    -- Archives
    ["application/zip"] = "zip",
    ["application/gzip"] = "gz",
    ["application/x-tar"] = "tar",
    ["application/x-7z-compressed"] = "7z",
    ["application/x-rar-compressed"] = "rar",

    -- Text/Code
    ["application/json"] = "json",
    ["application/xml"] = "xml",
    ["application/javascript"] = "js",
    ["application/x-yaml"] = "yaml",
    ["text/html"] = "html",
    ["text/plain"] = "txt",
    ["text/css"] = "css",
    ["text/csv"] = "csv",
    ["text/xml"] = "xml",
    ["text/javascript"] = "js",
    ["text/markdown"] = "md",

    -- Audio
    ["audio/mpeg"] = "mp3",
    ["audio/wav"] = "wav",
    ["audio/ogg"] = "ogg",

    -- Video
    ["video/mp4"] = "mp4",
    ["video/webm"] = "webm",
    ["video/ogg"] = "ogv",

    -- Other
    ["application/octet-stream"] = "bin",
}

---@param response nurl.Response
---@return boolean
function M.is_displayable(response)
    local empty_response = vim.trim(response.body) == ""
    if empty_response then
        return true
    end

    local content_type = M.get_content_type(response.headers)
    if not content_type then
        return false
    end

    for _, displayable_content_type in ipairs(displayable_content_types) do
        if string.find(content_type, displayable_content_type) then
            return true
        end
    end

    return false
end

---The file extension for the content type, to save the body with.
---@param headers table<string, string | string[]>
---@param fallback? string Default: "bin"
---@return string
function M.file_extension(headers, fallback)
    fallback = fallback or "bin"

    local content_type = M.get_content_type(headers)
    if content_type then
        local subtype = content_type_to_ext[content_type]
        if subtype then
            return subtype:lower()
        end
    end

    return fallback
end

---The last header block in curl's --include output. Curl prints a block for
---every response it receives: proxy CONNECT replies, 1xx responses such as
---100 Continue, and each redirect followed with --location. Only the last
---one belongs to the final response.
---@param headers string all header blocks
---@return string[] lines status line followed by the header lines
local function final_header_lines(headers)
    local blocks = vim.split(headers, "\r?\n\r?\n", { trimempty = true })
    return vim.split(blocks[#blocks], "\r?\n")
end

---@param stdout string curl output: all header blocks followed by the body
---@param stderr string curl stderr, ending with the --write-out metrics
---@return nurl.Response
function M.parse(stdout, stderr)
    -- Other messages curl writes to stderr come before the metrics, which are
    -- written once the transfer is done.
    local stderr_lines = vim.split(vim.trim(stderr), "\n")

    local metrics_line = vim.trim(stderr_lines[#stderr_lines])

    local time_appconnect, time_connect, time_namelookup, time_pretransfer, time_redirect, time_starttransfer, time_total, size_download, size_header, size_request, size_upload, speed_download, speed_upload =
        unpack(vim.iter(vim.split(metrics_line, ","))
            :map(function(value)
                return tonumber(value)
            end)
            :totable())

    if size_header == nil then
        error(
            ("Could not find the curl metrics in stderr: %q"):format(stderr),
            0
        )
    end
    if size_header > #stdout then
        error(
            ("Curl reported %d bytes of headers but printed %d bytes"):format(
                size_header,
                #stdout
            ),
            0
        )
    end

    if size_header == 0 then
        error("Curl printed no response headers", 0)
    end

    local header_lines = final_header_lines(stdout:sub(1, size_header))

    local protocol, status_code, reason_phrase =
        parse_start_line(header_lines[1])
    local headers, header_list = parse_headers(vim.list_slice(header_lines, 2))

    local body_file = nil -- should be populated later
    local body = stdout:sub(size_header + 1)

    return {
        protocol = protocol,
        status_code = status_code,
        reason_phrase = reason_phrase,
        headers = headers,
        header_list = header_list,
        body = body,
        body_file = body_file,
        time = {
            time_appconnect = time_appconnect,
            time_connect = time_connect,
            time_namelookup = time_namelookup,
            time_pretransfer = time_pretransfer,
            time_redirect = time_redirect,
            time_starttransfer = time_starttransfer,
            time_total = time_total,
        },
        size = {
            size_download = size_download,
            size_header = size_header,
            size_request = size_request,
            size_upload = size_upload,
        },
        speed = {
            speed_download = speed_download,
            speed_upload = speed_upload,
        },
    }
end

return M

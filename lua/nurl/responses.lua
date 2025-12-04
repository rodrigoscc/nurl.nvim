local config = require("nurl.config")

local fs = require("nurl.data.fs")

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
---@field headers table<string, string>
---@field body string
---@field body_file? string
---@field time nurl.ResponseTime
---@field size nurl.ResponseSize
---@field speed nurl.ResponseSpeed

---@param lines string[]
---@return table<string, string>
local function parse_headers(lines)
    local headers = {}

    for _, line in ipairs(lines) do
        -- Trim to remove extra space chars, since we're not using {text = true} in vim.system
        local parts = vim.split(vim.trim(line), ": ")
        local name = parts[1]
        local value = table.concat(parts, ": ", 2)

        headers[name] = value
    end

    return headers
end

--- Extracts the protocol, status code and reason phrase from the start line.
---@param line string request line
---@return string, number, string
local function parse_start_line(line)
    local protocol, status_code_str, reason_phrase =
        unpack(vim.split(line, " "))

    local status_code = tonumber(status_code_str)
    if status_code == nil then
        vim.notify(
            "Start line contained an invalid status code: " .. status_code_str,
            vim.log.levels.WARN
        )
        status_code = 0
    end

    return protocol, status_code, reason_phrase or ""
end

---@param headers table<string, string>
---@return string|nil
function M.get_content_type(headers)
    for name, value in pairs(headers) do
        if string.lower(name) == "content-type" then
            return string.lower(value)
        end
    end

    return nil
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

---@param headers table<string, string>
---@return boolean
local function is_displayable(headers)
    local content_type = M.get_content_type(headers)
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

---@param headers table<string, string>
---@param fallback string
---@return string
local function guess_extension(headers, fallback)
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

---@param stdout string[]
---@param stderr string[]
---@return nurl.Response
function M.parse(stdout, stderr)
    local separation_line_idx = vim.iter(ipairs(stdout)):find(function(_, line)
        -- Trim to remove extra space chars, since we're not using {text = true} in vim.system
        return vim.trim(line) == ""
    end)

    local start_line = vim.trim(stdout[1])

    local headers_lines =
        vim.iter(stdout):slice(2, separation_line_idx - 1):totable()
    local body_lines =
        vim.iter(stdout):slice(separation_line_idx + 1, #stdout):totable()

    local headers = parse_headers(headers_lines)

    local protocol, status_code, reason_phrase = parse_start_line(start_line)

    local time_line = vim.trim(stderr[1])
    local time_appconnect, time_connect, time_namelookup, time_pretransfer, time_redirect, time_starttransfer, time_total, size_download, size_header, size_request, size_upload, speed_download, speed_upload =
        unpack(vim.iter(vim.split(time_line, ","))
            :map(function(time)
                return tonumber(time)
            end)
            :totable())

    local body_file = nil
    local body = table.concat(body_lines, "\n")

    local is_body_displayable = is_displayable(headers)
    if not is_body_displayable then
        local extension = guess_extension(headers, "bin")
        -- TODO: what about too large files here?
        local unique_path =
            fs.unique_path(config.responses_files_dir, "response", extension)
        fs.write(unique_path, body)

        body_file = unique_path
        body = ""
    end

    return {
        protocol = protocol,
        status_code = status_code,
        reason_phrase = reason_phrase,
        headers = headers,
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

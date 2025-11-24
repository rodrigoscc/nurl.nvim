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
---@field time nurl.ResponseTime
---@field size nurl.ResponseSize
---@field speed nurl.ResponseSpeed

---@param lines string[]
local function parse_headers(lines)
    local headers = {}

    for _, line in ipairs(lines) do
        local parts = vim.split(line, ": ")
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

    return protocol, status_code, reason_phrase
end

---@param stdout string[]
---@param stderr string[]
---@return nurl.Response
function M.parse(stdout, stderr)
    local separation_line_idx = vim.iter(ipairs(stdout)):find(function(_, line)
        return line == ""
    end)

    local start_line = stdout[1]
    local headers_lines =
        vim.iter(stdout):slice(2, separation_line_idx - 1):totable()
    local body_lines =
        vim.iter(stdout):slice(separation_line_idx + 1, #stdout):totable()

    local headers = parse_headers(headers_lines)

    local protocol, status_code, reason_phrase = parse_start_line(start_line)

    local time_appconnect, time_connect, time_namelookup, time_pretransfer, time_redirect, time_starttransfer, time_total, size_download, size_header, size_request, size_upload, speed_download, speed_upload =
        unpack(vim.iter(vim.split(stderr[1], ","))
            :map(function(time)
                return tonumber(time)
            end)
            :totable())

    return {
        protocol = protocol,
        status_code = status_code,
        reason_phrase = reason_phrase,
        headers = headers,
        body = table.concat(body_lines, "\n"),
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

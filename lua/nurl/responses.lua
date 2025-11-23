local M = {}

---@class nurl.Response
---@field status_code integer
---@field reason_phrase string
---@field protocol string
---@field headers table<string, string>
---@field body string
---@field time number

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

    local total_time = tonumber(stderr[1])
    if total_time == nil then
        vim.notify(
            "Could not parse total time from stderr: "
                .. table.concat(stderr, "\n"),
            vim.log.levels.WARN
        )
    end

    return {
        protocol = protocol,
        status_code = status_code,
        reason_phrase = reason_phrase,
        headers = headers,
        body = table.concat(body_lines, "\n"),
        time = total_time,
    }
end

return M

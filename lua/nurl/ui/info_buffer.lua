local strings = require("nurl.utils.strings")
local requests = require("nurl.requests")
local numbers = require("nurl.utils.numbers")

local M = {}

local ns = vim.api.nvim_create_namespace("nurl.info")

local icons = {
    section = "▸",
    download = "↓",
    upload = "↑",
    query_first = "?",
    query_next = "&",
}

---@param method string
---@return string
local function get_method_highlight(method)
    local method_highlights = {
        GET = "NurlInfoMethodGet",
        POST = "NurlInfoMethodPost",
        PUT = "NurlInfoMethodPut",
        PATCH = "NurlInfoMethodPatch",
        DELETE = "NurlInfoMethodDelete",
        HEAD = "NurlInfoMethodHead",
        OPTIONS = "NurlInfoMethodOptions",
    }
    return method_highlights[method] or "NurlInfoMethod"
end

---@param status_code number
---@return string
local function get_status_highlight(status_code)
    if status_code >= 200 and status_code < 300 then
        return "NurlInfoStatusSuccess"
    elseif status_code >= 300 and status_code < 400 then
        return "NurlInfoStatusRedirect"
    elseif status_code >= 400 and status_code < 500 then
        return "NurlInfoStatusClientError"
    elseif status_code >= 500 then
        return "NurlInfoStatusServerError"
    else
        return "NurlInfoStatus"
    end
end

---@class InfoLine
---@field text string
---@field highlights {col_start: number, col_end: number, hl_group: string}[]

---@class InfoBufferBuilder
---@field lines InfoLine[]
---@field current_line number
local InfoBufferBuilder = {}

function InfoBufferBuilder:new()
    local o = {
        lines = {},
        current_line = 0,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

---@param text string
---@param hl_group? string
function InfoBufferBuilder:append(text, hl_group)
    if not self.lines[self.current_line + 1] then
        self.lines[self.current_line + 1] = { text = "", highlights = {} }
    end

    local line = self.lines[self.current_line + 1]
    local col_start = #line.text

    line.text = line.text .. text

    if hl_group then
        table.insert(line.highlights, {
            col_start = col_start,
            col_end = col_start + #text,
            hl_group = hl_group,
        })
    end

    return self
end

function InfoBufferBuilder:newline()
    self.current_line = self.current_line + 1
    return self
end

---@param label string
function InfoBufferBuilder:section(label)
    if #self.lines > 0 then
        self:newline()
    end

    self:append(icons.section .. " ", "NurlInfoIcon")
    self:append(label, "NurlInfoLabel")

    return self
end

---@param label string
---@param value string
---@param value_hl? string
---@param label_width? number
function InfoBufferBuilder:field(label, value, value_hl, label_width)
    label_width = label_width or 12

    self:newline()
    self:append("    ", nil)
    self:append(
        string.format("%-" .. label_width .. "s", label),
        "NurlInfoLabel"
    )
    self:append(value, value_hl or "NurlInfoValue")

    return self
end

---@param prefix string
---@param key string
---@param value string
function InfoBufferBuilder:query_param(prefix, key, value)
    self:newline()

    self:append("    ", nil)
    self:append(prefix .. " ", "NurlInfoSeparator")
    self:append(key, "NurlInfoQueryKey")
    self:append(" = ", "NurlInfoSeparator")
    self:append(value, "NurlInfoQueryValue")

    return self
end

---@param text string
function InfoBufferBuilder:muted_right(text)
    self:append("  " .. text, "Comment")
    return self
end

---@return string[], {line: number, col_start: number, col_end: number, hl_group: string}[]
function InfoBufferBuilder:build()
    local text_lines = {}
    local all_highlights = {}

    for i, line in ipairs(self.lines) do
        table.insert(text_lines, line.text)

        for _, hl in ipairs(line.highlights) do
            table.insert(all_highlights, {
                line = i - 1,
                col_start = hl.col_start,
                col_end = hl.col_end,
                hl_group = hl.hl_group,
            })
        end
    end

    return text_lines, all_highlights
end

---@param bufnr integer
---@param request nurl.Request
---@param response nurl.Response
---@param curl nurl.Curl
function M.render(bufnr, request, response, curl)
    local builder = InfoBufferBuilder:new()

    local base_url = requests.build_url(request.url)
    base_url = strings.escape_percentage(base_url)

    builder:section("Request")
    builder:append("       ", nil)
    builder:append(curl.exec_datetime, "Comment")
    builder:field(
        "Method",
        request.method,
        get_method_highlight(request.method)
    )
    builder:field("URL", base_url, "NurlInfoUrl")

    if request.query then
        local is_first = true

        for k, v in pairs(request.query) do
            if type(v) == "table" then
                for _, value_item in ipairs(v) do
                    if type(value_item) == "string" then
                        value_item = strings.escape_percentage(value_item)
                    end

                    local prefix = is_first and icons.query_first
                        or icons.query_next

                    builder:query_param(prefix, k, tostring(value_item))

                    is_first = false
                end
            else
                if type(v) == "string" then
                    v = strings.escape_percentage(v)
                end

                local prefix = is_first and icons.query_first
                    or icons.query_next

                builder:query_param(prefix, k, tostring(v))

                is_first = false
            end
        end
    end

    local status_text
    if response.reason_phrase ~= "" then
        status_text =
            string.format("%d %s", response.status_code, response.reason_phrase)
    else
        status_text = string.format("%d", response.status_code)
    end

    builder:section("Response")
    builder:field(
        "Status",
        status_text,
        get_status_highlight(response.status_code)
    )
    builder:field("Protocol", response.protocol)

    if response.body_file then
        builder:field("File", response.body_file, "NurlInfoUrl")
    end

    local time = response.time
    builder:section("Timing")
    builder:field("DNS", numbers.format_duration(time.time_namelookup))
    builder:field("Connect", numbers.format_duration(time.time_connect))
    builder:field("TLS", numbers.format_duration(time.time_appconnect))
    builder:field("Pretransfer", numbers.format_duration(time.time_pretransfer))
    builder:field("TTFB", numbers.format_duration(time.time_starttransfer))
    builder:field("Redirect", numbers.format_duration(time.time_redirect))
    builder:field(
        "Total",
        numbers.format_duration(time.time_total),
        "NurlInfoHighlight"
    )

    local size = response.size
    builder:section("Size")
    builder:field("Download", numbers.format_bytes(size.size_download))
    builder:field("Upload", numbers.format_bytes(size.size_upload))
    builder:field("Headers", numbers.format_bytes(size.size_header))
    builder:field("Request", numbers.format_bytes(size.size_request))

    local speed = response.speed
    builder:section("Speed")
    builder:field("Download", numbers.format_speed(speed.speed_download))
    builder:field("Upload", numbers.format_speed(speed.speed_upload))

    local lines, highlights = builder:build()

    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(
            bufnr,
            ns,
            hl.line,
            hl.col_start,
            { end_col = hl.col_end, hl_group = hl.hl_group }
        )
    end

    vim.api.nvim_set_option_value("filetype", "", { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

return M

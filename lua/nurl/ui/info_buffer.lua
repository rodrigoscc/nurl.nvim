local config = require("nurl.config")
local strings = require("nurl.utils.strings")
local requests = require("nurl.requests")
local numbers = require("nurl.utils.numbers")

local M = {}

local ns = vim.api.nvim_create_namespace("nurl.info")

local icons = {
    query_first = "?",
    query_next = "&",
    timing_bar = "█",
    timing_tick = "▏",
}

local timing_bar_width = 20
local timing_value_width = 7
local timing_label_width = 13

---@param value number
---@return number
local function non_negative(value)
    if value < 0 then
        return 0
    end

    return value
end

---@param value number
---@return number
local function round(value)
    -- Lua has no built-in round. Adding 0.5 before floor rounds positive values to nearest integer.
    return math.floor(value + 0.5)
end

---@param status_code number
---@return string
local function get_status_highlight(status_code)
    if status_code >= 200 and status_code < 300 then
        return config.highlight.groups.info_status_success
    elseif status_code >= 300 and status_code < 400 then
        return config.highlight.groups.info_status_redirect
    elseif status_code >= 400 and status_code < 500 then
        return config.highlight.groups.info_status_client_error
    elseif status_code >= 500 then
        return config.highlight.groups.info_status_server_error
    else
        return config.highlight.groups.info_status
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

function InfoBufferBuilder:blankline()
    self:newline()
    self.lines[self.current_line + 1] = { text = "", highlights = {} }
    return self
end

function InfoBufferBuilder:indent()
    self:append("  ", nil)
    return self
end

---@param label string
function InfoBufferBuilder:section(label)
    if #self.lines > 0 then
        self:blankline()
        self:newline()
    end

    self:append(label, config.highlight.groups.info_section)

    return self
end

---@param text string
---@param hl_group? string
function InfoBufferBuilder:indented_line(text, hl_group)
    self:newline()
    self:indent()
    self:append(text, hl_group or config.highlight.groups.info_value)

    return self
end

---@param label string
---@param value string
---@param value_hl? string
---@param label_width? number
function InfoBufferBuilder:field(label, value, value_hl, label_width)
    label_width = label_width or 13

    self:newline()
    self:indent()
    self:append(
        string.format("%-" .. label_width .. "s", label:lower()),
        config.highlight.groups.info_label
    )
    self:append(value, value_hl or config.highlight.groups.info_value)

    return self
end

---@param prefix string
---@param key string
---@param value string
function InfoBufferBuilder:query_param(prefix, key, value)
    self:newline()

    self:indent()
    self:append(prefix .. " ", config.highlight.groups.info_separator)
    self:append(key, config.highlight.groups.info_query_key)
    self:append(" = ", config.highlight.groups.info_separator)
    self:append(value, config.highlight.groups.info_query_value)

    return self
end

---@param label string
---@param value string
---@param duration number
---@param total number
function InfoBufferBuilder:timing_field(label, value, duration, total)
    self:newline()
    self:indent()
    self:append(
        string.format("%-" .. timing_label_width .. "s", label:lower()),
        config.highlight.groups.info_label
    )
    self:append(
        string.format("%" .. timing_value_width .. "s", value),
        config.highlight.groups.info_value
    )
    self:append("  ", nil)

    local ratio = 0
    if total > 0 and duration > 0 then
        ratio = duration / total
    end

    local exact_bar_len = ratio * timing_bar_width
    local bar_len = round(exact_bar_len)
    if bar_len > timing_bar_width then
        bar_len = timing_bar_width
    end

    if duration <= 0 or exact_bar_len < 1 then
        self:append(icons.timing_tick, config.highlight.groups.info_separator)
    else
        self:append(
            string.rep(icons.timing_bar, bar_len),
            config.highlight.groups.info_timing_bar
        )
    end

    return self
end

---@param label string
---@param value string
function InfoBufferBuilder:timing_total(label, value)
    self:newline()
    self:indent()
    self:append(
        string.format("%-" .. timing_label_width .. "s", label:lower()),
        config.highlight.groups.info_label
    )
    self:append(
        string.format("%" .. timing_value_width .. "s", value),
        config.highlight.groups.info_highlight
    )

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
---@param exec_datetime string
---@param request nurl.Request
---@param response nurl.Response
function M.render(bufnr, exec_datetime, request, response)
    local builder = InfoBufferBuilder:new()

    local base_url = requests.build_url(request.url)
    base_url = strings.escape_percentage(base_url)

    builder:section("Request")

    builder:newline()
    builder:indent()
    builder:append(request.method, config.highlight.groups.info_method)
    builder:append(" ", nil)
    builder:append(base_url, config.highlight.groups.info_url)

    builder:indented_line("sent " .. exec_datetime, "Comment")

    if request.title then
        builder:field(
            "title",
            request.title,
            config.highlight.groups.info_title
        )
    end

    if request.query and next(request.query) then
        builder:section("Query")

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
        "status",
        status_text,
        get_status_highlight(response.status_code)
    )
    builder:field("protocol", response.protocol)

    if response.body_file then
        builder:field(
            "file",
            response.body_file,
            config.highlight.groups.info_url
        )
    end

    local time = response.time
    builder:section("Timing")

    local dns = non_negative(time.time_namelookup)
    local tcp = non_negative(time.time_connect - time.time_namelookup)
    local has_tls = time.time_appconnect > 0
    local tls = has_tls
            and non_negative(time.time_appconnect - time.time_connect)
        or 0
    local setup_end = has_tls and time.time_appconnect or time.time_connect
    local pretransfer = non_negative(time.time_pretransfer - setup_end)
    local server = non_negative(time.time_starttransfer - time.time_pretransfer)
    local redirect = non_negative(time.time_redirect)
    local transfer = non_negative(time.time_total - time.time_starttransfer)

    builder:timing_field(
        "dns",
        numbers.format_duration(dns),
        dns,
        time.time_total
    )
    builder:timing_field(
        "tcp",
        numbers.format_duration(tcp),
        tcp,
        time.time_total
    )
    builder:timing_field(
        "tls",
        numbers.format_duration(tls),
        tls,
        time.time_total
    )
    builder:timing_field(
        "pretransfer",
        numbers.format_duration(pretransfer),
        pretransfer,
        time.time_total
    )
    builder:timing_field(
        "server",
        numbers.format_duration(server),
        server,
        time.time_total
    )
    builder:timing_field(
        "redirect",
        numbers.format_duration(redirect),
        redirect,
        time.time_total
    )
    builder:timing_field(
        "transfer",
        numbers.format_duration(transfer),
        transfer,
        time.time_total
    )
    builder:blankline()
    builder:timing_total("total", numbers.format_duration(time.time_total))

    local size = response.size
    builder:section("Size")
    builder:field("download", numbers.format_bytes(size.size_download))
    builder:field("upload", numbers.format_bytes(size.size_upload))
    builder:field("headers", numbers.format_bytes(size.size_header))
    builder:field("request", numbers.format_bytes(size.size_request))

    local speed = response.speed
    builder:section("Speed")
    builder:field("download", numbers.format_speed(speed.speed_download))
    builder:field("upload", numbers.format_speed(speed.speed_upload))

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

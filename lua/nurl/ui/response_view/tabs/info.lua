local config = require("nurl.config")
local highlights = require("nurl.ui.highlights")
local strings = require("nurl.utils.strings")
local requests = require("nurl.core.request")
local numbers = require("nurl.utils.numbers")
local TextBuilder = require("nurl.ui.text_builder")
local tables = require("nurl.utils.tables")

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

---Builder with the helpers of the info layout.
---@class InfoBufferBuilder: nurl.TextBuilder
local InfoBufferBuilder = setmetatable({}, { __index = TextBuilder })
InfoBufferBuilder.__index = InfoBufferBuilder

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

local expiry_warning_days = 30

---How long until the certificate expires, and how to highlight it.
---@param expires_at? integer seconds since the epoch
---@return string? text, string hl_group
local function expiry(expires_at)
    if expires_at == nil then
        return nil, config.highlight.groups.info_value
    end

    local seconds = expires_at - os.time()
    local days = math.floor(math.abs(seconds) / 86400)
    local days_text = days == 1 and "1 day" or ("%d days"):format(days)

    if seconds < 0 then
        return "expired " .. days_text .. " ago",
            config.highlight.groups.info_error
    elseif days < expiry_warning_days then
        return "in " .. days_text, config.highlight.groups.info_warning
    end

    return "in " .. days_text, config.highlight.groups.info_value
end

---@param builder InfoBufferBuilder
---@param tls nurl.ResponseTls
local function render_certificate(builder, tls)
    builder:section("Certificate")

    if tls.verify_reason then
        builder:field(
            "verify",
            "not verified: " .. tls.verify_reason,
            config.highlight.groups.info_error
        )
    else
        builder:field("verify", "ok", config.highlight.groups.info_ok)
    end

    local cert = tls.certs[1]
    if cert == nil then
        return
    end

    if cert.subject then
        builder:field("subject", cert.subject)
    end
    if cert.san then
        builder:field("names", (cert.san:gsub("DNS:", "")))
    end
    if cert.issuer then
        builder:field("issuer", cert.issuer)
    end
    if cert.start_date then
        builder:field("valid from", cert.start_date)
    end
    if cert.expire_date then
        local text, hl_group = expiry(cert.expires_at)
        builder:field("expires", cert.expire_date, hl_group)
        if text then
            builder:muted_right(text)
        end
    end

    if #tls.certs > 1 then
        for i, chain_cert in ipairs(tls.certs) do
            -- Without a label, the rest line up under the first.
            builder:field(i == 1 and "chain" or "", chain_cert.common_name or "?")
        end
    end
end

---Timing, size and speed of the request, with its URL and query.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    local request, response = handle.request, handle.response
    if response == nil then
        return
    end
    local exec_datetime = handle.exec_datetime

    local builder = InfoBufferBuilder:new() --[[@as InfoBufferBuilder]]

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

        for k, v in tables.sorted_pairs(request.query) do
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
        highlights.status_group(response.status_code)
    )
    builder:field("protocol", response.protocol)

    if response.body_file then
        builder:field(
            "file",
            response.body_file,
            config.highlight.groups.info_url
        )
    end

    if response.tls then
        render_certificate(builder, response.tls)
    end

    local time = response.time
    builder:section("Timing")

    -- Timings are missing if curl's timing output could not be parsed.
    local has_timing = true
    for _, key in ipairs({
        "time_namelookup",
        "time_connect",
        "time_appconnect",
        "time_pretransfer",
        "time_starttransfer",
        "time_redirect",
        "time_total",
    }) do
        if time[key] == nil then
            has_timing = false
        end
    end

    if not has_timing then
        builder:field("timing", "unavailable")
    else
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
    end

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

    builder:render(bufnr, ns)
    vim.api.nvim_set_option_value("filetype", "", { buf = bufnr })
end

return M

local Curl = require("nurl.core.curl")
local certificate = require("nurl.core.certificate")
local requests = require("nurl.core.request")
local tables = require("nurl.utils.tables")

---How requests and responses are stored as history rows.
local M = {}

---@alias nurl.HistoryItem [string, nurl.Request, nurl.Response, nurl.Curl]

---@class nurl.HistorySummary
---@field id integer
---@field time string
---@field method string
---@field url string
---@field title? string
---@field status integer
---@field duration? number

---The columns saved for a request, in the order encode returns them.
M.INSERT_COLUMNS = {
    "time",
    "request_url",
    "request_url_raw",
    "request_query",
    "request_title",
    "request_method",
    "request_auth",
    "request_headers",
    "request_data",
    "request_form",
    "request_data_urlencode",
    "request_curl_args",
    "response_status_code",
    "response_reason_phrase",
    "response_protocol",
    "response_headers",
    "response_body",
    "response_body_file",
    "response_time_appconnect",
    "response_time_connect",
    "response_time_namelookup",
    "response_time_pretransfer",
    "response_time_redirect",
    "response_time_starttransfer",
    "response_time_total",
    "response_size_download",
    "response_size_header",
    "response_size_request",
    "response_size_upload",
    "response_speed_download",
    "response_speed_upload",
    "curl_args",
    "curl_result_code",
    "curl_result_signal",
    "curl_result_stdout",
    "curl_result_stderr",
    "response_tls",
}

---The columns decode reads, in its order. The raw URL is only for searching.
M.ITEM_COLUMNS = vim.tbl_filter(function(column)
    return column ~= "request_url_raw"
end, M.INSERT_COLUMNS)

---The columns summary reads, in its order.
M.SUMMARY_COLUMNS = {
    "id",
    "time",
    "request_method",
    "request_url_raw",
    "request_title",
    "response_status_code",
    "response_time_total",
}

---The columns request reads, in its order.
M.REQUEST_COLUMNS = {
    "request_url",
    "request_query",
    "request_method",
    "request_headers",
    "request_data",
    "request_form",
    "request_data_urlencode",
}

---@param value any
---@return string | userdata JSON, or vim.NIL for nil
local function json(value)
    return value ~= nil and vim.json.encode(value) or vim.NIL
end

---The values of a completed request, for INSERT_COLUMNS.
---@param handle nurl.RequestHandle
---@return any[]
function M.encode(handle)
    local request = handle.request
    local response = handle.response
    local curl = handle.curl

    assert(response ~= nil, "Request must be completed")
    assert(curl ~= nil, "Request must be completed")

    return {
        handle.exec_datetime,
        vim.json.encode(request.url),
        requests.build_url(request.url),
        json(request.query),
        request.title or vim.NIL,
        request.method,
        json(request.auth),
        json(request.headers),
        json(request.data),
        json(request.form),
        json(request.data_urlencode),
        json(request.curl_args),
        response.status_code,
        response.reason_phrase,
        response.protocol,
        -- Save headers as [name, value] pairs so their order is kept.
        response.headers
                and vim.json.encode(response.header_list or response.headers)
            or vim.NIL,
        response.body,
        response.body_file or vim.NIL,
        response.time.time_appconnect,
        response.time.time_connect,
        response.time.time_namelookup,
        response.time.time_pretransfer,
        response.time.time_redirect,
        response.time.time_starttransfer,
        response.time.time_total,
        response.size.size_download,
        response.size.size_header,
        response.size.size_request,
        response.size.size_upload,
        response.speed.speed_download,
        response.speed.speed_upload,
        vim.json.encode(curl.args) or vim.NIL,
        curl.result.code,
        curl.result.signal,
        curl.result.stdout,
        -- The certificate chain takes several KB for each request, and is
        -- saved parsed in response_tls.
        curl.result.stderr and certificate.replace_chain(curl.result.stderr),
        json(response.tls),
    }
end

---Response headers are saved as [name, value] pairs, or as a name to value
---table by older versions.
---@param json_text string
---@return table<string, string | string[]> headers
---@return [string, string][]? header_list
local function decode_headers(json_text)
    local value = vim.json.decode(json_text)
    if not vim.islist(value) then
        return value, nil
    end

    local headers = {}
    for _, header in ipairs(value) do
        headers = tables.collect_value(headers, header[1], header[2])
    end
    return headers, value
end

---@param row nurl.Row with ITEM_COLUMNS
---@return nurl.HistoryItem
function M.decode(row)
    local function decode(index)
        local value = row:get_string(index)
        return value and vim.json.decode(value)
    end

    local headers, header_list
    local response_headers = row:get_string(15)
    if response_headers then
        headers, header_list = decode_headers(response_headers)
    end

    ---@type nurl.Request
    local request = {
        title = row:get_string(4),
        url = decode(2),
        query = decode(3),
        method = row:get_string(5),
        auth = decode(6),
        headers = decode(7),
        data = decode(8),
        form = decode(9),
        data_urlencode = decode(10),
        curl_args = decode(11),
    }

    ---@type nurl.Response
    local response = {
        status_code = row:get_number(12),
        reason_phrase = row:get_string(13),
        protocol = row:get_string(14),
        headers = headers,
        header_list = header_list,
        body = row:get_string(16),
        body_file = row:get_string(17),
        time = {
            time_appconnect = row:get_number(18),
            time_connect = row:get_number(19),
            time_namelookup = row:get_number(20),
            time_pretransfer = row:get_number(21),
            time_redirect = row:get_number(22),
            time_starttransfer = row:get_number(23),
            time_total = row:get_number(24),
        },
        size = {
            size_download = row:get_number(25),
            size_header = row:get_number(26),
            size_request = row:get_number(27),
            size_upload = row:get_number(28),
        },
        speed = {
            speed_download = row:get_number(29),
            speed_upload = row:get_number(30),
        },
        tls = decode(36),
    }

    ---@type nurl.Curl
    local curl = Curl:new({
        args = decode(31),
        result = {
            code = row:get_number(32),
            signal = row:get_number(33),
            stdout = row:get_string(34),
            stderr = row:get_string(35),
        },
    })

    return { row:get_string(1), request, response, curl }
end

---@param columns (string | userdata)[] values of SUMMARY_COLUMNS, vim.NIL for NULL
---@return nurl.HistorySummary
function M.summary(columns)
    local function text(index)
        local value = columns[index]
        return value ~= vim.NIL and value or nil
    end

    return {
        id = tonumber(text(1)),
        time = text(2),
        method = text(3),
        url = text(4),
        title = text(5),
        status = tonumber(text(6)),
        duration = tonumber(text(7)),
    }
end

---The request of an entry, without its response.
---@param row nurl.Row with REQUEST_COLUMNS
---@return nurl.Request
function M.request(row)
    local function decode(index)
        local value = row:get_string(index)
        return value and vim.json.decode(value)
    end

    return {
        url = decode(1),
        query = decode(2),
        method = row:get_string(3),
        headers = decode(4) or {},
        data = decode(5),
        form = decode(6),
        data_urlencode = decode(7),
    }
end

return M

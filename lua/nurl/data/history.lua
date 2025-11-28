local config = require("nurl.config")
local Curl = require("nurl.curl")

local M = {}

---@alias nurl.HistoryItem [nurl.Request, nurl.Response, nurl.Curl]

---@type nurl.Db | nil
M.db = nil

function M.setup()
    local Db = require("nurl.data.db")

    M.db = Db:new(config.history.db_file)

    local group = vim.api.nvim_create_augroup("nurl.history", {})
    vim.api.nvim_create_autocmd("ExitPre", {
        group = group,
        callback = function()
            if M.db then
                M.db:close()
                M.db = nil
            end
        end,
    })
end

---@param request nurl.Request
---@param response nurl.Response
---@param curl nurl.Curl
function M.insert_history_entry(request, response, curl)
    if M.db == nil then
        M.setup()
    end

    local result = M.db:exec(
        [[INSERT INTO
  request_history (
    time,
    request_url,
    request_method,
    request_headers,
    request_data,
    request_form,
    request_data_urlencode,
    response_status_code,
    response_reason_phrase,
    response_protocol,
    response_headers,
    response_body,
    response_body_file,
    response_time_appconnect,
    response_time_connect,
    response_time_namelookup,
    response_time_pretransfer,
    response_time_redirect,
    response_time_starttransfer,
    response_time_total,
    response_size_download,
    response_size_header,
    response_size_request,
    response_size_upload,
    response_speed_download,
    response_speed_upload,
    curl_args,
    curl_result_code,
    curl_result_signal,
    curl_result_stdout,
    curl_result_stderr
  )
VALUES
  (
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?
  );]],
        {
            curl.exec_datetime,
            request.url,
            request.method,
            request.headers and vim.json.encode(request.headers) or vim.NIL,
            request.data and vim.json.encode(request.data) or vim.NIL,
            request.form and vim.json.encode(request.form) or vim.NIL,
            request.data_urlencode and vim.json.encode(request.data_urlencode)
                or vim.NIL,
            response.status_code,
            response.reason_phrase,
            response.protocol,
            response.headers and vim.json.encode(response.headers) or vim.NIL,
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
            curl.result.stderr,
        }
    )

    result:close()

    M.delete_old_items()
end

function M.delete_old_items()
    local result = M.db:exec(
        [[DELETE FROM request_history
WHERE id IN (
  SELECT id FROM request_history
  ORDER BY time ASC
  LIMIT ?
)
AND (SELECT COUNT(*) FROM request_history) >= ?;]],
        {
            config.history.history_buffer,
            config.history.max_history_items + config.history.history_buffer,
        }
    )

    result:close()
end

---@return nurl.HistoryItem[]
function M.all()
    if M.db == nil then
        M.setup()
    end

    local result = M.db:exec([[SELECT
  time,
  request_url,
  request_method,
  request_headers,
  request_data,
  request_form,
  request_data_urlencode,
  response_status_code,
  response_reason_phrase,
  response_protocol,
  response_headers,
  response_body,
  response_body_file,
  response_time_appconnect,
  response_time_connect,
  response_time_namelookup,
  response_time_pretransfer,
  response_time_redirect,
  response_time_starttransfer,
  response_time_total,
  response_size_download,
  response_size_header,
  response_size_request,
  response_size_upload,
  response_speed_download,
  response_speed_upload,
  curl_args,
  curl_result_code,
  curl_result_signal,
  curl_result_stdout,
  curl_result_stderr
FROM
  request_history
ORDER BY time DESC]])

    local rows = result:all()
    result:close()

    ---@type nurl.HistoryItem[]
    local history = {}

    for _, row in ipairs(rows) do
        local time = row:get_string(1)
        local request_url = row:get_string(2)
        local request_method = row:get_string(3)
        local request_headers = row:get_string(4)
        local request_data = row:get_string(5)
        local request_form = row:get_string(6)
        local request_data_urlencode = row:get_string(7)
        local response_status_code = row:get_number(8)
        local response_reason_phrase = row:get_string(9)
        local response_protocol = row:get_string(10)
        local response_headers = row:get_string(11)
        local response_body = row:get_string(12)
        local response_body_file = row:get_string(13)
        local response_time_appconnect = row:get_number(14)
        local response_time_connect = row:get_number(15)
        local response_time_namelookup = row:get_number(16)
        local response_time_pretransfer = row:get_number(17)
        local response_time_redirect = row:get_number(18)
        local response_time_starttransfer = row:get_number(19)
        local response_time_total = row:get_number(20)
        local response_size_download = row:get_number(21)
        local response_size_header = row:get_number(22)
        local response_size_request = row:get_number(23)
        local response_size_upload = row:get_number(24)
        local response_speed_download = row:get_number(25)
        local response_speed_upload = row:get_number(26)
        local curl_args = row:get_string(27)
        local curl_result_code = row:get_number(28)
        local curl_result_signal = row:get_number(29)
        local curl_result_stdout = row:get_string(30)
        local curl_result_stderr = row:get_string(31)

        ---@type nurl.Request
        local request = {
            method = request_method,
            url = request_url,
            headers = request_headers and vim.json.decode(request_headers),
            data = request_data and vim.json.decode(request_data),
            form = request_form and vim.json.decode(request_form),
            data_urlencode = request_data_urlencode
                and vim.json.decode(request_data_urlencode),
        }

        ---@type nurl.Response
        local response = {
            status_code = response_status_code,
            reason_phrase = response_reason_phrase,
            protocol = response_protocol,
            headers = response_headers and vim.json.decode(response_headers),
            body = response_body,
            body_file = response_body_file,
            time = {
                time_appconnect = response_time_appconnect,
                time_connect = response_time_connect,
                time_namelookup = response_time_namelookup,
                time_pretransfer = response_time_pretransfer,
                time_redirect = response_time_redirect,
                time_starttransfer = response_time_starttransfer,
                time_total = response_time_total,
            },
            size = {
                size_download = response_size_download,
                size_header = response_size_header,
                size_request = response_size_request,
                size_upload = response_size_upload,
            },
            speed = {
                speed_download = response_speed_download,
                speed_upload = response_speed_upload,
            },
        }

        ---@type nurl.Curl
        local curl = Curl:new({
            args = vim.json.decode(curl_args),
            result = {
                code = curl_result_code,
                signal = curl_result_signal,
                stdout = curl_result_stdout,
                stderr = curl_result_stderr,
            },
            exec_datetime = time,
        })

        table.insert(history, { request, response, curl })
    end

    return history
end

return M

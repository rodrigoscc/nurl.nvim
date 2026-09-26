local config = require("nurl.config")
local Curl = require("nurl.curl")
local fs = require("nurl.data.fs")
local worker_root = require("nurl.data.worker_root")
local requests = require("nurl.requests")
local tables = require("nurl.utils.tables")

local uv = vim.uv or vim.loop

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

---@class nurl.HistoryFilters
---@field search? string
---@field method? string
---@field status? string
---@field from? string
---@field to? string
---@field request_body? string
---@field response_body? string
---@field response_file? "yes" | "no" whether the response body was saved to a file

---@type nurl.Db | nil
M.db = nil

local SQLITE_DONE = 101

local INSERT_ENTRY = [[INSERT INTO
request_history (
    time,
    request_url,
    request_url_raw,
    request_query,
    request_title,
    request_method,
    request_auth,
    request_headers,
    request_data,
    request_form,
    request_data_urlencode,
    request_curl_args,
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
    ?,
    ?,
    ?,
    ?,
    ?,
    ?
);]]

---@return string? err
local function delete_body_file(path)
    local removed, err, name = uv.fs_unlink(path)
    if not removed and name ~= "ENOENT" then
        return ("Could not remove history response file %s: %s"):format(
            path,
            err
        )
    end

    -- Each response is saved in its own directory. Leave the directory alone
    -- if another file is present rather than recursively deleting it.
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if dir then
        local success, dir_err, dir_name = uv.fs_rmdir(dir)
        if
            not success
            and dir_name ~= "ENOENT"
            and dir_name ~= "ENOTEMPTY"
            and dir_name ~= "EEXIST"
        then
            return ("Could not remove history response directory %s: %s"):format(
                dir,
                dir_err
            )
        end
    end
end

---Delete matching entries along with their saved response files.
---@param where string
---@param binds any[]
local function delete_entries(where, binds)
    local result = M.db:exec(
        "DELETE FROM request_history WHERE "
            .. where
            .. " RETURNING response_body_file",
        binds
    )
    local rows = result:all()
    local code = result.code
    result:close()
    assert(code == SQLITE_DONE, "Failed to delete request history")

    local failures = {}
    for _, row in ipairs(rows) do
        local body_file = row:get_string(1)
        local err = body_file and delete_body_file(body_file)
        if err then
            table.insert(failures, err)
        end
    end
    if #failures > 0 then
        error(table.concat(failures, "\n"))
    end
end

-- Most entries deleted when a request is saved, so one save never stalls.
local PRUNE_BATCH = 1000

---@param query string
---@return integer
local function count(query)
    local result = M.db:exec(query)
    local value = result:one():get_number(1)
    result:close()
    return value
end

---Keep at most `history.max_history_items` entries, deleting the oldest in the
---same (time, id) order as the history explorer.
function M.delete_old_items()
    local max_items = config.history.max_history_items
    assert(
        type(max_items) == "number" and max_items >= 1 and max_items % 1 == 0,
        "history.max_history_items must be a positive integer"
    )

    -- Counting reads every entry, but the id range is never smaller than the
    -- number of entries and only reads the ends of the index. Skip the count
    -- while the range is within the limit. MAX and MIN are separate queries
    -- because SQLite only reads them from the index when each is on its own.
    local id_range = count([[
SELECT COALESCE(
    (SELECT MAX(id) FROM request_history)
        - (SELECT MIN(id) FROM request_history) + 1,
    0
)]])
    if id_range <= max_items then
        return
    end

    local entries = count("SELECT COUNT(*) FROM request_history")
    if entries <= max_items then
        return
    end

    -- Delete down to a little below the limit, so the following saves skip
    -- the count until history fills up again.
    local headroom = math.min(PRUNE_BATCH, math.floor(max_items / 10))
    delete_entries(
        [[id IN (
    SELECT id FROM request_history ORDER BY time ASC, id ASC LIMIT ?
)]],
        { math.min(entries - max_items + headroom, PRUNE_BATCH) }
    )
end

function M.setup()
    local Db = require("nurl.data.db")

    local db_file = vim.fn.fnamemodify(config.history.db_file, ":p")
    fs.mkdir(vim.fs.dirname(db_file))
    M.db = Db:new(db_file)

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

---@param handle nurl.RequestHandle
function M.insert_history_entry(handle)
    if M.db == nil then
        M.setup()
    end

    local request = handle.request
    local response = handle.response
    local curl = handle.curl

    assert(response ~= nil, "Request must be completed")
    assert(curl ~= nil, "Request must be completed")

    local binds = {
        handle.exec_datetime,
        vim.json.encode(request.url),
        requests.build_url(request.url),
        request.query and vim.json.encode(request.query) or vim.NIL,
        request.title or vim.NIL,
        request.method,
        request.auth and vim.json.encode(request.auth) or vim.NIL,
        request.headers and vim.json.encode(request.headers) or vim.NIL,
        request.data and vim.json.encode(request.data) or vim.NIL,
        request.form and vim.json.encode(request.form) or vim.NIL,
        request.data_urlencode and vim.json.encode(request.data_urlencode)
            or vim.NIL,
        request.curl_args and vim.json.encode(request.curl_args) or vim.NIL,
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
        curl.result.stderr,
    }

    local result = M.db:exec(INSERT_ENTRY, binds)
    local code = result.code
    result:close()
    assert(code == SQLITE_DONE, "Failed to insert request history entry")

    -- The entry is saved at this point, so do not report a failure to delete
    -- old entries as a failure to save it.
    local ok, err = pcall(M.delete_old_items)
    if not ok then
        vim.notify(
            "Failed to delete old request history: " .. err,
            vim.log.levels.ERROR
        )
    end
end

local function ensure_db()
    if M.db == nil then
        M.setup()
    end
end

local function like_pattern(value)
    return "%"
        .. value:gsub("\\", "\\\\"):gsub("%%", "\\%%"):gsub("_", "\\_")
        .. "%"
end

local function page_query(filters, cursor, limit)
    filters = filters or {}
    limit = limit or 50

    assert(
        limit > 0 and limit % 1 == 0,
        "History page size must be a positive integer"
    )

    local where = {}
    local binds = {}

    local function condition(sql, ...)
        table.insert(where, sql)
        for _, value in ipairs({ ... }) do
            table.insert(binds, value)
        end
    end

    if filters.search and filters.search ~= "" then
        local pattern = like_pattern(filters.search)
        condition(
            "(request_url_raw LIKE ? ESCAPE '\\' OR request_title LIKE ? ESCAPE '\\')",
            pattern,
            pattern
        )
    end

    if filters.method and filters.method ~= "" then
        condition("request_method = ?", filters.method:upper())
    end

    if filters.status and filters.status ~= "" then
        local class = filters.status:match("^([1-5])[xX][xX]$")

        if class then
            condition(
                "response_status_code >= ? AND response_status_code < ?",
                tonumber(class) * 100,
                (tonumber(class) + 1) * 100
            )
        else
            local status = tonumber(filters.status)
            assert(
                status and status % 1 == 0,
                "Status must be a code or a class such as 4xx"
            )
            condition("response_status_code = ?", status)
        end
    end

    if filters.from and filters.from ~= "" then
        condition("time >= ?", filters.from)
    end

    if filters.to and filters.to ~= "" then
        -- Allow a date or a prefix of an ISO local datetime, inclusively.
        condition("time < ?", filters.to .. "~")
    end

    if filters.request_body and filters.request_body ~= "" then
        local pattern = like_pattern(filters.request_body)
        condition(
            "(request_data LIKE ? ESCAPE '\\' OR request_form LIKE ? ESCAPE '\\' OR request_data_urlencode LIKE ? ESCAPE '\\')",
            pattern,
            pattern,
            pattern
        )
    end

    if filters.response_body and filters.response_body ~= "" then
        condition(
            "response_body_file IS NULL AND response_body LIKE ? ESCAPE '\\'",
            like_pattern(filters.response_body)
        )
    end

    if filters.response_file == "yes" then
        condition("response_body_file IS NOT NULL")
    elseif filters.response_file == "no" then
        condition("response_body_file IS NULL")
    end

    if cursor then
        condition(
            "(time < ? OR (time = ? AND id < ?))",
            cursor.time,
            cursor.time,
            cursor.id
        )
    end

    local query = [[SELECT id, time, request_method, request_url_raw,
    request_title, response_status_code, response_time_total
FROM request_history]]
    if #where > 0 then
        query = query .. " WHERE " .. table.concat(where, " AND ")
    end

    query = query .. " ORDER BY time DESC, id DESC LIMIT ?"
    table.insert(binds, limit + 1)

    return query, binds
end

local function page_results(rows, limit)
    limit = limit or 50
    local summaries = {}

    for i = 1, math.min(#rows, limit) do
        local columns = rows[i]
        local function text(index)
            local value = columns[index]
            return value ~= vim.NIL and value or nil
        end
        table.insert(summaries, {
            id = tonumber(text(1)),
            time = text(2),
            method = text(3),
            url = text(4),
            title = text(5),
            status = tonumber(text(6)),
            duration = tonumber(text(7)),
        })
    end

    return summaries, #rows > limit
end

---Fetch summaries only. The cursor is a (time, id) pair, so entries with the
---same second are never skipped when loading another page.
---@param filters nurl.HistoryFilters
---@param cursor? nurl.HistorySummary
---@param limit? integer
---@return nurl.HistorySummary[], boolean
function M.page(filters, cursor, limit)
    ensure_db()

    local query, binds = page_query(filters, cursor, limit)
    local result = M.db:exec(query, binds)
    local rows = result:all()

    result:close()

    local columns = {}
    for _, row in ipairs(rows) do
        table.insert(columns, row.columns)
    end

    return page_results(columns, limit)
end

local function query_in_worker(path, root, sql, params)
    package.path = root .. "?.lua;" .. package.path

    local db
    local ok, data = pcall(function()
        db = require("nurl.data.db"):new(path)
        local result = db:exec(sql, vim.json.decode(params))
        local rows = result:all()

        result:close()

        local columns = {}
        for _, row in ipairs(rows) do
            table.insert(columns, row.columns)
        end

        return vim.json.encode(columns)
    end)

    if db then
        db:close()
    end

    return ok, data
end

---Run searches on a separate SQLite connection in libuv's worker pool.
---The worker only receives serialized values and never touches Neovim buffers.
---@param filters nurl.HistoryFilters
---@param cursor nurl.HistorySummary?
---@param limit integer
---@param callback fun(rows: nurl.HistorySummary[]?, more: boolean?, error: string?)
function M.page_async(filters, cursor, limit, callback)
    ensure_db()
    local query, binds = page_query(filters, cursor, limit)

    local work
    work = vim.uv.new_work(query_in_worker, function(ok, data)
        work = nil
        vim.schedule(function()
            if not ok then
                callback(nil, nil, data)
                return
            end

            local decoded, columns = pcall(vim.json.decode, data)
            if not decoded then
                callback(nil, nil, columns)
                return
            end

            local summaries, more = page_results(columns, limit)
            callback(summaries, more)
        end)
    end)

    work:queue(M.db.path, worker_root, query, vim.json.encode(binds))
end

---Delete entries by id, along with their saved response files.
---@param ids integer[]
function M.delete(ids)
    ensure_db()
    if #ids == 0 then
        return
    end
    local placeholders = ("?,"):rep(#ids):sub(1, -2)
    delete_entries(("id IN (%s)"):format(placeholders), ids)
end

---Load only the selected request for the explorer preview. In particular,
---this does not read the stored response body from SQLite.
---@param id integer
---@return nurl.Request?
function M.get_request(id)
    ensure_db()
    local result = M.db:exec(
        [[
SELECT request_url, request_query, request_method, request_headers,
    request_data, request_form, request_data_urlencode
FROM request_history WHERE id = ?]],
        { id }
    )
    local rows = result:all()
    result:close()

    local row = rows[1]
    if not row then
        return nil
    end

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

local SELECT_ITEM = [[SELECT
    time,
    request_url,
    request_query,
    request_title,
    request_method,
    request_auth,
    request_headers,
    request_data,
    request_form,
    request_data_urlencode,
    request_curl_args,
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
FROM request_history]]

---Response headers are saved as [name, value] pairs, or as a name to value
---table by older versions.
---@param json string
---@return table<string, string | string[]> headers
---@return [string, string][]? header_list
local function decode_headers(json)
    local value = vim.json.decode(json)
    if not vim.islist(value) then
        return value, nil
    end

    local headers = {}
    for _, header in ipairs(value) do
        headers = tables.collect_value(headers, header[1], header[2])
    end
    return headers, value
end

---@param row nurl.Row
---@return nurl.HistoryItem
local function decode_row(row)
    local time = row:get_string(1)
    local request_url = row:get_string(2)
    local request_query = row:get_string(3)
    local request_title = row:get_string(4)
    local request_method = row:get_string(5)
    local request_auth = row:get_string(6)
    local request_headers = row:get_string(7)
    local request_data = row:get_string(8)
    local request_form = row:get_string(9)
    local request_data_urlencode = row:get_string(10)
    local request_curl_args = row:get_string(11)
    local response_status_code = row:get_number(12)
    local response_reason_phrase = row:get_string(13)
    local response_protocol = row:get_string(14)
    local response_headers = row:get_string(15)
    local headers, header_list
    if response_headers then
        headers, header_list = decode_headers(response_headers)
    end
    local response_body = row:get_string(16)
    local response_body_file = row:get_string(17)
    local response_time_appconnect = row:get_number(18)
    local response_time_connect = row:get_number(19)
    local response_time_namelookup = row:get_number(20)
    local response_time_pretransfer = row:get_number(21)
    local response_time_redirect = row:get_number(22)
    local response_time_starttransfer = row:get_number(23)
    local response_time_total = row:get_number(24)
    local response_size_download = row:get_number(25)
    local response_size_header = row:get_number(26)
    local response_size_request = row:get_number(27)
    local response_size_upload = row:get_number(28)
    local response_speed_download = row:get_number(29)
    local response_speed_upload = row:get_number(30)
    local curl_args = row:get_string(31)
    local curl_result_code = row:get_number(32)
    local curl_result_signal = row:get_number(33)
    local curl_result_stdout = row:get_string(34)
    local curl_result_stderr = row:get_string(35)

    ---@type nurl.Request
    local request = {
        title = request_title,
        url = vim.json.decode(request_url),
        query = request_query and vim.json.decode(request_query),
        method = request_method,
        auth = request_auth and vim.json.decode(request_auth),
        headers = request_headers and vim.json.decode(request_headers),
        data = request_data and vim.json.decode(request_data),
        form = request_form and vim.json.decode(request_form),
        data_urlencode = request_data_urlencode
            and vim.json.decode(request_data_urlencode),
        curl_args = request_curl_args and vim.json.decode(request_curl_args),
    }

    ---@type nurl.Response
    local response = {
        status_code = response_status_code,
        reason_phrase = response_reason_phrase,
        protocol = response_protocol,
        headers = headers,
        header_list = header_list,
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
    })

    return { time, request, response, curl }
end

---@param id integer
---@return nurl.HistoryItem?
function M.get(id)
    ensure_db()
    local result = M.db:exec(SELECT_ITEM .. " WHERE id = ?", { id })
    local rows = result:all()
    result:close()
    if rows[1] then
        return decode_row(rows[1])
    end
end

return M

local Db = require("nurl.infra.db")
local body_store = require("nurl.infra.body_store")
local codec = require("nurl.history.codec")

---The history's SQL. Every function takes the database to use.
local M = {}

---@class nurl.HistoryFilters
---@field search? string
---@field method? string
---@field title? string the exact title
---@field url? string the exact URL, without the query field
---@field status? string
---@field from? string
---@field to? string
---@field request_body? string
---@field response_body? string
---@field response_file? "yes" | "no" whether the response body was saved to a file

local INSERT = ("INSERT INTO request_history (%s) VALUES (%s)"):format(
    table.concat(codec.INSERT_COLUMNS, ", "),
    ("?, "):rep(#codec.INSERT_COLUMNS):sub(1, -3)
)

---@param db nurl.Db
---@param handle nurl.RequestHandle a completed request
function M.insert(db, handle)
    local result = db:exec(INSERT, codec.encode(handle))
    local code = result.code
    result:close()
    assert(code == Db.DONE, "Failed to insert request history entry")
end

---Delete matching entries along with their saved response files.
---@param db nurl.Db
---@param where string
---@param binds any[]
local function delete_entries(db, where, binds)
    local result = db:exec(
        "DELETE FROM request_history WHERE "
            .. where
            .. " RETURNING response_body_file",
        binds
    )
    local rows = result:all()
    local code = result.code
    result:close()
    assert(code == Db.DONE, "Failed to delete request history")

    local failures = {}
    for _, row in ipairs(rows) do
        local body_file = row:get_string(1)
        local err = body_file and body_store.delete(body_file)
        if err then
            table.insert(failures, err)
        end
    end
    if #failures > 0 then
        error(table.concat(failures, "\n"))
    end
end

---Delete entries by id, along with their saved response files.
---@param db nurl.Db
---@param ids integer[]
function M.delete(db, ids)
    if #ids == 0 then
        return
    end
    local placeholders = ("?,"):rep(#ids):sub(1, -2)
    delete_entries(db, ("id IN (%s)"):format(placeholders), ids)
end

-- Most entries deleted when a request is saved, so one save never stalls.
local PRUNE_BATCH = 1000

---@param db nurl.Db
---@param query string
---@return integer
local function count(db, query)
    local result = db:exec(query)
    local value = result:one():get_number(1)
    result:close()
    return value
end

---Keep at most max_items entries, deleting the oldest in the same (time, id)
---order as the history explorer.
---@param db nurl.Db
---@param max_items integer
function M.prune(db, max_items)
    assert(
        type(max_items) == "number" and max_items >= 1 and max_items % 1 == 0,
        "history.max_history_items must be a positive integer"
    )

    -- Counting reads every entry, but the id range is never smaller than the
    -- number of entries and only reads the ends of the index. Skip the count
    -- while the range is within the limit. MAX and MIN are separate queries
    -- because SQLite only reads them from the index when each is on its own.
    local id_range = count(db, [[
SELECT COALESCE(
    (SELECT MAX(id) FROM request_history)
        - (SELECT MIN(id) FROM request_history) + 1,
    0
)]])
    if id_range <= max_items then
        return
    end

    local entries = count(db, "SELECT COUNT(*) FROM request_history")
    if entries <= max_items then
        return
    end

    -- Delete down to a little below the limit, so the following saves skip
    -- the count until history fills up again.
    local headroom = math.min(PRUNE_BATCH, math.floor(max_items / 10))
    delete_entries(
        db,
        [[id IN (
    SELECT id FROM request_history ORDER BY time ASC, id ASC LIMIT ?
)]],
        { math.min(entries - max_items + headroom, PRUNE_BATCH) }
    )
end

local function like_pattern(value)
    return "%"
        .. value:gsub("\\", "\\\\"):gsub("%%", "\\%%"):gsub("_", "\\_")
        .. "%"
end

---The query of a page of summaries. The cursor is a (time, id) pair, so
---entries with the same second are never skipped when loading another page.
---@param filters? nurl.HistoryFilters
---@param cursor? nurl.HistorySummary
---@param limit? integer
---@return string query, any[] binds
function M.page_query(filters, cursor, limit)
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

    if filters.title and filters.title ~= "" then
        condition("request_title = ?", filters.title)
    end

    if filters.url and filters.url ~= "" then
        condition("request_url_raw = ?", filters.url)
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

    local query = "SELECT "
        .. table.concat(codec.SUMMARY_COLUMNS, ", ")
        .. " FROM request_history"
    if #where > 0 then
        query = query .. " WHERE " .. table.concat(where, " AND ")
    end

    query = query .. " ORDER BY time DESC, id DESC LIMIT ?"
    table.insert(binds, limit + 1)

    return query, binds
end

---@param rows (string | userdata)[][] rows of SUMMARY_COLUMNS
---@param limit? integer
---@return nurl.HistorySummary[] summaries, boolean more whether more rows follow
function M.page_results(rows, limit)
    limit = limit or 50
    local summaries = {}

    for i = 1, math.min(#rows, limit) do
        table.insert(summaries, codec.summary(rows[i]))
    end

    return summaries, #rows > limit
end

---@param db nurl.Db
---@param filters? nurl.HistoryFilters
---@param cursor? nurl.HistorySummary
---@param limit? integer
---@return nurl.HistorySummary[], boolean
function M.page(db, filters, cursor, limit)
    local query, binds = M.page_query(filters, cursor, limit)
    local result = db:exec(query, binds)
    local rows = result:all()
    result:close()

    return M.page_results(
        vim.tbl_map(function(row)
            return row.columns
        end, rows),
        limit
    )
end

---@param db nurl.Db
---@param id integer
---@return nurl.HistoryItem?
function M.get(db, id)
    local result = db:exec(
        ("SELECT %s FROM request_history WHERE id = ?"):format(
            table.concat(codec.ITEM_COLUMNS, ", ")
        ),
        { id }
    )
    local rows = result:all()
    result:close()

    return rows[1] and codec.decode(rows[1])
end

---The request of an entry, without reading its response.
---@param db nurl.Db
---@param id integer
---@return nurl.Request?
function M.get_request(db, id)
    local result = db:exec(
        ("SELECT %s FROM request_history WHERE id = ?"):format(
            table.concat(codec.REQUEST_COLUMNS, ", ")
        ),
        { id }
    )
    local rows = result:all()
    result:close()

    return rows[1] and codec.request(rows[1])
end

return M

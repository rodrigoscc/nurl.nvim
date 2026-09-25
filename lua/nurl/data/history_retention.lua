local uv = vim.uv or vim.loop

local M = {}

-- Reclaim some headroom at once instead of vacuuming after every insertion
-- when history is near the limit.
local TARGET_RATIO = 0.8

local stored_text_columns = {
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
    "response_reason_phrase",
    "response_protocol",
    "response_headers",
    "response_body",
    "response_body_file",
    "curl_args",
    "curl_result_signal",
    "curl_result_stdout",
    "curl_result_stderr",
}

local function file_size(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.size or 0
end

local function query_rows(db, query, binds)
    local result = db:exec(query, binds)
    local rows = result:all()
    local code = result.code
    result:close()
    assert(code == 101, "Could not query request history: " .. db:errormsg())
    return rows
end

local function linked_files(db)
    local rows = query_rows(
        db,
        [[
SELECT response_body_file, MAX(response_body_file_size)
FROM request_history WHERE response_body_file IS NOT NULL
GROUP BY response_body_file]]
    )

    local sizes = {}
    local total = 0
    for _, row in ipairs(rows) do
        local path = row:get_string(1)
        local size = file_size(path)
        sizes[path] = size
        total = total + size
        if size ~= row:get_number(2) then
            local update = db:exec(
                [[
UPDATE request_history SET response_body_file_size = ?
WHERE response_body_file = ?]],
                { size, path }
            )
            local code = update.code
            update:close()
            assert(code == 101, "Could not update history response file size")
        end
    end
    return sizes, total
end

local function recorded_file_bytes(db)
    local result = db:exec([[
SELECT COALESCE(SUM(size), 0) FROM (
    SELECT MAX(response_body_file_size) AS size FROM request_history
    WHERE response_body_file IS NOT NULL GROUP BY response_body_file
)]])
    local row = result:one()
    result:close()
    return row:get_number(1)
end

local function validate_budget(max_bytes)
    assert(
        type(max_bytes) == "number" and max_bytes > 0 and max_bytes % 1 == 0,
        "history.max_size_bytes must be a positive integer"
    )
end

local function disk_size(db, external_bytes)
    return file_size(db.path)
        + file_size(db.path .. "-wal")
        + file_size(db.path .. "-shm")
        + external_bytes
end

local function checkpoint(db)
    local rows = query_rows(db, "PRAGMA wal_checkpoint(TRUNCATE)")
    return rows[1] and rows[1]:get_number(1) == 0
end

local function candidates(db)
    local byte_lengths = {}
    for _, column in ipairs(stored_text_columns) do
        table.insert(
            byte_lengths,
            ("COALESCE(LENGTH(CAST(%s AS BLOB)), 0)"):format(column)
        )
    end
    -- Account for numeric fields, the row header, and the time index.
    local query = ([[SELECT id, response_body_file, %s + 256
FROM request_history ORDER BY time ASC, id ASC]]):format(
        table.concat(byte_lengths, " + ")
    )
    return query_rows(db, query)
end

local function delete_body_file(path)
    local removed, err, name = uv.fs_unlink(path)
    if not removed and name ~= "ENOENT" then
        error(("Could not remove history response file %s: %s"):format(path, err))
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
            error(("Could not remove history response directory %s: %s"):format(dir, dir_err))
        end
    end
end

local function delete_oldest(db, count)
    local rows = query_rows(
        db,
        [[
DELETE FROM request_history WHERE id IN (
    SELECT id FROM request_history ORDER BY time ASC, id ASC LIMIT ?
) RETURNING response_body_file]],
        { count }
    )

    for _, row in ipairs(rows) do
        local path = row:get_string(1)
        if path then
            local still_used = #query_rows(
                db,
                [[
SELECT 1 FROM request_history WHERE response_body_file = ? LIMIT 1]],
                { path }
            ) > 0
            if not still_used then
                delete_body_file(path)
            end
        end
    end
end

---@param db nurl.Db
---@param max_bytes integer
---@return boolean
function M.over_budget(db, max_bytes)
    validate_budget(max_bytes)
    return disk_size(db, recorded_file_bytes(db)) > max_bytes
end

---@param db nurl.Db
---@param max_bytes integer
function M.enforce(db, max_bytes)
    validate_budget(max_bytes)
    local external_bytes = recorded_file_bytes(db)
    local size = disk_size(db, external_bytes)
    if size <= max_bytes then
        return
    end

    -- Files can have been removed or changed outside the database. Confirm
    -- their actual sizes before deleting any history.
    local file_sizes
    file_sizes, external_bytes = linked_files(db)
    size = disk_size(db, external_bytes)
    if size <= max_bytes then
        return
    end

    -- WAL can grow without increasing retained history. Only prune if a
    -- checkpoint confirms the database and its files still exceed the budget.
    if not checkpoint(db) then
        return
    end
    size = disk_size(db, external_bytes)
    if size <= max_bytes then
        return
    end

    local rows = candidates(db)
    local target = math.floor(max_bytes * TARGET_RATIO)
    local next_row = 1
    while size > target and next_row < #rows do
        local freed = 0
        local count = 0
        repeat
            local row = rows[next_row]
            freed = freed + (row:get_number(3) or 0)
            local path = row:get_string(2)
            if path then
                freed = freed + (file_sizes[path] or 0)
            end
            count = count + 1
            next_row = next_row + 1
        until freed >= size - target or next_row >= #rows

        delete_oldest(db, count)

        -- DELETE frees SQLite pages for reuse, not disk space. VACUUM shrinks
        -- the database; checkpointing then truncates the WAL as well.
        local vacuum = db:exec("VACUUM")
        local vacuum_code = vacuum.code
        vacuum:close()
        assert(vacuum_code == 101, "Could not compact history database")
        if not checkpoint(db) then
            return
        end
        file_sizes, external_bytes = linked_files(db)
        size = disk_size(db, external_bytes)
    end
end

local function enforce_in_worker(path, root, max_bytes)
    package.path = root .. "?.lua;" .. package.path
    local db
    local ok, err = pcall(function()
        db = require("nurl.data.db"):new(path)
        require("nurl.data.history_retention").enforce(db, max_bytes)
    end)
    if db then
        db:close()
    end
    return ok, ok and "" or tostring(err)
end

---@param path string
---@param max_bytes integer
---@param callback fun(error?: string)
function M.enforce_async(path, max_bytes, callback)
    local worker_root = require("nurl.data.worker_root")
    local work
    work = vim.uv.new_work(enforce_in_worker, function(ok, err)
        work = nil
        vim.schedule(function()
            if ok then
                callback()
            else
                callback(err)
            end
        end)
    end)
    work:queue(path, worker_root, max_bytes)
end

return M

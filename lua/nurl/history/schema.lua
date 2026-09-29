local Db = require("nurl.infra.db")

---The history tables, versioned with SQLite's user_version.
local M = {}

---Statements taking a database from one version to the next. Migration i
---leaves the database at version i. Add new ones at the end, and never change
---released ones: databases already at their version would not run them again.
---@type string[][]
M.migrations = {
    -- 1: the history table. Databases created before migrations were tracked
    -- already have it, hence IF NOT EXISTS.
    {
        [[CREATE TABLE IF NOT EXISTS request_history (
    id INTEGER PRIMARY KEY,
    time TEXT,
    request_url TEXT,
    request_url_raw TEXT,
    request_query TEXT,
    request_title TEXT,
    request_method TEXT,
    request_auth TEXT,
    request_headers TEXT,
    request_data TEXT,
    request_form TEXT,
    request_data_urlencode TEXT,
    request_curl_args TEXT,
    response_status_code INTEGER,
    response_reason_phrase TEXT,
    response_protocol TEXT,
    response_headers TEXT,
    response_body TEXT,
    response_body_file TEXT,
    response_time_appconnect REAL,
    response_time_connect REAL,
    response_time_namelookup REAL,
    response_time_pretransfer REAL,
    response_time_redirect REAL,
    response_time_starttransfer REAL,
    response_time_total REAL,
    response_size_download INTEGER,
    response_size_header INTEGER,
    response_size_request INTEGER,
    response_size_upload INTEGER,
    response_speed_download INTEGER,
    response_speed_upload INTEGER,
    curl_args TEXT,
    curl_result_code INTEGER,
    curl_result_signal TEXT,
    curl_result_stdout TEXT,
    curl_result_stderr TEXT
)]],
        [[CREATE INDEX IF NOT EXISTS idx_request_history_time ON request_history(time)]],
    },
}

---@param db nurl.Db
---@param sql string
local function run(db, sql)
    local result = db:exec(sql)
    local code = result.code
    result:close()

    if code ~= Db.DONE and code ~= Db.ROW then
        error(
            ("Failed to migrate the history database (%d): %s\n%s"):format(
                code,
                db:errormsg(),
                sql
            )
        )
    end
end

---@param db nurl.Db
---@return integer
function M.version(db)
    local result = db:exec("PRAGMA user_version")
    local version = result:one():get_number(1)
    result:close()
    return version --[[@as integer]]
end

---Bring the database to the latest version, each migration in a transaction.
---@param db nurl.Db
function M.migrate(db)
    local version = M.version(db)

    if version > #M.migrations then
        error(
            ("The history database is at version %d, newer than this version of nurl knows (%d)"):format(
                version,
                #M.migrations
            )
        )
    end

    for target = version + 1, #M.migrations do
        run(db, "BEGIN")

        local ok, err = pcall(function()
            for _, sql in ipairs(M.migrations[target]) do
                run(db, sql)
            end
            -- PRAGMA takes no bound parameters.
            run(db, ("PRAGMA user_version = %d"):format(target))
        end)

        if not ok then
            run(db, "ROLLBACK")
            error(err, 0)
        end

        run(db, "COMMIT")
    end
end

return M

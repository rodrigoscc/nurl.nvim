local ffi = require("ffi")

ffi.cdef([[
    typedef struct sqlite3 sqlite3;
    typedef struct sqlite3_stmt sqlite3_stmt;

    int sqlite3_open(const char *filename, sqlite3 **ppDb);
    int sqlite3_close(sqlite3*);
    int sqlite3_exec(
      sqlite3*, const char *sql, int (*callback)(void*,int,char**,char**), void*, char **errmsg);
    int sqlite3_prepare_v2(
      sqlite3*, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
    int sqlite3_reset(sqlite3_stmt*);
    int sqlite3_step(sqlite3_stmt*);
    int sqlite3_finalize(sqlite3_stmt*);
    int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int n, void(*)(void*));
    int sqlite3_bind_int64(sqlite3_stmt*, int, long long);
    int sqlite3_bind_double(sqlite3_stmt*, int, double);
    int sqlite3_bind_null(sqlite3_stmt*, int);
    const unsigned char *sqlite3_column_text(sqlite3_stmt*, int);
    int sqlite3_column_type(sqlite3_stmt*, int iCol);
    long long sqlite3_column_int64(sqlite3_stmt*, int);
    int sqlite3_column_count(sqlite3_stmt *pStmt);
    const char *sqlite3_errmsg(sqlite3*);
]])

local sqlite = ffi.load("sqlite3")

---@param stmt ffi.cdata*
---@param idx number
---@param value any
---@param value_type? type
local function bind(stmt, idx, value, value_type)
    value_type = value_type or type(value)
    if value_type == "string" then
        return sqlite.sqlite3_bind_text(stmt, idx, value, #value, nil)
    elseif value_type == "number" then
        return sqlite.sqlite3_bind_double(stmt, idx, value)
    elseif value_type == "boolean" then
        return sqlite.sqlite3_bind_int64(stmt, idx, value and 1 or 0)
    elseif value_type == "nil" or value == vim.NIL then
        return sqlite.sqlite3_bind_null(stmt, idx)
    else
        error(
            "Unsupported value type: "
                .. type(value)
                .. " ("
                .. tostring(value)
                .. ")"
        )
    end
end

---@class nurl.Db
---@field private path string
---@field private db sqlite3*
---@field private handle ffi.cdata*
local Db = {}

---@class nurl.Row
---@field columns string[]
local Row = {}

function Row:new(columns)
    local row = setmetatable({}, self)
    self.__index = self

    row.columns = columns

    return row
end

---@param idx integer
---@return string | nil
function Row:get_string(idx)
    local value = self.columns[idx]
    if value == vim.NIL then
        return nil
    end
    return value
end

---@param idx integer
---@return number | nil
function Row:get_number(idx)
    local value = self.columns[idx]
    if value == vim.NIL then
        return nil
    end
    return tonumber(value)
end

---@param idx integer
---@return boolean | nil
function Row:get_boolean(idx)
    local value = self.columns[idx]
    if value == vim.NIL then
        return nil
    end
    return value == "1"
end

---@class nurl.Result
---@field stmt sqlite3_stmt*
---@field code number | nil
local Result = {}

local SQLITE_ROW = 100
local SQLITE_DONE = 101
local SQLITE_NULL = 5

---@param stmt sqlite3_stmt*
---@return nurl.Result
function Result:new(stmt)
    local result = setmetatable({}, self)
    self.__index = self

    result.stmt = stmt
    result.code = sqlite.sqlite3_step(result.stmt)

    ffi.gc(stmt, function()
        result:close()
    end)

    return result
end

---@return nurl.Row
function Result:one()
    if self.code ~= SQLITE_ROW then
        error("Failed to get one row from result: " .. self.code)
    end

    local columns = {}
    local column_count = sqlite.sqlite3_column_count(self.stmt)

    for i = 0, column_count - 1 do
        local column_type = sqlite.sqlite3_column_type(self.stmt, i)
        if column_type == SQLITE_NULL then
            table.insert(columns, vim.NIL)
        else
            local text_ptr = sqlite.sqlite3_column_text(self.stmt, i)
            local value = text_ptr ~= nil and ffi.string(text_ptr) or vim.NIL
            table.insert(columns, value)
        end
    end

    local row = Row:new(columns)

    local code = sqlite.sqlite3_step(self.stmt)
    if code == SQLITE_ROW then
        error("Multiple results found")
    end

    return row
end

---@return nurl.Row[]
function Result:all()
    local column_count = sqlite.sqlite3_column_count(self.stmt)

    ---@type nurl.Row[]
    local rows = {}

    while self.code == SQLITE_ROW do
        local columns = {}

        for i = 0, column_count - 1 do
            local column_type = sqlite.sqlite3_column_type(self.stmt, i)
            if column_type == SQLITE_NULL then
                table.insert(columns, vim.NIL)
            else
                local text_ptr = sqlite.sqlite3_column_text(self.stmt, i)
                local value = text_ptr ~= nil and ffi.string(text_ptr)
                    or vim.NIL
                table.insert(columns, value)
            end
        end

        local row = Row:new(columns)

        table.insert(rows, row)

        self.code = sqlite.sqlite3_step(self.stmt)
    end

    return rows
end

function Result:close()
    if self.stmt then
        sqlite.sqlite3_finalize(self.stmt)
        self.stmt = nil
    end
end

---@alias sqlite3* ffi.cdata*
---@alias sqlite3_stmt* ffi.cdata*

function Db:new(path)
    local db = setmetatable({}, self)
    self.__index = self

    db.path = path

    db.handle = ffi.new("sqlite3*[1]")
    if sqlite.sqlite3_open(db.path, db.handle) ~= 0 then
        error("Failed to open database: " .. db.path)
    end

    db.db = db.handle[0]

    local result = db:exec("PRAGMA journal_mode=WAL")
    result:close()

    if result.code ~= SQLITE_ROW then
        error(
            ("Failed to enable wal journal mode %d: %s"):format(
                result.code,
                db:errormsg()
            )
        )
    end

    result = db:exec([[CREATE TABLE IF NOT EXISTS request_history (
    id INTEGER PRIMARY KEY,
    time TEXT,
    request_url TEXT,
    request_title TEXT,
    request_method TEXT,
    request_headers TEXT,
    request_data TEXT,
    request_form TEXT,
    request_data_urlencode TEXT,
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
);]])
    local create_code = result.code
    result:close()

    if create_code ~= SQLITE_DONE then
        error(
            ("Failed to create request_history table %d: %s"):format(
                create_code,
                db:errormsg()
            )
        )
    end

    result = db:exec(
        [[CREATE INDEX IF NOT EXISTS idx_request_history_time ON request_history(time);]]
    )
    local index_code = result.code
    result:close()

    if index_code ~= SQLITE_DONE then
        error(
            ("Failed to create index on time column %d: %s"):format(
                index_code,
                db:errormsg()
            )
        )
    end

    ffi.gc(db.handle, function()
        db:close()
    end)

    return db
end

---@param query string
---@param binds? any[]
function Db:exec(query, binds)
    binds = binds or {}

    local stmt = ffi.new("sqlite3_stmt*[1]")

    local code = sqlite.sqlite3_prepare_v2(self.db, query, #query, stmt, nil) --[[@as number]]
    if code ~= 0 then
        error(
            ("Failed to prepare statement %d: %s"):format(code, self:errormsg())
        )
    end

    for i, value in ipairs(binds) do
        if bind(stmt[0], i, value) ~= 0 then
            error(("Failed to bind %d=%s"):format(i, value))
        end
    end

    return Result:new(stmt[0])
end

function Db:errormsg()
    return ffi.string(sqlite.sqlite3_errmsg(self.db))
end

function Db:close()
    if self.db then
        sqlite.sqlite3_close(self.db)
        self.db = nil
        self.handle = nil
    end
end

return Db

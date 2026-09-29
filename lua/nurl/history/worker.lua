local repository = require("nurl.history.repository")

---Runs history searches on a separate SQLite connection in libuv's worker
---pool, so that slow searches do not block Neovim.
local M = {}

-- Lua modules can be loaded through package.path without being on runtimepath
-- (as in the test runner). Find the root from this loaded module instead.
local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and vim.uv.fs_realpath(source:sub(2))
assert(file, "Could not locate nurl Lua modules for background workers")

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(file))) .. "/"

---Runs in the worker thread, which only receives serialized values and never
---touches Neovim buffers.
local function query_in_worker(path, lua_root, sql, params)
    package.path = lua_root .. "?.lua;" .. package.path

    local db
    local ok, data = pcall(function()
        db = require("nurl.infra.db"):new(path)
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

---@param db_path string the database to search, opened by the worker
---@param filters nurl.HistoryFilters
---@param cursor nurl.HistorySummary?
---@param limit integer
---@param callback fun(rows: nurl.HistorySummary[]?, more: boolean?, error: string?)
function M.page(db_path, filters, cursor, limit, callback)
    local query, binds = repository.page_query(filters, cursor, limit)

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

            local summaries, more = repository.page_results(columns, limit)
            callback(summaries, more)
        end)
    end)

    work:queue(db_path, root, query, vim.json.encode(binds))
end

return M

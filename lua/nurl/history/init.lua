local config = require("nurl.config")
local fs = require("nurl.infra.fs")
local repository = require("nurl.history.repository")

---The requests sent, saved with their responses in a SQLite database.
local M = {}

---The open database, opened on first use.
---@type nurl.Db | nil
M.db = nil

---Open a history database, creating or migrating its tables.
---@param path string
---@return nurl.Db
function M.open(path)
    local db = require("nurl.infra.db"):new(path)

    local ok, err = pcall(require("nurl.history.schema").migrate, db)
    if not ok then
        db:close()
        error(err, 0)
    end

    return db
end

---Open the configured database, closing it when Neovim exits.
function M.setup()
    local db_file = vim.fn.fnamemodify(config.history.db_file, ":p")
    fs.mkdir(vim.fs.dirname(db_file))
    M.db = M.open(db_file)

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

---@return nurl.Db
local function db()
    if M.db == nil then
        M.setup()
    end
    return M.db --[[@as nurl.Db]]
end

---Save a completed request, then delete the oldest entries beyond
---history.max_history_items.
---@param handle nurl.RequestHandle
function M.insert_history_entry(handle)
    repository.insert(db(), handle)

    -- The entry is saved at this point, so do not report a failure to delete
    -- old entries as a failure to save it.
    local ok, err =
        pcall(repository.prune, db(), config.history.max_history_items)
    if not ok then
        vim.notify(
            "Failed to delete old request history: " .. err,
            vim.log.levels.ERROR
        )
    end
end

---A page of summaries, newest first.
---@param filters nurl.HistoryFilters
---@param cursor? nurl.HistorySummary the last entry of the previous page
---@param limit? integer
---@return nurl.HistorySummary[], boolean more
function M.page(filters, cursor, limit)
    return repository.page(db(), filters, cursor, limit)
end

---A page of summaries, searched in the background.
---@param filters nurl.HistoryFilters
---@param cursor nurl.HistorySummary?
---@param limit integer
---@param callback fun(rows: nurl.HistorySummary[]?, more: boolean?, error: string?)
function M.page_async(filters, cursor, limit, callback)
    require("nurl.history.worker").page(
        db().path,
        filters,
        cursor,
        limit,
        callback
    )
end

---Delete entries by id, along with their saved response files.
---@param ids integer[]
function M.delete(ids)
    repository.delete(db(), ids)
end

---The request of an entry, without reading its response.
---@param id integer
---@return nurl.Request?
function M.get_request(id)
    return repository.get_request(db(), id)
end

---@param id integer
---@return nurl.HistoryItem?
function M.get(id)
    return repository.get(db(), id)
end

return M

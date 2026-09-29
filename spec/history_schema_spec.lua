local Db = require("nurl.infra.db")
local history = require("nurl.history")
local schema = require("nurl.history.schema")

describe("history schema", function()
    local path, db

    ---@param sql string
    ---@return nurl.Row[]
    local function query(sql)
        local result = db:exec(sql)
        local rows = result:all()
        result:close()
        return rows
    end

    before_each(function()
        path = vim.fn.tempname() .. ".sqlite3"
    end)

    after_each(function()
        if db then
            db:close()
            db = nil
        end
        for _, suffix in ipairs({ "", "-wal", "-shm" }) do
            vim.fn.delete(path .. suffix)
        end
    end)

    it("creates the tables of a new database", function()
        db = history.open(path)

        assert.are.equal(#schema.migrations, schema.version(db))
        assert.are.equal(
            1,
            #query(
                "SELECT name FROM sqlite_master WHERE name = 'request_history'"
            )
        )
    end)

    it("keeps the entries of a database from before migrations", function()
        -- Older versions created the table without setting user_version.
        db = Db:new(path)
        for _, sql in ipairs(schema.migrations[1]) do
            db:exec(sql):close()
        end
        db:exec(
            "INSERT INTO request_history (time, request_method) VALUES ('2026-09-26T10:00:00', 'GET')"
        ):close()
        assert.are.equal(0, schema.version(db))
        db:close()

        db = history.open(path)

        assert.are.equal(#schema.migrations, schema.version(db))
        local rows = query("SELECT time, request_method FROM request_history")
        assert.are.equal(1, #rows)
        assert.are.equal("GET", rows[1]:get_string(2))
    end)

    it("does nothing when already up to date", function()
        db = history.open(path)
        db:exec(
            "INSERT INTO request_history (time) VALUES ('2026-09-26T10:00:00')"
        ):close()

        schema.migrate(db)

        assert.are.equal(#schema.migrations, schema.version(db))
        assert.are.equal(1, #query("SELECT id FROM request_history"))
    end)

    it("refuses a database from a newer version", function()
        db = Db:new(path)
        db:exec(("PRAGMA user_version = %d"):format(#schema.migrations + 1))
            :close()
        db:close()
        db = nil

        assert.has_error(function()
            history.open(path)
        end, ("The history database is at version %d, newer than this version of nurl knows (%d)"):format(
            #schema.migrations + 1,
            #schema.migrations
        ))
    end)

    it("rolls back a migration that fails", function()
        db = history.open(path)
        local version = schema.version(db)

        table.insert(schema.migrations, {
            "CREATE TABLE half_done (x)",
            "NOT SQL",
        })
        local ok, err = pcall(schema.migrate, db)
        table.remove(schema.migrations)

        assert.is_false(ok)
        assert.matches("Failed to prepare statement", err)
        assert.are.equal(version, schema.version(db))
        assert.are.equal(
            0,
            #query("SELECT name FROM sqlite_master WHERE name = 'half_done'")
        )
    end)
end)

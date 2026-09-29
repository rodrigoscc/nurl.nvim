local Db = require("nurl.infra.db")

describe("db", function()
    local path, db

    before_each(function()
        path = vim.fn.tempname() .. ".sqlite3"
        db = Db:new(path)
        local create =
            db:exec("CREATE TABLE items (time TEXT, title TEXT, method TEXT)")
        create:close()
    end)

    after_each(function()
        db:close()
        for _, suffix in ipairs({ "", "-wal", "-shm" }) do
            vim.fn.delete(path .. suffix)
        end
    end)

    it("binds the values after a nil", function()
        local insert = db:exec(
            "INSERT INTO items (time, title, method) VALUES (?, ?, ?)",
            { "2026-09-26T10:00:00", nil, "GET" }
        )
        insert:close()

        local result = db:exec(
            "SELECT time, title, method FROM items"
        )
        local row = result:one()
        result:close()
        assert.are.equal("2026-09-26T10:00:00", row:get_string(1))
        assert.is_nil(row:get_string(2))
        assert.are.equal("GET", row:get_string(3))
    end)

    it("rejects more values than the statement has parameters", function()
        local ok, err = pcall(db.exec, db, "SELECT ?", { 1, 2 })
        assert.is_false(ok)
        assert.matches("2 values for 1 parameters", err)
    end)
end)

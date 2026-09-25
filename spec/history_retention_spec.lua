local Db = require("nurl.data.db")
local config = require("nurl.config")
local fs = require("nurl.data.fs")
local history = require("nurl.data.history")
local retention = require("nurl.data.history_retention")

describe("history disk retention", function()
    local dir, path, db

    before_each(function()
        dir = vim.fn.tempname()
        fs.mkdir(dir)
        path = vim.fs.joinpath(dir, "history.sqlite3")
        db = Db:new(path)
    end)

    after_each(function()
        history.db = nil
        config.setup()
        db:close()
        vim.fs.rm(dir, { recursive = true, force = true })
    end)

    local function disk_size(files)
        local total = 0
        for _, file in ipairs({ path, path .. "-wal", path .. "-shm" }) do
            local stat = vim.uv.fs_stat(file)
            total = total + (stat and stat.size or 0)
        end
        for _, file in ipairs(files or {}) do
            local stat = vim.uv.fs_stat(file)
            total = total + (stat and stat.size or 0)
        end
        return total
    end

    local function insert(index, body, file)
        local result = db:exec([[
INSERT INTO request_history (
    time, request_url_raw, response_body, response_body_file,
    response_body_file_size
) VALUES (?, ?, ?, ?, ?)]], {
            ("2026-09-24T12:00:%02d"):format(index),
            "https://example.org/" .. index,
            body,
            file or vim.NIL,
            file and vim.uv.fs_stat(file).size or 0,
        })
        result:close()
    end

    local function urls()
        local result = db:exec([[
SELECT request_url_raw FROM request_history ORDER BY time, id]])
        local rows = result:all()
        result:close()
        local values = {}
        for _, row in ipairs(rows) do
            table.insert(values, row:get_string(1))
        end
        return values
    end

    it("compacts SQLite after dropping the oldest large responses", function()
        for i = 1, 12 do
            insert(i, string.rep("x", 16000))
        end

        retention.enforce(db, 100000)

        local kept = urls()
        assert.is_true(#kept > 0 and #kept < 12)
        assert.are.equal("https://example.org/12", kept[#kept])
        assert.is_true(disk_size() <= 100000)
    end)

    it("keeps all entries while their storage is under budget", function()
        for i = 1, 50 do
            insert(i, "small response")
        end

        retention.enforce(db, 1024 * 1024)

        assert.are.equal(50, #urls())
    end)

    it("counts and deletes file-backed responses with their history", function()
        local files = {}
        for i = 1, 4 do
            local file = fs.unique_path(dir, "response", "bin")
            fs.write(file, string.rep("x", 30000))
            table.insert(files, file)
            insert(i, "", file)
        end

        retention.enforce(db, 90000)

        local kept = urls()
        assert.are.same({ "https://example.org/4" }, kept)
        for i = 1, 3 do
            assert.is_false(fs.exists(files[i]))
            assert.is_false(fs.exists(vim.fs.dirname(files[i])))
        end
        assert.is_true(fs.exists(files[4]))
        assert.is_true(disk_size(files) <= 90000)
    end)

    it("counts a shared response file only once", function()
        local file = fs.unique_path(dir, "response", "bin")
        fs.write(file, string.rep("x", 30000))
        insert(1, "", file)
        insert(2, "", file)

        local budget = disk_size({ file }) + 1000
        assert.is_false(retention.over_budget(db, budget))
        retention.enforce(db, budget)
        assert.are.equal(2, #urls())
        assert.is_true(fs.exists(file))
    end)

    it("updates recorded sizes for files removed outside history", function()
        local file = fs.unique_path(dir, "response", "bin")
        fs.write(file, string.rep("x", 30000))
        insert(1, "", file)
        fs.delete_dir(vim.fs.dirname(file))

        assert.is_true(retention.over_budget(db, 60000))
        retention.enforce(db, 60000)
        assert.is_false(retention.over_budget(db, 60000))
        assert.are.equal(1, #urls())
    end)

    it("keeps the newest entry even when it alone exceeds the budget", function()
        insert(1, string.rep("x", 20000))
        insert(2, string.rep("x", 100000))

        retention.enforce(db, 60000)

        assert.are.same({ "https://example.org/2" }, urls())
    end)

    it("backfills file sizes in an existing history database", function()
        local file = fs.unique_path(dir, "response", "bin")
        fs.write(file, string.rep("x", 1234))
        local drop = db:exec("DROP TABLE request_history")
        drop:close()
        local create = db:exec([[
CREATE TABLE request_history (
    id INTEGER PRIMARY KEY, time TEXT, response_body_file TEXT
)]])
        create:close()
        local old_entry = db:exec([[
INSERT INTO request_history (time, response_body_file) VALUES (?, ?)]], {
            "2026-09-24T12:00:00",
            file,
        })
        old_entry:close()
        db:close()

        db = Db:new(path)
        local result = db:exec([[
SELECT response_body_file_size FROM request_history]])
        local row = result:all()[1]
        result:close()
        assert.are.equal(1234, row:get_number(1))
    end)

    it("applies the budget after recording a completed request", function()
        config.setup({ history = { max_size_bytes = 70000 } })
        history.db = db
        local files = {}
        for i = 1, 2 do
            local file = fs.unique_path(dir, "response", "bin")
            fs.write(file, string.rep("x", 30000))
            table.insert(files, file)
            history.insert_history_entry({
                exec_datetime = ("2026-09-24T12:00:%02d"):format(i),
                request = {
                    url = "https://example.org/" .. i,
                    method = "GET",
                    headers = {},
                },
                response = {
                    status_code = 200,
                    reason_phrase = "OK",
                    protocol = "HTTP/1.1",
                    headers = {},
                    body = "",
                    body_file = file,
                    time = {
                        time_appconnect = 0,
                        time_connect = 0,
                        time_namelookup = 0,
                        time_pretransfer = 0,
                        time_redirect = 0,
                        time_starttransfer = 0,
                        time_total = 0,
                    },
                    size = {
                        size_download = 30000,
                        size_header = 0,
                        size_request = 0,
                        size_upload = 0,
                    },
                    speed = { speed_download = 0, speed_upload = 0 },
                },
                curl = {
                    args = {},
                    result = { code = 0, signal = 0, stdout = "", stderr = "" },
                },
            })
        end

        assert.is_true(vim.wait(5000, function()
            return not history.retention_running and not fs.exists(files[1])
        end))
        assert.are.same({ "https://example.org/2" }, urls())
        assert.is_false(fs.exists(files[1]))
        assert.is_true(fs.exists(files[2]))
        local result = db:exec([[
SELECT response_body_file_size FROM request_history]])
        local row = result:all()[1]
        result:close()
        assert.are.equal(30000, row:get_number(1))
    end)
end)

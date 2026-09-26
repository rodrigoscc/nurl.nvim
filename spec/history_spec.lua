local Db = require("nurl.data.db")
local config = require("nurl.config")
local fs = require("nurl.data.fs")
local history = require("nurl.data.history")

describe("history explorer queries", function()
    local path

    before_each(function()
        path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(path)
    end)

    after_each(function()
        config.setup()
        history.db:close()
        history.db = nil
        vim.fn.delete(path)
        vim.fn.delete(path .. "-wal")
        vim.fn.delete(path .. "-shm")
    end)

    local function insert(time, url, method, status, data, response, body_file)
        local result = history.db:exec([[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    request_data, response_status_code, response_reason_phrase,
    response_protocol, response_headers, response_body, response_body_file,
    response_time_total, curl_args
) VALUES (?, ?, ?, ?, '{}', ?, ?, 'OK', 'HTTP/1.1', '{}', ?, ?, 0.12, '[]')]], {
            time,
            vim.json.encode(url),
            url,
            method,
            data and vim.json.encode(data) or vim.NIL,
            status,
            response,
            body_file or vim.NIL,
        })
        result:close()
    end

    it("pages deterministically when timestamps are equal and loads details by id", function()
        insert(
            "2026-09-24T12:00:00",
            "https://example.org/a",
            "GET",
            200,
            nil,
            "one"
        )
        insert(
            "2026-09-24T12:00:00",
            "https://example.org/b",
            "POST",
            201,
            { id = 2 },
            "two"
        )
        insert(
            "2026-09-23T12:00:00",
            "https://example.org/c",
            "GET",
            404,
            nil,
            "three"
        )

        local first, more = history.page({}, nil, 1)
        assert.is_true(more)
        assert.are.equal("https://example.org/b", first[1].url)
        local item = history.get(first[1].id)
        assert.are.equal("POST", item[2].method)
        assert.are.equal("two", item[3].body)

        local second = history.page({}, first[1], 1)
        local third, last = history.page({}, second[1], 1)
        assert.are.equal("https://example.org/a", second[1].url)
        assert.are.equal(404, third[1].status)
        assert.is_false(last)
    end)

    it("combines literal body, status, and date filters and skips file-backed responses", function()
        insert(
            "2026-09-24T12:00:00",
            "https://example.org/a",
            "POST",
            400,
            { name = "50%_done" },
            "Error 50%_done"
        )
        insert(
            "2026-09-24T13:00:00",
            "https://example.org/b",
            "POST",
            400,
            { name = "50%_done" },
            "Error 50%_done",
            "/tmp/body.bin"
        )
        insert(
            "2026-09-23T12:00:00",
            "https://example.org/c",
            "POST",
            200,
            { name = "50%_done" },
            "Error 50%_done"
        )

        local rows, more = history.page({
            method = "post",
            status = "4xx",
            from = "2026-09-24",
            to = "2026-09-24",
            request_body = "50%_done",
            response_body = "error 50%_done",
        }, nil, 50)
        assert.are.equal(1, #rows)
        assert.are.equal("https://example.org/a", rows[1].url)
        assert.is_false(more)
        assert.are.equal(0, #history.page({ response_body = "50XXdone" }))
    end)

    it("returns the same body-filter page from the background worker", function()
        for i, suffix in ipairs({ "a", "b", "c" }) do
            insert(
                "2026-09-24T12:00:00",
                "https://example.org/" .. suffix,
                "POST",
                200,
                { id = i },
                i == 3 and "other" or "needle"
            )
        end

        local filters = { request_body = "id", response_body = "needle" }
        local expected, expected_more = history.page(filters, nil, 1)
        local actual, more, failure
        history.page_async(filters, nil, 1, function(rows, has_more, err)
            actual, more, failure = rows, has_more, err
        end)
        assert.is_true(vim.wait(5000, function()
            return actual ~= nil or failure ~= nil
        end))
        assert.is_nil(failure)
        assert.are.same(expected, actual)
        assert.are.equal(expected_more, more)

        local next_page
        history.page_async(filters, actual[1], 1, function(rows, has_more, err)
            next_page = { rows = rows, more = has_more, error = err }
        end)
        assert.is_true(vim.wait(5000, function()
            return next_page ~= nil
        end))
        assert.is_nil(next_page.error)
        assert.are.same(history.page(filters, actual[1], 1), next_page.rows)
        assert.is_false(next_page.more)
    end)

    it("searches form and urlencoded request bodies too", function()
        for _, column in ipairs({ "request_form", "request_data_urlencode" }) do
            local query = string.format(
                [[INSERT INTO request_history (
    time, request_url_raw, request_method, response_status_code, %s
) VALUES ('2026-09-24T12:00:00', 'https://example.org', 'POST', 200, ?)]],
                column
            )
            local result = history.db:exec(query, {
                vim.json.encode({ token = "unique-" .. column }),
            })
            result:close()
        end
        assert.are.equal(
            1,
            #history.page({ request_body = "unique-request_form" })
        )
        assert.are.equal(
            1,
            #history.page({ request_body = "unique-request_data_urlencode" })
        )
    end)

    it("filters by whether the response body was saved to a file", function()
        insert("2026-09-24T12:00:01", "https://example.org/inline", "GET", 200, nil, "text")
        insert("2026-09-24T12:00:02", "https://example.org/file", "GET", 200, nil, "", "/tmp/response.png")

        local function urls(filters)
            return vim.tbl_map(function(row)
                return row.url
            end, (history.page(filters)))
        end

        assert.are.same({ "https://example.org/file" }, urls({ response_file = "yes" }))
        assert.are.same({ "https://example.org/inline" }, urls({ response_file = "no" }))
        assert.are.same(
            { "https://example.org/file", "https://example.org/inline" },
            urls({})
        )
    end)

    local function completed_request(index, body_file, time)
        return {
            exec_datetime = time or ("2026-09-24T12:00:%02d"):format(index),
            request = {
                url = "https://example.org/" .. index,
                method = "GET",
                headers = {},
            },
            response = {
                status_code = 200,
                reason_phrase = "OK",
                protocol = "HTTP/1.1",
                headers = {},
                body = "",
                body_file = body_file,
                time = {
                    time_appconnect = 0,
                    time_connect = 0,
                    time_namelookup = 0,
                    time_pretransfer = 0,
                    time_redirect = 0,
                    time_starttransfer = 0,
                    time_total = 0.1,
                },
                size = {
                    size_download = 0,
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
        }
    end

    local function saved_urls()
        local result = history.db:exec(
            "SELECT request_url_raw FROM request_history ORDER BY time, id"
        )
        local rows = result:all()
        result:close()
        return vim.tbl_map(function(row)
            return row:get_string(1)
        end, rows)
    end

    it("keeps only the newest max_history_items entries", function()
        config.setup({ history = { max_history_items = 3 } })

        for i = 1, 5 do
            history.insert_history_entry(completed_request(i))
        end

        assert.are.same({
            "https://example.org/3",
            "https://example.org/4",
            "https://example.org/5",
        }, saved_urls())
    end)

    it("does not count history while it is under max_history_items", function()
        config.setup({ history = { max_history_items = 3 } })
        local queries = {}
        local exec = history.db.exec
        history.db.exec = function(db, query, ...)
            table.insert(queries, query)
            return exec(db, query, ...)
        end

        local ok, err = pcall(function()
            for i = 1, 3 do
                history.insert_history_entry(completed_request(i))
            end
        end)
        history.db.exec = nil
        assert(ok, err)

        for _, query in ipairs(queries) do
            assert.is_nil(query:find("COUNT(*)", 1, true))
        end
        assert.are.equal(3, #saved_urls())
    end)

    local function insert_rows(count)
        local begin = history.db:exec("BEGIN")
        begin:close()
        for i = 1, count do
            local result = history.db:exec(
                "INSERT INTO request_history (time, request_url_raw) VALUES (?, ?)",
                { ("2026-01-01T00:00:00.%05d"):format(i), "old" }
            )
            result:close()
        end
        local commit = history.db:exec("COMMIT")
        commit:close()
    end

    it("deletes a batch below max_history_items to skip later counts", function()
        config.setup({ history = { max_history_items = 20 } })
        insert_rows(20)
        local counts = 0
        local exec = history.db.exec
        history.db.exec = function(db, query, ...)
            if query:find("COUNT(*)", 1, true) then
                counts = counts + 1
            end
            return exec(db, query, ...)
        end

        local ok, err = pcall(function()
            -- Over the limit: delete down to 10% below it.
            history.insert_history_entry(completed_request(1))
            assert.are.equal(18, #saved_urls())
            -- Back under the limit, so these saves do not count history.
            history.insert_history_entry(completed_request(2))
            history.insert_history_entry(completed_request(3))
            assert.are.equal(20, #saved_urls())
        end)
        history.db.exec = nil
        assert(ok, err)
        assert.are.equal(1, counts)
    end)

    it("deletes at most 1000 entries per saved request", function()
        config.setup({ history = { max_history_items = 10 } })
        insert_rows(1010)

        history.insert_history_entry(completed_request(1))
        assert.are.equal(11, #saved_urls())

        history.insert_history_entry(completed_request(2))
        assert.are.equal(9, #saved_urls())
        assert.are.same(
            { "https://example.org/1", "https://example.org/2" },
            vim.list_slice(saved_urls(), 8)
        )
    end)

    it("deletes the oldest entries by request time", function()
        config.setup({ history = { max_history_items = 3 } })

        -- A slow request that started first is saved last.
        history.insert_history_entry(completed_request(2))
        history.insert_history_entry(completed_request(3))
        history.insert_history_entry(
            completed_request(1, nil, "2026-09-24T12:00:01")
        )
        history.insert_history_entry(completed_request(4))

        assert.are.same({
            "https://example.org/2",
            "https://example.org/3",
            "https://example.org/4",
        }, saved_urls())
    end)

    it("keeps max_history_items entries when ids have gaps", function()
        config.setup({ history = { max_history_items = 3 } })
        for i = 1, 3 do
            history.insert_history_entry(completed_request(i))
        end
        local result =
            history.db:exec("DELETE FROM request_history WHERE id = 2")
        result:close()

        history.insert_history_entry(completed_request(4))

        assert.are.same({
            "https://example.org/1",
            "https://example.org/3",
            "https://example.org/4",
        }, saved_urls())
    end)

    it("keeps history and reports an invalid max_history_items", function()
        config.setup({ history = { max_history_items = false } })
        local notify = vim.notify
        local messages = {}
        vim.notify = function(message)
            table.insert(messages, message)
        end

        local ok, err = pcall(function()
            for i = 1, 2 do
                history.insert_history_entry(completed_request(i))
            end
        end)
        vim.notify = notify

        assert(ok, err)
        assert.are.equal(2, #saved_urls())
        assert.are.equal(2, #messages)
        assert.matches("max_history_items must be a positive integer", messages[1])
    end)

    it("deletes the response files of deleted entries", function()
        config.setup({ history = { max_history_items = 1 } })
        local dir = vim.fn.tempname()
        local files = {}
        for i = 1, 2 do
            files[i] = fs.unique_path(dir, "response", "bin")
            fs.write(files[i], "body " .. i)
            history.insert_history_entry(completed_request(i, files[i]))
        end

        assert.are.same({ "https://example.org/2" }, saved_urls())
        assert.is_false(fs.exists(files[1]))
        assert.is_false(fs.exists(vim.fs.dirname(files[1])))
        assert.is_true(fs.exists(files[2]))
        vim.fs.rm(dir, { recursive = true, force = true })
    end)

    it("deletes entries by id with their response files", function()
        local dir = vim.fn.tempname()
        local file = fs.unique_path(dir, "response", "bin")
        fs.write(file, "body")
        for i = 1, 3 do
            history.insert_history_entry(
                completed_request(i, i == 2 and file or nil)
            )
        end
        local ids = vim.tbl_map(function(row)
            return row.id
        end, (history.page({})))

        history.delete({ ids[2], ids[3] }) -- entries 2 and 1

        assert.are.same({ "https://example.org/3" }, saved_urls())
        assert.is_false(fs.exists(file))
        vim.fs.rm(dir, { recursive = true, force = true })
    end)

    it("does not sync to disk on every commit", function()
        local result = history.db:exec("PRAGMA synchronous")
        local row = result:one()
        result:close()
        assert.are.equal(1, row:get_number(1)) -- NORMAL
    end)

    it("keeps the order of response headers", function()
        local request = completed_request(1)
        request.response.headers = { b = "2", a = { "1", "3" } }
        request.response.header_list = { { "b", "2" }, { "a", "1" }, { "a", "3" } }
        history.insert_history_entry(request)

        local id = history.page({})[1].id
        local response = history.get(id)[3]
        assert.are.same(
            { "b: 2", "a: 1", "a: 3" },
            require("nurl.responses").header_lines(response)
        )
        assert.are.same({ "1", "3" }, response.headers.a)
    end)

    it("loads response headers saved without their order", function()
        insert(
            "2026-09-24T12:00:00",
            "https://example.org",
            "GET",
            200,
            nil,
            "body"
        )
        local result = history.db:exec(
            [[UPDATE request_history SET response_headers = '{"b":"2","a":"1"}']]
        )
        result:close()

        local response = history.get(history.page({})[1].id)[3]
        assert.are.same({ a = "1", b = "2" }, response.headers)
        assert.are.same(
            { "a: 1", "b: 2" },
            require("nurl.responses").header_lines(response)
        )
    end)

    it("closes the connection when opening history fails", function()
        if not vim.uv.fs_stat("/proc/self/fd") then
            return
        end
        local bad = vim.fn.tempname()
        fs.write(bad, string.rep("not a database\n", 1000))
        local function open_files()
            return #vim.fn.readdir("/proc/self/fd")
        end

        local before = open_files()
        for _ = 1, 10 do
            assert.is_false(pcall(Db.new, Db, bad))
        end
        collectgarbage()
        collectgarbage()
        assert.are.equal(before, open_files())
        vim.fn.delete(bad)
    end)
end)

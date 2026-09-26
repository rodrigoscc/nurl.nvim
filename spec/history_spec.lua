local Db = require("nurl.data.db")
local fs = require("nurl.data.fs")
local history = require("nurl.data.history")

describe("history explorer queries", function()
    local path

    before_each(function()
        path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(path)
    end)

    after_each(function()
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

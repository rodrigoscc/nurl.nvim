local config = require("nurl.config")
local Db = require("nurl.data.db")
local history = require("nurl.data.history")
local explorer = require("nurl.ui.history_explorer")

describe("history explorer searches", function()
    local original_page, original_page_async
    local original_input, original_select
    local test_path

    before_each(function()
        config.setup()
        test_path = nil
        original_page = history.page
        original_page_async = history.page_async
        original_input = vim.ui.input
        original_select = vim.ui.select
    end)

    after_each(function()
        if #vim.api.nvim_list_tabpages() > 1 then
            vim.cmd.tabclose()
        end
        history.page = original_page
        history.page_async = original_page_async
        vim.ui.input = original_input
        vim.ui.select = original_select
        if test_path then
            history.db:close()
            history.db = nil
            vim.fn.delete(test_path)
            vim.fn.delete(test_path .. "-wal")
            vim.fn.delete(test_path .. "-shm")
        end
    end)

    it("ignores results from a previous body filter", function()
        local callbacks = {}
        history.page = function()
            return {}, false
        end
        history.page_async = function(_, _, _, callback)
            table.insert(callbacks, callback)
        end

        explorer.open()
        local list = vim.api.nvim_get_current_buf()
        local input = "old"
        vim.ui.select = function(fields, _, callback)
            callback(fields[7]) -- response body
        end
        vim.ui.input = function(_, callback)
            callback(input)
        end

        local function filter()
            for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
                if mapping.lhs == "F" then
                    mapping.callback()
                    return
                end
            end
            error("Missing history filter keymap")
        end

        filter()
        input = "new"
        filter()
        assert.are.equal(2, #callbacks)

        local function summary(url)
            return {
                id = 1,
                time = "2026-09-24T12:00:00",
                method = "GET",
                status = 200,
                duration = 0.1,
                url = url,
            }
        end
        callbacks[1]({ summary("https://example.org/old") }, false)
        assert.are.equal(
            "Loading history…",
            vim.api.nvim_buf_get_lines(list, 0, 1, false)[1]
        )

        callbacks[2]({ summary("https://example.org/new") }, false)
        assert.is_true(
            vim.api.nvim_buf_get_lines(list, 0, 1, false)[1]:find(
                "/new",
                1,
                true
            ) ~= nil
        )
    end)

    it("runs searches that scan every entry in the background", function()
        local sync_filters = {}
        local async_filters = {}
        history.page = function(filters)
            table.insert(sync_filters, vim.deepcopy(filters))
            return {}, false
        end
        history.page_async = function(filters, _, _, callback)
            table.insert(async_filters, vim.deepcopy(filters))
            callback({}, false)
        end

        explorer.open()
        local list = vim.api.nvim_get_current_buf()
        local field_index, input
        vim.ui.select = function(fields, _, callback)
            callback(fields[field_index])
        end
        vim.ui.input = function(_, callback)
            callback(input)
        end
        local function filter(index, value)
            field_index, input = index, value
            for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
                if mapping.lhs == "F" then
                    mapping.callback()
                end
            end
        end

        filter(4, "2026-09-01") -- from: uses the time index
        filter(1, "example") -- URL / title
        filter(2, "POST") -- method
        filter(3, "5xx") -- status

        assert.are.same({ {}, { from = "2026-09-01" } }, sync_filters)
        assert.are.same({
            { from = "2026-09-01", search = "example" },
            { from = "2026-09-01", search = "example", method = "POST" },
            {
                from = "2026-09-01",
                search = "example",
                method = "POST",
                status = "5xx",
            },
        }, async_filters)
    end)

    it("routes :Nurl history and the old API to the explorer", function()
        history.page = function()
            return {}, false
        end

        require("nurl.commands").setup()
        vim.cmd("Nurl history")
        assert.are.equal(2, #vim.api.nvim_list_tabpages())
        assert.is_true(
            vim.api.nvim_buf_get_name(0):find("nurl://history/list", 1, true)
                ~= nil
        )
        vim.cmd.tabclose()

        require("nurl").pick_history()
        assert.are.equal(2, #vim.api.nvim_list_tabpages())
        assert.is_true(
            vim.api.nvim_buf_get_name(0):find("nurl://history/list", 1, true)
                ~= nil
        )
    end)

    it("previews the selected request body without loading response bodies into the list", function()
        test_path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(test_path)
        for i = 1, 2 do
            local result = history.db:exec([[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    request_data, response_status_code, response_body, response_time_total
) VALUES (?, ?, ?, 'POST', '{}', ?, 200, ?, 0.1)]], {
                ("2026-09-24T12:00:%02d"):format(i),
                vim.json.encode("https://example.org/" .. i),
                "https://example.org/" .. i,
                vim.json.encode(
                    "request-"
                        .. i
                        .. "\n"
                        .. string.rep("body line\n", 200)
                        .. "end-of-request-"
                        .. i
                ),
                string.rep("response-" .. i, 10000),
            })
            result:close()
        end

        explorer.open()
        local list_win = vim.api.nvim_get_current_win()
        local list_buf = vim.api.nvim_get_current_buf()
        local preview_buf
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local bufnr = vim.api.nvim_win_get_buf(win)
            if bufnr ~= list_buf then
                preview_buf = bufnr
            end
        end
        assert.is_true(preview_buf ~= nil)
        local function preview_lines()
            return table.concat(
                vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false),
                "\n"
            )
        end

        assert.is_true(vim.wait(3000, function()
            return preview_lines():find("request-2", 1, true) ~= nil
        end))
        assert.is_true(
            preview_lines():find("end-of-request-2", 1, true) ~= nil
        )
        assert.is_nil(preview_lines():find("response-2", 1, true))
        assert.is_nil(table.concat(
            vim.api.nvim_buf_get_lines(list_buf, 0, -1, false),
            "\n"
        ):find("request-", 1, true))

        vim.api.nvim_win_set_cursor(list_win, { 2, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = list_buf })
        assert.is_true(vim.wait(3000, function()
            return preview_lines():find("request-1", 1, true) ~= nil
        end))
        assert.is_nil(preview_lines():find("response-1", 1, true))
    end)

    it("fills the visible list when the window opens or grows", function()
        config.setup({ history = { explorer = { page_size = 2 } } })
        test_path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(test_path)
        for i = 1, 100 do
            local url = "https://example.org/" .. i
            local result = history.db:exec([[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method,
    response_status_code, response_time_total
) VALUES ('2026-09-24T12:00:00', ?, ?, 'GET', 200, 0.1)]], {
                vim.json.encode(url),
                url,
            })
            result:close()
        end

        explorer.open()
        local list_win = vim.api.nvim_get_current_win()
        local list_buf = vim.api.nvim_get_current_buf()
        local preview_win
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if win ~= list_win then
                preview_win = win
            end
        end
        local function loaded()
            return #vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)
        end

        assert.is_true(loaded() >= vim.api.nvim_win_get_height(list_win))
        assert.is_true(loaded() > 2)

        local original_count = loaded()
        vim.api.nvim_win_set_height(preview_win, 1)
        vim.api.nvim_exec_autocmds("WinResized", {})
        assert.is_true(vim.api.nvim_win_get_height(list_win) > original_count)
        assert.is_true(loaded() >= vim.api.nvim_win_get_height(list_win))
        assert.is_true(loaded() > original_count)
    end)

    it("does not leave empty buffers behind", function()
        history.page = function()
            return {}, false
        end
        local function buffers()
            return #vim.api.nvim_list_bufs()
        end

        local before = buffers()
        for _ = 1, 3 do
            explorer.open()
            vim.cmd.tabclose()
        end
        assert.are.equal(before, buffers())
    end)

    it("closes when it is the last tab page", function()
        history.page = function()
            return {}, false
        end

        explorer.open()
        local list_buf = vim.api.nvim_get_current_buf()
        vim.cmd.tabonly()

        local q
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list_buf, "n")) do
            if mapping.lhs == "q" then
                q = mapping.callback
            end
        end
        local ok, err = pcall(q)
        assert(ok, err)

        assert.is_false(vim.api.nvim_buf_is_valid(list_buf))
        assert.are.equal(1, #vim.api.nvim_list_tabpages())
        assert.are.equal(1, #vim.api.nvim_list_wins())
        assert.is_nil(
            vim.api.nvim_buf_get_name(0):find("nurl://history", 1, true)
        )
    end)

    it("keeps the list and selection when opening and closing a response", function()
        test_path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(test_path)
        config.setup({ buffers = { { "body", keys = { q = "close" } } } })

        local result = history.db:exec([[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    request_data, response_status_code, response_reason_phrase, response_protocol,
    response_headers, response_body, response_time_total, curl_args
) VALUES ('2026-09-24T12:00:00', ?, ?, 'POST', '{}', ?,
    200, 'OK', 'HTTP/1.1', '{}', 'saved response', 0.1, '[]')]], {
            vim.json.encode("https://example.org"),
            "https://example.org",
            vim.json.encode("request payload"),
        })
        result:close()

        explorer.open()
        local list_win = vim.api.nvim_get_current_win()
        local list_buf = vim.api.nvim_get_current_buf()
        local tab = vim.api.nvim_get_current_tabpage()
        assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(tab))
        local preview_buf
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            local bufnr = vim.api.nvim_win_get_buf(win)
            if
                vim.api.nvim_buf_get_name(bufnr):find(
                    "history/request",
                    1,
                    true
                )
            then
                preview_buf = bufnr
            end
        end
        assert.is_true(vim.wait(3000, function()
            return preview_buf
                and table.concat(
                    vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false),
                    "\n"
                ):find("request payload", 1, true) ~= nil
        end))
        assert.is_nil(table.concat(
            vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false),
            "\n"
        ):find("saved response", 1, true))

        vim.ui.input = function(_, callback)
            callback("example.org")
        end
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list_buf, "n")) do
            if mapping.lhs == "/" then
                mapping.callback()
                break
            end
        end
        assert.is_true(
            vim.wo[list_win].winbar:find("example.org", 1, true) ~= nil
        )
        assert.is_true(vim.wait(3000, function()
            return vim.api.nvim_buf_get_lines(list_buf, 0, 1, false)[1]:find(
                "example.org",
                1,
                true
            ) ~= nil
        end))

        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list_buf, "n")) do
            if mapping.lhs == "<CR>" then
                mapping.callback()
                break
            end
        end
        assert.are.equal(tab, vim.api.nvim_get_current_tabpage())
        assert.are.equal(3, #vim.api.nvim_tabpage_list_wins(tab))
        assert.are.equal("body", vim.b.nurl_data.buffer_type)

        local response_buf = vim.api.nvim_get_current_buf()
        vim.cmd.close()
        assert.are.equal(list_win, vim.api.nvim_get_current_win())
        assert.are.equal(list_buf, vim.api.nvim_get_current_buf())
        assert.are.equal(1, vim.api.nvim_win_get_cursor(list_win)[1])
        assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(tab))
        assert.is_true(
            vim.wo[list_win].winbar:find("example.org", 1, true) ~= nil
        )
        vim.api.nvim_buf_delete(response_buf, { force = true })
    end)
end)

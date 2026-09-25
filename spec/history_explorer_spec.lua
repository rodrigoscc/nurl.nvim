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

    it("keeps the list and selection when opening and closing a response", function()
        test_path = vim.fn.tempname() .. ".sqlite3"
        history.db = Db:new(test_path)
        config.setup({ buffers = { { "body", keys = { q = "close" } } } })

        local result = history.db:exec([[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    response_status_code, response_reason_phrase, response_protocol,
    response_headers, response_body, response_time_total, curl_args
) VALUES ('2026-09-24T12:00:00', ?, ?, 'GET', '{}',
    200, 'OK', 'HTTP/1.1', '{}', 'saved response', 0.1, '[]')]], {
            vim.json.encode("https://example.org"),
            "https://example.org",
        })
        result:close()

        explorer.open()
        local list_win = vim.api.nvim_get_current_win()
        local list_buf = vim.api.nvim_get_current_buf()
        local tab = vim.api.nvim_get_current_tabpage()
        assert.are.equal(1, #vim.api.nvim_tabpage_list_wins(tab))

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

        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list_buf, "n")) do
            if mapping.lhs == "<CR>" then
                mapping.callback()
                break
            end
        end
        assert.are.equal(tab, vim.api.nvim_get_current_tabpage())
        assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(tab))
        assert.are.equal("body", vim.b.nurl_data.buffer_type)

        local response_buf = vim.api.nvim_get_current_buf()
        vim.cmd.close()
        assert.are.equal(list_win, vim.api.nvim_get_current_win())
        assert.are.equal(list_buf, vim.api.nvim_get_current_buf())
        assert.are.equal(1, vim.api.nvim_win_get_cursor(list_win)[1])
        assert.is_true(
            vim.wo[list_win].winbar:find("example.org", 1, true) ~= nil
        )
        vim.api.nvim_buf_delete(response_buf, { force = true })
    end)
end)

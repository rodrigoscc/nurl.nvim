local config = require("nurl.config")
local history = require("nurl.history")
local explorer = require("nurl.ui.history_explorer")

---The text of a winbar, whatever the width of its window.
local function plain(winbar)
    local text = winbar
        :gsub("%%#[^#]*#", "")
        :gsub("%%%*", "")
        :gsub("%%[=<]", "")
        :gsub("%%%%", "%%")
    return text
end

---The filter field with a key, among those the filter picker offers.
local function field(fields, key)
    for _, candidate in ipairs(fields) do
        if candidate.key == key then
            return candidate
        end
    end
    error("Missing filter field " .. key)
end

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

        explorer.open(require("nurl.app.client"))
        local list = vim.api.nvim_get_current_buf()
        local input = "old"
        vim.ui.select = function(fields, _, callback)
            callback(field(fields, "response_body"))
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
            vim.api
                .nvim_buf_get_lines(list, 0, 1, false)[1]
                :find("/new", 1, true) ~= nil
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

        explorer.open(require("nurl.app.client"))
        local list = vim.api.nvim_get_current_buf()
        local field_key, input
        vim.ui.select = function(fields, _, callback)
            callback(field(fields, field_key))
        end
        vim.ui.input = function(_, callback)
            callback(input)
        end
        local function filter(key, value)
            field_key, input = key, value
            for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
                if mapping.lhs == "F" then
                    mapping.callback()
                end
            end
        end

        filter("from", "2026-09-01") -- uses the time index
        filter("search", "example")
        filter("method", "POST")
        filter("status", "5xx")

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

    it("filters responses whose body was saved to a file", function()
        local async_filters = {}
        history.page = function()
            return {}, false
        end
        history.page_async = function(filters, _, _, callback)
            table.insert(async_filters, vim.deepcopy(filters))
            callback({}, false)
        end

        explorer.open(require("nurl.app.client"))
        local list = vim.api.nvim_get_current_buf()
        local choice
        vim.ui.select = function(items, _, callback)
            if type(items[1]) == "table" then
                callback(field(items, "response_file"))
            else
                assert.are.same({ "yes", "no", "any" }, items)
                callback(choice)
            end
        end
        local function filter(value)
            choice = value
            for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
                if mapping.lhs == "F" then
                    mapping.callback()
                end
            end
        end

        filter("yes")
        assert.are.same({ { response_file = "yes" } }, async_filters)
        assert.is_true(vim.wo.winbar:find("response_file=yes", 1, true) ~= nil)

        filter("any")
        assert.are.equal(1, #async_filters)
        assert.is_nil(vim.wo.winbar:find("response_file", 1, true))
    end)

    it("deletes entries from the cursor down after confirmation", function()
        local rows = {}
        for i = 1, 4 do
            table.insert(rows, {
                id = i,
                time = ("2026-09-24T12:00:0%d"):format(5 - i),
                method = "GET",
                status = 200,
                duration = 0.1,
                url = "https://example.org/" .. i,
            })
        end
        history.page = function()
            return vim.deepcopy(rows), false
        end
        local deleted = {}
        local original_delete = history.delete
        history.delete = function(ids)
            vim.list_extend(deleted, ids)
        end
        local answer = 2
        local original_confirm = vim.fn.confirm
        vim.fn.confirm = function()
            return answer
        end

        local ok, err = pcall(function()
            explorer.open(require("nurl.app.client"))
            local list = vim.api.nvim_get_current_buf()
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            vim.api.nvim_feedkeys("2dd", "x", false)
            assert.are.same({}, deleted)

            answer = 1
            vim.api.nvim_feedkeys("2dd", "x", false)
            assert.are.same({ 2, 3 }, deleted)

            local lines = vim.api.nvim_buf_get_lines(list, 0, -1, false)
            assert.are.equal(2, #lines)
            assert.is_truthy(lines[1]:find("example.org/1", 1, true))
            assert.is_truthy(lines[2]:find("example.org/4", 1, true))
            assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
        end)
        history.delete = original_delete
        vim.fn.confirm = original_confirm
        assert(ok, err)
    end)

    it(
        "shows status icons, readable durations and URLs without scheme",
        function()
            history.page = function()
                return {
                    {
                        id = 2,
                        time = "2026-09-24T12:00:01",
                        method = "POST",
                        status = 404,
                        duration = 1.4,
                        title = "Create order",
                        url = "https://example.org/orders",
                    },
                    {
                        id = 1,
                        time = "2026-09-24T12:00:00",
                        method = "GET",
                        status = 200,
                        duration = 0.045,
                        url = "http://example.org/users",
                    },
                },
                    false
            end

            explorer.open(require("nurl.app.client"))
            local list = vim.api.nvim_get_current_buf()
            local lines = vim.api.nvim_buf_get_lines(list, 0, -1, false)

            assert.is_truthy(
                lines[1]:find(
                    "󰅚 404    1.40s  Create order  example.org/orders",
                    1,
                    true
                )
            )
            assert.is_truthy(
                lines[2]:find("󰄬 200     45ms  example.org/users", 1, true)
            )
            assert.is_nil(lines[1]:find("://", 1, true))

            local function group_at(row, text)
                local col = lines[row + 1]:find(text, 1, true) - 1
                local marks = vim.api.nvim_buf_get_extmarks(
                    list,
                    -1,
                    { row, col },
                    { row, col },
                    { details = true, overlap = true }
                )
                return marks[#marks][4].hl_group
            end
            assert.are.equal("NurlHistoryDurationSlow", group_at(0, "1.40s"))
            assert.are.equal("NurlHistoryUrlDim", group_at(0, "example.org"))
            assert.are.equal("NurlHistoryDuration", group_at(1, "45ms"))
            assert.are.equal("NurlHistoryUrl", group_at(1, "example.org"))
        end
    )

    it("starts with the filters it is given", function()
        local filters = { method = "GET", title = "Get user" }
        local searched
        history.page_async = function(page_filters, _, _, callback)
            searched = vim.deepcopy(page_filters)
            callback({}, false)
        end

        explorer.open(require("nurl.app.client"), filters)
        local win = vim.api.nvim_get_current_win()

        assert.are.same(filters, searched)
        assert.is_truthy(
            plain(vim.wo[win].winbar):find(
                " method=GET    title=Get user   0 matches",
                1,
                true
            )
        )

        -- Clearing the filters leaves the given table alone.
        history.page = function()
            return {}, false
        end
        vim.api.nvim_feedkeys("C", "x", false)
        assert.are.same({ method = "GET", title = "Get user" }, filters)
    end)

    it("shows the entry count, filters, search state and keys in the winbar", function()
        local callbacks = {}
        history.page = function()
            return {
                {
                    id = 1,
                    time = "2026-09-24T12:00:00",
                    method = "GET",
                    status = 200,
                    duration = 0.1,
                    url = "https://example.org/a",
                },
                {
                    id = 2,
                    time = "2026-09-24T11:00:00",
                    method = "GET",
                    status = 200,
                    duration = 0.1,
                    url = "https://example.org/b",
                },
            },
                false
        end
        history.page_async = function(_, _, _, callback)
            table.insert(callbacks, callback)
        end
        vim.ui.input = function(_, callback)
            callback("100%")
        end

        explorer.open(require("nurl.app.client"))
        local win = vim.api.nvim_get_current_win()
        local list = vim.api.nvim_get_current_buf()
        local function winbar()
            return vim.api.nvim_eval_statusline(
                vim.wo[win].winbar,
                { winid = win, use_winbar = true }
            )
        end

        local text = winbar().str
        assert.is_truthy(
            text:find("<CR> open  / search  F filter  ? help  󰋚 History", 1, true)
        )
        assert.is_nil(text:find("entries", 1, true))
        assert.is_nil(text:find("match", 1, true))
        assert.is_nil(text:find("searching", 1, true))

        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
            if mapping.lhs == "/" then
                mapping.callback()
            end
        end
        local raw = vim.wo[win].winbar
        assert.is_truthy(winbar().str:find("⠋ searching  <CR>", 1, true))
        assert.is_truthy(raw:find("%#NurlHistoryFilter# search=", 1, true))

        -- Spinner ticks redraw the frame without setting the winbar again.
        local sets = 0
        local autocmd = vim.api.nvim_create_autocmd("OptionSet", {
            pattern = "winbar",
            callback = function()
                sets = sets + 1
            end,
        })
        local ticked = vim.wait(1000, function()
            return winbar().str:find("⠋ searching", 1, true) == nil
        end)
        vim.api.nvim_del_autocmd(autocmd)
        assert.is_true(ticked)
        assert.are.equal(0, sets)
        assert.are.equal(raw, vim.wo[win].winbar)

        callbacks[1]({
            {
                id = 1,
                time = "2026-09-24T12:00:00",
                method = "GET",
                status = 200,
                duration = 0.1,
                url = "https://example.org/100%",
            },
        }, false)
        text = plain(vim.wo[win].winbar)
        assert.is_truthy(text:find(" search=100%   1 match  <CR>", 1, true))
        assert.is_nil(text:find("searching", 1, true))
    end)

    it("shows failed searches and stops searching when filters change", function()
        local callbacks = {}
        history.page = function()
            return {}, false
        end
        history.page_async = function(_, _, _, callback)
            table.insert(callbacks, callback)
        end
        local search = string.rep("ã", 45)
        vim.ui.input = function(_, callback)
            callback(search)
        end
        local original_notify = vim.notify
        vim.notify = function() end

        local ok, err = pcall(function()
            explorer.open(require("nurl.app.client"))
            local win = vim.api.nvim_get_current_win()
            local list = vim.api.nvim_get_current_buf()
            local function press(lhs)
                for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
                    if mapping.lhs == lhs then
                        mapping.callback()
                    end
                end
            end
            local function winbar()
                return plain(vim.wo[win].winbar)
            end

            -- Long filters are cut by characters, not bytes.
            press("/")
            assert.is_truthy(winbar():find(
                " search=" .. string.rep("ã", 40) .. "… ",
                1,
                true
            ))

            press("C")
            assert.is_nil(winbar():find("searching", 1, true))
            assert.is_nil(winbar():find("match", 1, true))

            press("/")
            callbacks[2](nil, nil, "worker failed")
            local text = winbar()
            assert.is_truthy(text:find("…   󰅚 failed to load", 1, true))
            assert.is_nil(text:find("match", 1, true))
            assert.is_nil(text:find("searching", 1, true))

            -- A page that fails after others leaves older entries unlisted.
            press("/")
            callbacks[3]({
                {
                    id = 1,
                    time = "2026-09-24T12:00:00",
                    method = "GET",
                    status = 200,
                    duration = 0.1,
                    url = "https://example.org",
                },
            }, true)
            callbacks[4](nil, nil, "worker failed")
            assert.is_truthy(
                winbar():find("…   1+ match  󰅚 failed to load", 1, true)
            )
        end)
        vim.notify = original_notify
        assert(ok, err)
    end)

    it("shows when the previewed request was sent in its winbar", function()
        history.page = function()
            return {
                {
                    id = 2,
                    time = "2026-10-04T01:15:32",
                    method = "GET",
                    status = 200,
                    duration = 0.1,
                    url = "https://example.org/2",
                },
                {
                    id = 1,
                    time = "2026-09-29T22:56:07",
                    method = "GET",
                    status = 200,
                    duration = 0.1,
                    url = "https://example.org/1",
                },
            },
                false
        end
        local original_get_request = history.get_request
        history.get_request = function()
            return nil
        end

        local ok, err = pcall(function()
            explorer.open(require("nurl.app.client"))
            local preview_win = vim.fn.win_getid(vim.fn.winnr("j"))
            local function winbar()
                return vim.api.nvim_eval_statusline(
                    vim.wo[preview_win].winbar,
                    { winid = preview_win, use_winbar = true }
                ).str
            end

            assert.is_truthy(winbar():find("󰈈 Preview", 1, true))
            assert.is_true(vim.wait(1000, function()
                return winbar():find("^Sunday, Oct 4, 2026  01:15:32") ~= nil
            end))

            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
            assert.is_true(vim.wait(1000, function()
                return winbar():find("^Tuesday, Sep 29, 2026  22:56:07")
                    ~= nil
            end))
            assert.is_truthy(winbar():find("󰈈 Preview", 1, true))
        end)
        history.get_request = original_get_request
        assert(ok, err)
    end)

    it("shows a header above the first entry of each day", function()
        local rows = {}
        for i, time in ipairs({
            "2025-12-31T23:00:00",
            "2025-12-31T09:00:00",
            "2025-12-30T22:00:00",
            "2025-12-29T08:00:00",
        }) do
            table.insert(rows, {
                id = 5 - i,
                time = time,
                method = "GET",
                status = 200,
                duration = 0.1,
                url = "https://example.org/" .. i,
            })
        end
        history.page = function()
            return vim.deepcopy(rows), false
        end

        explorer.open(require("nurl.app.client"))
        local win = vim.api.nvim_get_current_win()
        local list = vim.api.nvim_get_current_buf()

        assert.is_truthy(
            vim.api.nvim_buf_get_lines(list, 0, 1, false)[1]:find("^23:00  GET")
        )

        local headers = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(list, -1, 0, -1, {
                details = true,
            }))
        do
            if mark[4].virt_lines then
                assert.is_true(mark[4].virt_lines_above)
                table.insert(headers, { mark[2], mark[4].virt_lines[1][1][1] })
            end
        end
        assert.are.same({ { 2, "Dec 30, 2025" }, { 3, "Dec 29, 2025" } }, headers)

        -- The winbar names the day of the top row.
        local function day()
            return vim.api
                .nvim_eval_statusline(
                    vim.wo[win].winbar,
                    { winid = win, use_winbar = true }
                ).str
                :match("^(.-)%s%s")
        end
        assert.are.equal("Dec 31, 2025", day())

        vim.fn.winrestview({ topline = 3, lnum = 3 })
        vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(win) })
        assert.are.equal("Dec 30, 2025", day())
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

    it(
        "previews the selected request body without loading response bodies into the list",
        function()
            test_path = vim.fn.tempname() .. ".sqlite3"
            history.db = history.open(test_path)
            for i = 1, 2 do
                local result = history.db:exec(
                    [[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    request_data, response_status_code, response_body, response_time_total
) VALUES (?, ?, ?, 'POST', '{}', ?, 200, ?, 0.1)]],
                    {
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
                    }
                )
                result:close()
            end

            explorer.open(require("nurl.app.client"))
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
            assert.is_nil(
                table
                    .concat(vim.api.nvim_buf_get_lines(list_buf, 0, -1, false), "\n")
                    :find("request-", 1, true)
            )

            vim.api.nvim_win_set_cursor(list_win, { 2, 0 })
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = list_buf })
            assert.is_true(vim.wait(3000, function()
                return preview_lines():find("request-1", 1, true) ~= nil
            end))
            assert.is_nil(preview_lines():find("response-1", 1, true))
        end
    )

    it("fills the visible list when the window opens or grows", function()
        config.setup({ history = { explorer = { page_size = 2 } } })
        test_path = vim.fn.tempname() .. ".sqlite3"
        history.db = history.open(test_path)
        for i = 1, 100 do
            local url = "https://example.org/" .. i
            local result = history.db:exec(
                [[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method,
    response_status_code, response_time_total
) VALUES ('2026-09-24T12:00:00', ?, ?, 'GET', 200, 0.1)]],
                {
                    vim.json.encode(url),
                    url,
                }
            )
            result:close()
        end

        explorer.open(require("nurl.app.client"))
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
            explorer.open(require("nurl.app.client"))
            vim.cmd.tabclose()
        end
        assert.are.equal(before, buffers())
    end)

    it("closes when it is the last tab page", function()
        history.page = function()
            return {}, false
        end

        explorer.open(require("nurl.app.client"))
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

    it("lets FileType autocmds of the user change the list", function()
        history.page = function()
            return {}, false
        end
        local group = vim.api.nvim_create_augroup("nurl_test_filetype", {})
        vim.api.nvim_create_autocmd("FileType", {
            group = group,
            pattern = "nurl-history",
            callback = function(args)
                vim.wo.number = true
                vim.keymap.set("n", "q", "<Nop>", {
                    buffer = args.buf,
                    desc = "user close",
                })
            end,
        })

        local ok, err = pcall(function()
            explorer.open(require("nurl.app.client"))
            assert.is_true(vim.wo.number)
            local q = vim.fn.maparg("q", "n", false, true)
            assert.are.equal("user close", q.desc)
        end)
        vim.api.nvim_del_augroup_by_id(group)
        assert(ok, err)
    end)

    it("leaves the winbar of other buffers opened in the preview", function()
        history.page = function()
            return {}, false
        end

        explorer.open(require("nurl.app.client"))
        local list = vim.api.nvim_get_current_buf()
        local preview_win = vim.fn.win_getid(vim.fn.winnr("j"))
        assert.is_truthy(vim.wo[preview_win].winbar:find("Preview", 1, true))

        vim.api.nvim_win_call(preview_win, function()
            vim.cmd.enew()
        end)
        assert.are.equal("", vim.wo[preview_win].winbar)

        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list, "n")) do
            if mapping.lhs == "C" then
                mapping.callback()
            end
        end
        assert.are.equal("", vim.wo[preview_win].winbar)
    end)

    it("hides the user's window decorations without changing them", function()
        history.page = function()
            return {}, false
        end
        vim.o.number = true
        vim.o.signcolumn = "yes"
        vim.o.cursorline = true

        explorer.open(require("nurl.app.client"))
        local list_win = vim.api.nvim_get_current_win()
        local list_buf = vim.api.nvim_get_current_buf()
        local preview_win = vim.fn.win_getid(vim.fn.winnr("j"))

        assert.are.equal("nurl-history", vim.bo[list_buf].filetype)
        assert.are.equal(
            "http",
            vim.bo[vim.api.nvim_win_get_buf(preview_win)].filetype
        )

        for _, win in ipairs({ list_win, preview_win }) do
            assert.is_false(vim.wo[win].number)
            assert.are.equal("no", vim.wo[win].signcolumn)
        end
        assert.is_true(vim.wo[list_win].cursorline)
        assert.is_false(vim.wo[preview_win].cursorline)

        -- Closing the last tab page leaves the user's options in the window.
        vim.cmd.tabonly()
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list_buf, "n")) do
            if mapping.lhs == "q" then
                mapping.callback()
            end
        end
        assert.is_true(vim.wo.number)
        assert.are.equal("yes", vim.wo.signcolumn)

        vim.o.number = false
        vim.o.signcolumn = "auto"
        vim.o.cursorline = false
    end)

    it(
        "keeps the list and selection when opening and closing a response",
        function()
            test_path = vim.fn.tempname() .. ".sqlite3"
            history.db = history.open(test_path)
            config.setup({ buffers = { { "body", keys = { q = "close" } } } })

            local result = history.db:exec(
                [[
INSERT INTO request_history (
    time, request_url, request_url_raw, request_method, request_headers,
    request_data, response_status_code, response_reason_phrase, response_protocol,
    response_headers, response_body, response_time_total, curl_args
) VALUES ('2026-09-24T12:00:00', ?, ?, 'POST', '{}', ?,
    200, 'OK', 'HTTP/1.1', '{}', 'saved response', 0.1, '[]')]],
                {
                    vim.json.encode("https://example.org"),
                    "https://example.org",
                    vim.json.encode("request payload"),
                }
            )
            result:close()

            explorer.open(require("nurl.app.client"))
            local list_win = vim.api.nvim_get_current_win()
            local list_buf = vim.api.nvim_get_current_buf()
            local tab = vim.api.nvim_get_current_tabpage()
            assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(tab))
            local preview_buf
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
                local bufnr = vim.api.nvim_win_get_buf(win)
                if
                    vim.api
                        .nvim_buf_get_name(bufnr)
                        :find("history/request", 1, true)
                then
                    preview_buf = bufnr
                end
            end
            assert.is_true(vim.wait(3000, function()
                return preview_buf
                    and table
                            .concat(
                                vim.api.nvim_buf_get_lines(
                                    preview_buf,
                                    0,
                                    -1,
                                    false
                                ),
                                "\n"
                            )
                            :find("request payload", 1, true)
                        ~= nil
            end))
            assert.is_nil(
                table
                    .concat(
                        vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false),
                        "\n"
                    )
                    :find("saved response", 1, true)
            )

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
                return vim.api
                    .nvim_buf_get_lines(list_buf, 0, 1, false)[1]
                    :find("example.org", 1, true) ~= nil
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
        end
    )
end)

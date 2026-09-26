local Curl = require("nurl.curl")
local history = require("nurl.data.history")
local explorer = require("nurl.ui.history_explorer")
local highlights = require("nurl.ui.highlights")
local registry = require("nurl.registry")

describe("status colors", function()
    local original_page

    before_each(function()
        require("nurl").setup({})
        original_page = history.page
    end)

    after_each(function()
        history.page = original_page
        while #vim.api.nvim_list_tabpages() > 1 do
            vim.cmd.tabclose()
        end
        if #vim.api.nvim_tabpage_list_wins(0) > 1 then
            vim.cmd.only()
        end
    end)

    local function history_item(status_code)
        return {
            "2026-09-26T10:00:00",
            { method = "GET", url = "https://example.org", headers = {} },
            {
                status_code = status_code,
                reason_phrase = "",
                protocol = "HTTP/1.1",
                headers = {},
                body = "",
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
            Curl:new({
                args = {},
                result = { code = 0, signal = 0, stdout = "", stderr = "" },
            }),
        }
    end

    local function buffer_groups(bufnr)
        local groups = {}
        for _, mark in
            ipairs(
                vim.api.nvim_buf_get_extmarks(
                    bufnr,
                    -1,
                    0,
                    -1,
                    { details = true }
                )
            )
        do
            groups[mark[4].hl_group or ""] = true
        end
        return groups
    end

    it("groups status codes by class", function()
        assert.are.equal("NurlStatus", highlights.status_group(101))
        assert.are.equal("NurlStatusSuccess", highlights.status_group(204))
        assert.are.equal("NurlStatusRedirect", highlights.status_group(304))
        assert.are.equal("NurlStatusClientError", highlights.status_group(404))
        assert.are.equal("NurlStatusServerError", highlights.status_group(503))
    end)

    for _, case in ipairs({
        { 200, "NurlStatusSuccess" },
        { 304, "NurlStatusRedirect" },
        { 404, "NurlStatusClientError" },
        { 503, "NurlStatusServerError" },
    }) do
        local status_code, group = case[1], case[2]

        it(("uses %s for %d in every view"):format(group, status_code), function()
            local win = require("nurl").open_history_item(history_item(status_code))
            local winbar = vim.api.nvim_eval_statusline(
                vim.wo[win].winbar,
                { winid = win, use_winbar = true, highlights = true }
            )
            assert.are.equal(group, winbar.highlights[1].group)

            local handle_id = vim.b[vim.api.nvim_win_get_buf(win)].nurl_data.handle_id
            local info = registry:get(handle_id).buffers.info
            assert.is_true(buffer_groups(info)[group])

            history.page = function()
                return {
                    {
                        id = 1,
                        time = "2026-09-26T10:00:00",
                        method = "GET",
                        status = status_code,
                        url = "https://example.org",
                    },
                }, false
            end
            explorer.open()
            assert.is_true(buffer_groups(0)[group])
        end)
    end
end)

local Curl = require("nurl.curl")

describe("response window", function()
    before_each(function()
        require("nurl").setup({})
    end)

    after_each(function()
        if #vim.api.nvim_tabpage_list_wins(0) > 1 then
            vim.cmd.only()
        end
    end)

    it("toggles the info split with gi and leaves Enter alone", function()
        local win = require("nurl").open_history_item({
            "2026-09-26T10:00:00",
            { method = "GET", url = "https://example.org", headers = {} },
            {
                status_code = 200,
                reason_phrase = "OK",
                protocol = "HTTP/1.1",
                headers = {},
                body = "",
                time = {},
                size = {},
                speed = {},
            },
            Curl:new({
                args = {},
                result = { code = 0, signal = 0, stdout = "", stderr = "" },
            }),
        })
        vim.api.nvim_set_current_win(win)
        assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))

        assert.are.equal("", vim.fn.maparg("<CR>", "n"))
        vim.api.nvim_feedkeys("gi", "x", false)
        assert.are.equal(3, #vim.api.nvim_tabpage_list_wins(0))
        vim.api.nvim_feedkeys("gi", "x", false)
        assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))
    end)
end)

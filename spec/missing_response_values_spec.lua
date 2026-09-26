local Curl = require("nurl.curl")
local info_buffer = require("nurl.ui.info_buffer")

describe("responses without timing or size values", function()
    before_each(function()
        require("nurl").setup({})
    end)

    after_each(function()
        if #vim.api.nvim_tabpage_list_wins(0) > 1 then
            vim.cmd.only()
        end
    end)

    local function response()
        return {
            status_code = 200,
            reason_phrase = "OK",
            protocol = "HTTP/1.1",
            headers = {},
            body = "",
            time = {},
            size = {},
            speed = {},
        }
    end

    it("renders the info buffer", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        info_buffer.render(
            bufnr,
            "2026-09-26T10:00:00",
            { method = "GET", url = "https://example.org", headers = {} },
            response()
        )

        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        assert.matches("timing%s+unavailable", text)
        assert.matches("download%s+%-", text)
    end)

    it("renders the winbar without a time", function()
        local win = require("nurl").open_history_item({
            "2026-09-26T10:00:00",
            { method = "GET", url = "https://example.org", headers = {} },
            response(),
            Curl:new({
                args = {},
                result = { code = 0, signal = 0, stdout = "", stderr = "" },
            }),
        })
        local winbar = vim.api.nvim_eval_statusline(
            vim.wo[win].winbar,
            { winid = win, use_winbar = true }
        ).str
        assert.matches("200", winbar)
        assert.is_nil(winbar:find("·", 1, true))
    end)
end)

local Curl = require("nurl.core.curl")
local RequestHandle = require("nurl.app.handle")
local raw_tab = require("nurl.ui.response_view.tabs.raw")

describe("raw buffer", function()
    ---@param curl nurl.Curl
    ---@return string[]
    local function render(curl)
        local bufnr = vim.api.nvim_create_buf(false, true)
        local handle = RequestHandle:new({
            method = "POST",
            url = "https://example.com",
            headers = {},
        })
        handle.curl = curl

        raw_tab.render(bufnr, handle)

        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end

    it("shows a command with a body on several lines", function()
        local lines = render(Curl.build({
            method = "POST",
            url = "https://example.com",
            headers = {},
            data = "line1\nline2",
        }))

        assert.matches("^curl .*line1$", lines[1])
        assert.matches("^line2", lines[2])
    end)

    it("shows the output after the command", function()
        local lines = render(Curl:new({
            args = { "https://example.com" },
            result = {
                code = 0,
                signal = 0,
                stdout = "HTTP/1.1 200 OK\r\n\r\nhello",
                stderr = "0.1,0.2",
            },
        }))

        assert.are.same({
            "curl 'https://example.com'",
            "HTTP/1.1 200 OK\r",
            "\r",
            "hello",
            "0.1,0.2",
        }, lines)
    end)
end)

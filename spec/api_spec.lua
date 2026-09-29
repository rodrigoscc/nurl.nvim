local RequestHandle = require("nurl.app.handle")
local Curl = require("nurl.core.curl")

describe("public API", function()
    before_each(function()
        require("nurl").setup({ formatters = {} })
    end)

    after_each(function()
        vim.cmd("silent! only")
        vim.cmd.enew()
    end)

    it("has every field typed in meta/types.lua", function()
        local types = vim.fn.readfile("lua/nurl/meta/types.lua")
        local nurl = require("nurl")
        local fields = 0

        for _, line in ipairs(types) do
            local name, type = line:match("^%-%-%-@field ([%w_]+)%??%s+(%S+)")
            if name then
                fields = fields + 1
                local expected = type:match("^fun") and "function" or "table"
                assert.are.equal(expected, _G.type(nurl[name]), name)
            end
        end

        assert.is_true(fields > 10)
    end)

    it("is also the Nurl global", function()
        assert.are.equal(require("nurl"), _G.Nurl)
    end)

    it("gets the request shown in a response buffer", function()
        local request = { method = "GET", url = "https://example.org", headers = {} }
        local view = require("nurl.app.client").open_history_item({
            "2026-09-26T10:00:00",
            request,
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

        assert.are.equal(request, Nurl.get_request(view.buffers.headers))
        vim.api.nvim_set_current_win(view.win)
        assert.are.equal(request, Nurl.get_request())
        vim.cmd.new()
        assert.is_nil(Nurl.get_request())
    end)

    it("removed the internals it used to expose", function()
        assert.is_nil(Nurl.registry)
        assert.is_nil(Nurl.last_requests)
        assert.is_nil(Nurl.open_history_item)
    end)
end)

local pickers = require("nurl.pickers")
local client = require("nurl.app.client")
local Curl = require("nurl.core.curl")

local REQUESTS = [[
return {
    { "https://example.org/one" },
    {
        "https://example.org/two",
        method = "POST",
    },
}
]]

describe(":Nurl", function()
    local dir, file, single
    local stubbed = {}
    local calls, notifications

    ---Replace a module function for the test, recording its calls.
    ---@param module table
    ---@param name string
    local function stub(module, name)
        table.insert(stubbed, { module, name, module[name] })
        module[name] = function(...)
            table.insert(calls, { name, ... })
        end
    end

    before_each(function()
        dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        require("nurl").setup({
            dir = dir,
            formatters = {},
            trust = { enabled = false },
        })

        file = vim.fs.joinpath(dir, "requests.lua")
        vim.fn.writefile(vim.split(REQUESTS, "\n"), file)
        single = vim.fs.joinpath(dir, "single.lua")
        vim.fn.writefile({ 'return { { "https://example.org/single" } }' }, single)

        calls, notifications = {}, {}
        stub(client, "send")
        stub(client, "yank")
        stub(client, "resend")
        stub(pickers, "pick")
        table.insert(stubbed, { vim, "notify", vim.notify })
        vim.notify = function(msg, level)
            table.insert(notifications, { msg, level })
        end
    end)

    after_each(function()
        for _, s in ipairs(stubbed) do
            s[1][s[2]] = s[3]
        end
        stubbed = {}
        vim.cmd("silent! only")
        vim.cmd("silent! %bwipeout!")
        vim.fn.delete(dir, "rf")
    end)

    describe("at the cursor", function()
        before_each(function()
            vim.cmd.edit(file)
            vim.api.nvim_win_set_cursor(0, { 4, 8 })
        end)

        it("sends the request and shows it", function()
            vim.cmd("Nurl .")

            assert.are.equal(1, #calls)
            local name, request, opts = unpack(calls[1])
            assert.are.equal("send", name)
            assert.are.equal("https://example.org/two", request[1])
            assert.are.same({ display = true }, opts)
        end)

        it("applies overrides", function()
            vim.cmd("Nurl . method=PUT headers.X-Debug=1")

            local request = calls[1][2]
            assert.are.equal("PUT", request.method)
            assert.are.same({ ["X-Debug"] = 1 }, request.headers)
        end)

        it("yanks the curl command", function()
            vim.cmd("Nurl yank .")

            assert.are.equal("yank", calls[1][1])
            assert.are.equal("https://example.org/two", calls[1][2][1])
        end)

        it("cannot jump", function()
            vim.cmd("Nurl jump .")

            assert.are.same({}, calls)
            assert.are.equal("Cannot jump at cursor", notifications[1][1])
        end)

        it("reports when there is no request", function()
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("Nurl .")

            assert.are.same({}, calls)
            assert.are.same(
                { "No request found at cursor", vim.log.levels.ERROR },
                notifications[1]
            )
        end)
    end)

    it("sends the request of a response window there again", function()
        local request = { method = "GET", url = "https://example.org", headers = {} }
        local view = client.open_history_item({
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

        vim.cmd("Nurl .")

        local _, sent, opts = unpack(calls[1])
        assert.are.same(request, sent)
        assert.are.same({ display = { win = view.win } }, opts)
    end)

    it("sends the only request of a file without a picker", function()
        vim.cmd("Nurl " .. single)

        assert.are.equal("send", calls[1][1])
        assert.are.equal("https://example.org/single", calls[1][2][1])
    end)

    it("picks one of the requests of a file", function()
        vim.cmd("Nurl " .. file)

        local name, title, items, on_pick = unpack(calls[1])
        assert.are.equal("pick", name)
        assert.are.equal("Nurl: send", title)
        assert.are.equal(2, #items)
        assert.are.equal(file, items[1].file)

        on_pick(items[1])
        assert.are.equal("send", calls[2][1])
        assert.are.equal("https://example.org/one", calls[2][2][1])
    end)

    it("picks one of the project requests, even if there is one", function()
        vim.fn.delete(file)

        vim.cmd("Nurl yank")

        local name, title, items = unpack(calls[1])
        assert.are.equal("pick", name)
        assert.are.equal("Nurl: yank", title)
        assert.are.equal(1, #items)
    end)

    it("jumps with the picker's own jump", function()
        vim.cmd("Nurl jump " .. file)

        local name, title, _, on_pick = unpack(calls[1])
        assert.are.equal("pick", name)
        assert.are.equal("Nurl: jump", title)
        assert.is_nil(on_pick)
    end)

    it("resends a recent request by index", function()
        vim.cmd("Nurl resend -2 method=PUT")

        local name, index, overrides = unpack(calls[1])
        assert.are.equal("resend", name)
        assert.are.equal(-2, index)
        assert.are.same({ { { "method" }, "PUT" } }, overrides)
    end)

    it("warns when there is nothing to resend", function()
        client.recent.items = {}

        vim.cmd("Nurl resend")

        assert.are.same({}, calls)
        assert.are.equal("No recent requests to resend", notifications[1][1])
    end)
end)

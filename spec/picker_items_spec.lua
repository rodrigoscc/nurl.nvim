local items = require("nurl.pickers.items")
local variables = require("nurl.variables")

describe("picker items", function()
    local notify = vim.notify
    local notifications

    before_each(function()
        notifications = {}
        vim.notify = function(msg)
            table.insert(notifications, msg)
        end
    end)

    after_each(function()
        vim.notify = notify
    end)

    it("expands requests but keeps lazy values for sending", function()
        local evaluated = false
        local token = variables.lazy(function()
            evaluated = true
            return "secret"
        end)

        local prepared = items.prepare({
            {
                request = {
                    url = function()
                        return "https://example.org"
                    end,
                    headers = { Authorization = token },
                },
                file = "requests.lua",
                start_row = 3,
            },
        })

        assert.is_false(evaluated)
        assert.are.equal(1, #prepared)

        local item = prepared[1].item
        assert.are.equal("https://example.org", item.request.url)
        assert.is_true(variables.is_lazy(item.request.headers.Authorization))
        assert.are.equal("requests.lua", item.file)
        assert.are.equal(3, item.start_row)

        assert.are.equal(
            variables.LAZY_PLACEHOLDER,
            prepared[1].preview.headers.Authorization
        )
        assert.are.equal("GET https://example.org requests.lua", prepared[1].text)
    end)

    it("does not change the items it is given", function()
        local request = { "https://example.org" }
        local given = { request = request }

        items.prepare({ given })

        assert.are.equal(request, given.request)
    end)

    it("skips requests that fail to expand", function()
        local prepared = items.prepare({
            { request = { "https://example.org/ok" } },
            {
                request = { "https://example.org", url = "https://other.org" },
                file = "requests.lua",
                start_row = 7,
            },
        })

        assert.are.equal(1, #prepared)
        assert.are.equal("https://example.org/ok", prepared[1].item.request.url)
        assert.matches("^Skipped request in requests.lua:7 after error", notifications[1])
    end)
end)

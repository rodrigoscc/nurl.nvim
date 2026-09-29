local formatter = require("nurl.infra.formatter")

describe("formatter", function()
    local upper = { cmd = { "tr", "a-z", "A-Z" } }

    it("finds the formatter of a file type", function()
        assert.are.equal(upper, formatter.find({ json = upper }, "json"))
        assert.is_nil(formatter.find({ json = upper }, "xml"))
    end)

    it("skips a formatter that is not available", function()
        local missing = {
            cmd = { "missing" },
            available = function()
                return false
            end,
        }

        assert.is_nil(formatter.find({ json = missing }, "json"))
    end)

    it("formats and waits without a callback", function()
        local result = formatter.run(upper, "hello")

        assert.are.equal(0, result.code)
        assert.are.equal("HELLO", result.stdout)
    end)

    it("formats in the background with a callback", function()
        local result
        local returned = formatter.run(upper, "hello", function(out)
            result = out
        end)

        assert.is_nil(returned)
        assert.is_true(vim.wait(2000, function()
            return result ~= nil
        end))
        assert.are.equal("HELLO", result.stdout)
    end)
end)

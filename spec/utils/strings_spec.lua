local strings = require("nurl.utils.strings")

describe("utils.strings", function()
    describe("title", function()
        it("capitalizes first letter of lowercase string", function()
            assert.are.equal("Hello", strings.title("hello"))
        end)

        it("keeps already capitalized string unchanged", function()
            assert.are.equal("Hello", strings.title("Hello"))
        end)

        it("handles single character", function()
            assert.are.equal("A", strings.title("a"))
        end)

        it("handles empty string", function()
            assert.are.equal("", strings.title(""))
        end)

        it("handles string starting with number", function()
            assert.are.equal("123abc", strings.title("123abc"))
        end)
    end)

    describe("is_identifier", function()
        it("accepts Lua names", function()
            for _, name in ipairs({ "token", "_private", "api_key2" }) do
                assert.is_true(strings.is_identifier(name), name)
            end
        end)

        it("rejects other text and keywords", function()
            for _, name in ipairs({ "api-key", "1st", "", "a b", "end", "nil" }) do
                assert.is_false(strings.is_identifier(name), name)
            end
        end)
    end)
end)

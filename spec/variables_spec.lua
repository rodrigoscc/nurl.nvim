local variables = require("nurl.variables")

describe("variables", function()
    describe("expand", function()
        it("returns nil for nil input", function()
            assert.is_nil(variables.expand(nil))
        end)

        it("returns string as-is", function()
            assert.are.equal("hello", variables.expand("hello"))
        end)

        it("returns number as-is", function()
            assert.are.equal(42, variables.expand(42))
        end)

        it("returns boolean as-is", function()
            assert.is_true(variables.expand(true))
            assert.is_false(variables.expand(false))
        end)

        it("calls function and returns result", function()
            local fn = function()
                return "dynamic"
            end
            assert.are.equal("dynamic", variables.expand(fn))
        end)

        it("expands table recursively", function()
            local tbl = { a = 1, b = "two" }
            local result = variables.expand(tbl)
            assert.are.same({ a = 1, b = "two" }, result)
        end)
    end)

    describe("expand_table", function()
        it("expands functions in table", function()
            local tbl = {
                static = "value",
                dynamic = function()
                    return "computed"
                end,
            }
            local result = variables.expand_table(tbl)
            assert.are.equal("value", result.static)
            assert.are.equal("computed", result.dynamic)
        end)

        it("expands nested tables", function()
            local tbl = {
                nested = {
                    fn = function()
                        return "nested_value"
                    end,
                },
            }
            local result = variables.expand_table(tbl)
            assert.are.equal("nested_value", result.nested.fn)
        end)

        it("handles nil values in table", function()
            local tbl = { a = 1, b = nil, c = 3 }
            local result = variables.expand_table(tbl)
            assert.are.equal(1, result.a)
            assert.is_nil(result.b)
            assert.are.equal(3, result.c)
        end)

        it("handles empty table", function()
            local result = variables.expand_table({})
            assert.are.same({}, result)
        end)

        it("deeply nested functions", function()
            local tbl = {
                level1 = {
                    level2 = {
                        value = function()
                            return "deep"
                        end,
                    },
                },
            }
            local result = variables.expand_table(tbl)
            assert.are.equal("deep", result.level1.level2.value)
        end)
    end)
end)

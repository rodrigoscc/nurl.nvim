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

    describe("lazy", function()
        it("creates a lazy value", function()
            local lazy_val = variables.lazy(function()
                return "lazy_result"
            end)
            assert.is_true(variables.is_lazy(lazy_val))
        end)

        it("is_lazy returns false for non-lazy values", function()
            assert.is_falsy(variables.is_lazy("string"))
            assert.is_falsy(variables.is_lazy(123))
            assert.is_falsy(variables.is_lazy({}))
            assert.is_falsy(variables.is_lazy(nil))
        end)

        it("expand resolves lazy values by default", function()
            local lazy_val = variables.lazy(function()
                return "lazy_result"
            end)
            local result = variables.expand(lazy_val)
            assert.are.equal("lazy_result", result)
        end)

        it("expand preserves lazy values with lazy option", function()
            local lazy_val = variables.lazy(function()
                return "lazy_result"
            end)
            local result = variables.expand(lazy_val, { lazy = true })
            assert.is_true(variables.is_lazy(result))
        end)

        it("expand_table resolves lazy values by default", function()
            local tbl = {
                static = "value",
                lazy_field = variables.lazy(function()
                    return "lazy_result"
                end),
            }
            local result = variables.expand_table(tbl)
            assert.are.equal("value", result.static)
            assert.are.equal("lazy_result", result.lazy_field)
        end)

        it("expand_table preserves lazy values with lazy option", function()
            local tbl = {
                static = "value",
                lazy_field = variables.lazy(function()
                    return "lazy_result"
                end),
            }
            local result = variables.expand_table(tbl, { lazy = true })
            assert.are.equal("value", result.static)
            assert.is_true(variables.is_lazy(result.lazy_field))
        end)

        it("expand resolves nested lazy values by default", function()
            local tbl = {
                nested = {
                    lazy_field = variables.lazy(function()
                        return "nested_lazy"
                    end),
                },
            }
            local result = variables.expand(tbl)
            assert.are.equal("nested_lazy", result.nested.lazy_field)
        end)

        it("expand preserves nested lazy values with lazy option", function()
            local tbl = {
                nested = {
                    lazy_field = variables.lazy(function()
                        return "nested_lazy"
                    end),
                },
            }
            local result = variables.expand(tbl, { lazy = true })
            assert.is_true(variables.is_lazy(result.nested.lazy_field))
        end)

        it("expand resolves lazy value returned by function", function()
            local fn = function()
                return variables.lazy(function()
                    return "from_lazy"
                end)
            end
            local result = variables.expand(fn)
            assert.are.equal("from_lazy", result)
        end)

        it("expand preserves lazy value returned by function with lazy option", function()
            local fn = function()
                return variables.lazy(function()
                    return "from_lazy"
                end)
            end
            local result = variables.expand(fn, { lazy = true })
            assert.is_true(variables.is_lazy(result))
        end)
    end)

    describe("stringify_lazy", function()
        it("replaces lazy value with placeholder", function()
            local lazy_val = variables.lazy(function()
                return "secret"
            end)
            local result = variables.stringify_lazy(lazy_val)
            assert.are.equal(variables.LAZY_PLACEHOLDER, result)
        end)

        it("returns non-lazy values unchanged", function()
            assert.are.equal("string", variables.stringify_lazy("string"))
            assert.are.equal(123, variables.stringify_lazy(123))
            assert.is_nil(variables.stringify_lazy(nil))
        end)

        it("replaces lazy values in table", function()
            local tbl = {
                static = "value",
                lazy_field = variables.lazy(function()
                    return "secret"
                end),
            }
            local result = variables.stringify_lazy(tbl)
            assert.are.equal("value", result.static)
            assert.are.equal(variables.LAZY_PLACEHOLDER, result.lazy_field)
        end)

        it("replaces nested lazy values", function()
            local tbl = {
                nested = {
                    lazy_field = variables.lazy(function()
                        return "secret"
                    end),
                },
            }
            local result = variables.stringify_lazy(tbl)
            assert.are.equal(variables.LAZY_PLACEHOLDER, result.nested.lazy_field)
        end)

        it("handles function returning lazy value", function()
            local tbl = {
                fn = function()
                    return variables.lazy(function()
                        return "secret"
                    end)
                end,
            }
            local result = variables.stringify_lazy(tbl)
            assert.are.equal(variables.LAZY_PLACEHOLDER, result.fn)
        end)
    end)
end)

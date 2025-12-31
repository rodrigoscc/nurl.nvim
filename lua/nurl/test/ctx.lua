local Test = require("nurl.test.test")

---@alias nurl.Assert1Fun fun(actual: any, message?: string)
---@alias nurl.Assert2Fun fun(expected: any, actual: any, message?: string)

---@class nurl.Assertions
---@field equal nurl.Assert2Fun
---@field same nurl.Assert2Fun

---@class nurl.TestContext
---@field are nurl.Assertions
---@field are_not nurl.Assertions
---@field is_true nurl.Assert1Fun
---@field is_false nurl.Assert1Fun
---@field truthy nurl.Assert1Fun
---@field falsy nurl.Assert1Fun
---@field is_nil nurl.Assert1Fun
---@field is_not_nil nurl.Assert1Fun
---@field test fun(name: string, fn: fun())
local TestContext = {}

function TestContext:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

local M = {}

---@param report nurl.TestReport
---@return nurl.TestContext
function M.build_ctx(report)
    local test = Test:new({ report = report })

    local ctx = TestContext:new({
        are = {
            same = function(expected, actual, message)
                test:same(expected, actual, message)
            end,
            equal = function(expected, actual, message)
                test:equal(expected, actual, message)
            end,
        },
        are_not = {
            same = function(expected, actual, message)
                test:not_same(expected, actual, message)
            end,
            equal = function(expected, actual, message)
                test:not_equal(expected, actual, message)
            end,
        },
        is_true = function(value, message)
            test:is_true(value, message)
        end,
        is_false = function(value, message)
            test:is_false(value, message)
        end,
        truthy = function(value, message)
            test:truthy(value, message)
        end,
        falsy = function(value, message)
            test:falsy(value, message)
        end,
        is_nil = function(value, message)
            test:is_nil(value, message)
        end,
        is_not_nil = function(value, message)
            test:is_not_nil(value, message)
        end,
        test = function(name, fn)
            report:start_suite(name)
            local ok, err = pcall(fn)
            if not ok then
                report:error(err)
            end
            report:end_suite()
        end,
    })

    return ctx
end

return M

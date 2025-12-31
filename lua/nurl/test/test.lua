---@class nurl.Test
---@field report nurl.TestReport
local Test = {}

function Test:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@param passed boolean
---@param expected any
---@param actual any
---@param message? string
function Test:_record(passed, expected, actual, message)
    if passed then
        self.report:passed(expected, actual, message)
    else
        self.report:failed(expected, actual, message)
    end
end

---@param value any
---@param message? string
function Test:is_true(value, message)
    self:_record(value == true, true, value, message)
end

---@param value any
---@param message? string
function Test:is_false(value, message)
    self:_record(value == false, false, value, message)
end

---@param value any
---@param message? string
function Test:truthy(value, message)
    self:_record(not not value, true, value, message)
end

---@param value any
---@param message? string
function Test:falsy(value, message)
    self:_record(not value, false, value, message)
end

---@param expected any
---@param actual any
---@param message? string
function Test:same(expected, actual, message)
    self:_record(vim.deep_equal(expected, actual), expected, actual, message)
end

---@param expected any
---@param actual any
---@param message? string
function Test:equal(expected, actual, message)
    self:_record(actual == expected, expected, actual, message)
end

---@param expected any
---@param actual any
---@param message? string
function Test:not_same(expected, actual, message)
    self:_record(
        not vim.deep_equal(expected, actual),
        expected,
        actual,
        message
    )
end

---@param expected any
---@param actual any
---@param message? string
function Test:not_equal(expected, actual, message)
    self:_record(actual ~= expected, expected, actual, message)
end

---@param value any
---@param message? string
function Test:is_nil(value, message)
    self:_record(value == nil, nil, value, message)
end

---@param value any
---@param message? string
function Test:is_not_nil(value, message)
    self:_record(value ~= nil, nil, value, message)
end

return Test

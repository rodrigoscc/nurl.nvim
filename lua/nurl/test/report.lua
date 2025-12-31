local suites = require("nurl.test.suites")

---@class nurl.TestResult
---@field passed boolean
---@field expected any
---@field actual any
---@field message? string
---@field error? string

---@class nurl.TestSuite
---@field name string
---@field results (nurl.TestSuite|nurl.TestResult)[]

---@class nurl.TestReport
---@field private results (nurl.TestSuite|nurl.TestResult)[]
---@field private suites_stack nurl.TestSuite[]
local TestReport = {}

function TestReport:new(o)
    o = o or { results = {}, suites_stack = {} }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function TestReport:_stack_results()
    if #self.suites_stack > 0 then
        return self.suites_stack[#self.suites_stack].results
    end

    return self.results
end

function TestReport:_push_stack(suite)
    table.insert(self.suites_stack, suite)
end

function TestReport:_pop_stack()
    table.remove(self.suites_stack, #self.suites_stack)
end

---@param expected any
---@param actual any
---@param message? string
function TestReport:passed(expected, actual, message)
    local stack_results = self:_stack_results()
    local new_result = {
        passed = true,
        expected = expected,
        actual = actual,
        message = message,
    }
    table.insert(stack_results, new_result)
end

---@param expected any
---@param actual any
---@param message? string
function TestReport:failed(expected, actual, message)
    local stack_results = self:_stack_results()
    local new_result = {
        passed = false,
        expected = expected,
        actual = actual,
        message = message,
    }
    table.insert(stack_results, new_result)
end

---@param err string
function TestReport:error(err)
    local stack_results = self:_stack_results()
    local new_result = {
        passed = false,
        error = err,
    }
    table.insert(stack_results, new_result)
end

---@param name string
function TestReport:start_suite(name)
    local stack_results = self:_stack_results()
    local suite = { name = name, results = {} }
    table.insert(stack_results, suite)
    self:_push_stack(suite)
end

function TestReport:end_suite()
    self:_pop_stack()
end

function TestReport:get_results()
    assert(#self.suites_stack == 0, "suites stack should be empty")
    return self.results
end

---@param results (nurl.TestResult|nurl.TestSuite)[]
local function results_has_failures(results)
    for _, item in ipairs(results) do
        if suites.is_suite(item) then
            ---@cast item nurl.TestSuite
            if results_has_failures(item.results) then
                return true
            end
        else
            ---@cast item nurl.TestResult
            if not item.passed or item.error then
                return true
            end
        end
    end
end

---@return boolean
function TestReport:has_failures()
    for _, item in ipairs(self.results) do
        if suites.is_suite(item) then
            ---@cast item nurl.TestSuite
            if results_has_failures(item.results) then
                return true
            end
        else
            ---@cast item nurl.TestResult
            if not item.passed or item.error then
                return true
            end
        end
    end

    return false
end

return TestReport

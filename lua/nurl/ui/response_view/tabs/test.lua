local config = require("nurl.config")
local suites = require("nurl.test.suites")
local TextBuilder = require("nurl.ui.text_builder")

local M = {}

local ns = vim.api.nvim_create_namespace("nurl.test")

---@param results (nurl.TestResult|nurl.TestSuite)[]
---@return number passed
---@return number failed
---@return number errors
local function count_results(results)
    local passed = 0
    local failed = 0
    local errors = 0

    for _, item in ipairs(results) do
        if suites.is_suite(item) then
            ---@cast item nurl.TestSuite
            local p, f, e = count_results(item.results)
            passed = passed + p
            failed = failed + f
            errors = errors + e
        else
            ---@cast item nurl.TestResult
            if item.error then
                errors = errors + 1
            elseif item.passed then
                passed = passed + 1
            else
                failed = failed + 1
            end
        end
    end

    return passed, failed, errors
end

---@param value any
---@return string
local function format_value(value)
    if type(value) == "table" then
        return vim.inspect(value, { indent = "  ", newline = "\n" })
    elseif type(value) == "string" then
        return string.format('"%s"', value)
    elseif value == nil then
        return "nil"
    else
        return tostring(value)
    end
end

---@param value any
---@return boolean
local function is_multiline(value)
    return type(value) == "table"
end

---@class nurl.FlattenedResult
---@field result nurl.TestResult
---@field breadcrumb string

---@param results (nurl.TestResult|nurl.TestSuite)[]
---@param breadcrumb string
---@param failures nurl.FlattenedResult[]
---@param errors nurl.FlattenedResult[]
local function flatten_results(results, breadcrumb, failures, errors)
    for _, item in ipairs(results) do
        if suites.is_suite(item) then
            ---@cast item nurl.TestSuite
            local new_breadcrumb = breadcrumb == "" and item.name
                or (breadcrumb .. " " .. item.name)

            flatten_results(item.results, new_breadcrumb, failures, errors)
        else
            ---@cast item nurl.TestResult
            if item.error then
                table.insert(errors, { result = item, breadcrumb = breadcrumb })
            elseif not item.passed then
                table.insert(
                    failures,
                    { result = item, breadcrumb = breadcrumb }
                )
            end
        end
    end
end

---@param builder nurl.TextBuilder
---@param flattened nurl.FlattenedResult
local function render_failure(builder, flattened)
    local result = flattened.result
    local breadcrumb = flattened.breadcrumb

    local label_hl = config.highlight.groups.test_label

    local expected_str = format_value(result.expected)
    local actual_str = format_value(result.actual)
    local multiline = is_multiline(result.expected)
        or is_multiline(result.actual)

    builder:newline()
    builder:newline()
    builder:append("Failure", config.highlight.groups.test_fail)

    if breadcrumb ~= "" then
        builder:newline()
        builder:append(breadcrumb, config.highlight.groups.test_suite_name)
    end

    if result.message then
        builder:newline()
        builder:append(result.message)
    end

    local actual_hl = config.highlight.groups.test_value_actual
    local expected_hl = config.highlight.groups.test_value_expected

    if multiline then
        builder:newline()
        builder:append("Passed in:", label_hl)
        for line in actual_str:gmatch("[^\n]+") do
            builder:newline()
            builder:append(line, actual_hl)
        end
        builder:newline()
        builder:append("Expected:", label_hl)
        for line in expected_str:gmatch("[^\n]+") do
            builder:newline()
            builder:append(line, expected_hl)
        end
    else
        builder:newline()
        builder:append("Passed in: ", label_hl)
        builder:append(actual_str, actual_hl)
        builder:newline()
        builder:append("Expected: ", label_hl)
        builder:append(expected_str, expected_hl)
    end
end

---@param builder nurl.TextBuilder
---@param flattened nurl.FlattenedResult
local function render_error(builder, flattened)
    local result = flattened.result
    local breadcrumb = flattened.breadcrumb

    builder:newline()
    builder:newline()
    builder:append("Error", config.highlight.groups.test_error)

    if breadcrumb ~= "" then
        builder:newline()
        builder:append(breadcrumb, config.highlight.groups.test_suite_name)
    end

    builder:newline()
    builder:append(result.error, config.highlight.groups.test_value)
end

---The results of the request's tests.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    if handle.response == nil then
        return
    end
    local test_report = handle.test_report

    local builder = TextBuilder:new()

    if test_report == nil then
        builder:append("No tests", "Comment")

        builder:render(bufnr, ns)
        return
    end

    local results = test_report:get_results()

    if #results == 0 then
        builder:append("No tests", "Comment")

        builder:render(bufnr, ns)
        return
    end

    local passed, failed, errors = count_results(results)

    builder:append(tostring(passed), config.highlight.groups.test_pass)
    builder:append(" successes" .. " / ")
    builder:append(tostring(failed), config.highlight.groups.test_fail)
    builder:append(" failures" .. " / ")
    builder:append(tostring(errors), config.highlight.groups.test_error)
    builder:append(" errors")

    ---@type nurl.FlattenedResult[]
    local failures = {}
    ---@type nurl.FlattenedResult[]
    local errs = {}

    flatten_results(results, "", failures, errs)

    for _, flattened in ipairs(failures) do
        render_failure(builder, flattened)
    end

    for _, flattened in ipairs(errs) do
        render_error(builder, flattened)
    end

    builder:render(bufnr, ns)
end

return M

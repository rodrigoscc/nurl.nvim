local config = require("nurl.config")
local highlights = require("nurl.ui.highlights")
local strings = require("nurl.utils.strings")
local request_format = require("nurl.core.request_format")
local numbers = require("nurl.utils.numbers")

local M = {}

---@return nurl.ResponseView?
local function current_view()
    -- Required here: the view requires this module.
    return require("nurl.ui.response_view").for_buf(
        vim.api.nvim_get_current_buf()
    )
end

function M.request_title()
    local view = current_view()
    if not view then
        return ""
    end

    local request = view.handle.request

    local title = request.title
        or request_format.full_url(request):gsub("^%w+://", "")
    title = strings.escape_percentage(title)

    return string.format(
        "%%#%s#%s%%* %%#%s#%s%%*",
        config.highlight.groups.info_method,
        request.method,
        config.highlight.groups.winbar_title,
        title
    )
end

function M.status_code()
    local view = current_view()
    if not view then
        return ""
    end

    local handle = view.handle
    local response = handle.response

    if response ~= nil then
        local status_code = response.status_code
        return string.format(
            "%%#%s#%s %s%%*",
            highlights.status_group(status_code),
            highlights.status_icon(status_code),
            status_code
        )
    end

    if handle:is_failed() then
        return string.format(
            "%%#%s#󰅚 Error%%*",
            config.highlight.groups.winbar_error
        )
    end

    if handle:is_cancelled() then
        return string.format(
            "%%#%s#󰜺 Cancelled%%*",
            config.highlight.groups.winbar_warning
        )
    end

    return string.format(
        "%%#%s#󰦖 Loading%%*",
        config.highlight.groups.winbar_loading
    )
end

function M.time()
    local view = current_view()
    local response = view and view.handle.response

    if response ~= nil and response.time.time_total ~= nil then
        return string.format(
            " %%#%s#· %s%%*",
            config.highlight.groups.winbar_time,
            numbers.format_duration(response.time.time_total)
        )
    end

    return ""
end

---@param buffer_name string
---@param has_test_failures boolean
---@return string
local function get_active_tab_highlight(buffer_name, has_test_failures)
    if buffer_name == "test" and has_test_failures then
        return config.highlight.groups.test_fail
    end

    return config.highlight.groups.winbar_tab_active
end

---@param buffer_name string
---@param has_test_failures boolean
---@return string
local function get_inactive_tab_highlight(buffer_name, has_test_failures)
    if buffer_name == "test" and has_test_failures then
        return config.highlight.groups.test_fail
    end

    return config.highlight.groups.winbar_tab_inactive
end

function M.tabs()
    local view = current_view()
    if not view then
        return ""
    end

    local buffer_type = view:type_of(vim.api.nvim_get_current_buf())
    ---@cast buffer_type nurl.BufferType
    local active_name = strings.title(buffer_type)
    local test_report = view.handle.test_report
    local has_test_failures = test_report and test_report:has_failures()
        or false

    local dots = {}
    for _, buffer in ipairs(config.buffers) do
        local is_active = buffer[1] == buffer_type
        if is_active then
            local hl = get_active_tab_highlight(buffer[1], has_test_failures)
            table.insert(dots, string.format("%%#%s#●%%*", hl))
        else
            local hl = get_inactive_tab_highlight(buffer[1], has_test_failures)
            table.insert(dots, string.format("%%#%s#○%%*", hl))
        end
    end

    return string.format(
        "%%#%s#%s%%* %s",
        get_active_tab_highlight(buffer_type, has_test_failures),
        active_name,
        table.concat(dots, " ")
    )
end

function M.winbar()
    return "%{%v:lua.Nurl.winbar.status_code()%} %<%{%v:lua.Nurl.winbar.request_title()%}%{%v:lua.Nurl.winbar.time()%} %=%{%v:lua.Nurl.winbar.tabs()%}"
end

return M

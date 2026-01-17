local config = require("nurl.config")
local strings = require("nurl.utils.strings")
local requests = require("nurl.requests")
local numbers = require("nurl.utils.numbers")
local registry = require("nurl.registry")

local M = {}

function M.request_title()
    local entry = registry:get(vim.b[0].nurl_data.handle_id)
    local request = entry.handle.request

    local title = ""

    if request and request.title then
        title = request.title
    elseif request.url then
        title = requests.title(request)
    end

    -- % in statusline is special
    title = strings.escape_percentage(title)

    return string.format(
        "%%#%s#%s %%*",
        config.highlight.groups.winbar_title,
        title
    )
end

function M.status_code()
    local entry = registry:get(vim.b[0].nurl_data.handle_id)
    local response = entry.handle.response

    if response ~= nil then
        if response.status_code <= 299 then
            return string.format(
                "%%#%s#󰄬 %s%%*",
                config.highlight.groups.winbar_success_status_code,
                response.status_code
            )
        else
            return string.format(
                "%%#%s#󰅚 %s%%*",
                config.highlight.groups.winbar_error_status_code,
                response.status_code
            )
        end
    end

    if entry.handle:is_failed() then
        return string.format(
            "%%#%s#󰅚 Error%%*",
            config.highlight.groups.winbar_error
        )
    end

    if entry.handle:is_cancelled() then
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
    local entry = registry:get(vim.b[0].nurl_data.handle_id)
    local response = entry.handle.response

    if response ~= nil then
        return string.format(
            "%%#%s#(took %s)%%*",
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
        return config.highlight.groups.winbar_error_status_code
    end

    return config.highlight.groups.winbar_tab_active
end

---@param buffer_name string
---@param has_test_failures boolean
---@return string
local function get_inactive_tab_highlight(buffer_name, has_test_failures)
    if buffer_name == "test" and has_test_failures then
        return config.highlight.groups.winbar_error_status_code
    end

    return config.highlight.groups.winbar_tab_inactive
end

function M.tabs()
    local entry = registry:get(vim.b[0].nurl_data.handle_id)

    local buffer_type = vim.b[0].nurl_data.buffer_type
    local active_name = strings.title(buffer_type)
    local has_test_failures = entry.handle.test_report
            and entry.handle.test_report:has_failures()
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

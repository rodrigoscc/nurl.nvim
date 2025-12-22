local config = require("nurl.config")
local strings = require("nurl.utils.strings")
local requests = require("nurl.requests")
local numbers = require("nurl.utils.numbers")

local M = {}

function M.request_title()
    local request = vim.b[0].nurl_data.request

    local title = ""

    if request and request.title then
        title = request.title
    elseif request.url then
        title = requests.title(request)
    end

    -- % in statusline is special
    title = strings.escape_percentage(title)

    return string.format(
        "%%#%s# %s %%*",
        config.highlight.groups.winbar_title,
        title
    )
end

function M.status_code()
    local response = vim.b[0].nurl_data.response

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

    local curl = vim.b[0].nurl_data.curl

    if curl.result and curl.result.code ~= 0 then
        return string.format(
            "%%#%s#󰅚 Error%%*",
            config.highlight.groups.winbar_error
        )
    end

    if curl.result and curl.result.signal ~= 0 then
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
    local response = vim.b[0].nurl_data.response

    if response ~= nil then
        return string.format(
            "%%#%s#(took %s)%%*",
            config.highlight.groups.winbar_time,
            numbers.format_duration(response.time.time_total)
        )
    end

    return ""
end

function M.tabs()
    local buffer_type = vim.b[0].nurl_data.buffer_type
    local active_name = strings.title(buffer_type)

    local dots = {}
    for _, buffer in ipairs(config.buffers) do
        local is_active = buffer[1] == buffer_type
        if is_active then
            table.insert(
                dots,
                string.format(
                    "%%#%s#●%%*",
                    config.highlight.groups.winbar_tab_active
                )
            )
        else
            table.insert(
                dots,
                string.format(
                    "%%#%s#○%%*",
                    config.highlight.groups.winbar_tab_inactive
                )
            )
        end
    end

    return string.format(
        "%%#%s#%s%%* %s",
        config.highlight.groups.winbar_tab_active,
        active_name,
        table.concat(dots, " ")
    )
end

function M.winbar()
    return "%{%v:lua.Nurl.winbar.status_code()%}%<%{%v:lua.Nurl.winbar.request_title()%}%{%v:lua.Nurl.winbar.time()%} %=%{%v:lua.Nurl.winbar.tabs()%}"
end

return M

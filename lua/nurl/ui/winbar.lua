local config = require("nurl.config")
local strings = require("nurl.utils.strings")

local M = {}

function M.request_title()
    local request = vim.b[0].nurl_request

    if request and request.title then
        return string.format(
            "%%#%s# %s %%*",
            config.highlight.groups.winbar_title,
            request.title
        )
    elseif request.url then
        return string.format(
            "%%#%s# %s %%*",
            config.highlight.groups.winbar_title,
            request.url
        )
    end

    return ""
end

function M.status_code()
    local response = vim.b[0].nurl_response

    if response ~= nil then
        if response.status_code <= 299 then
            return string.format(
                "%%#%s# %s %%*",
                config.highlight.groups.winbar_success_status_code,
                response.status_code
            )
        else
            return string.format(
                "%%#%s# %s %%*",
                config.highlight.groups.winbar_error_status_code,
                response.status_code
            )
        end
    end

    local curl = vim.b[0].nurl_curl

    if curl.result and curl.result.code ~= 0 then
        return string.format(
            "%%#%s#[Error]%%*",
            config.highlight.groups.winbar_error
        )
    end

    if curl.result and curl.result.signal ~= 0 then
        return string.format(
            "%%#%s#[Cancelled]%%*",
            config.highlight.groups.winbar_warning
        )
    end

    return string.format(
        "%%#%s#[Loading]%%*",
        config.highlight.groups.winbar_loading
    )
end

function M.time()
    local response = vim.b[0].nurl_response

    if response ~= nil then
        local seconds = string.format("%.2f", response.time.time_total)
        return string.format(
            "%%#%s#(took %ss)%%*",
            config.highlight.groups.winbar_time,
            seconds
        )
    end

    return ""
end

function M.buffer_tab(type)
    local buffer_type = vim.b[0].nurl_buffer_type

    local is_active = buffer_type == type

    if is_active then
        return string.format(
            "%%#%s# %s %%*",
            config.highlight.groups.winbar_tab_active,
            strings.title(type)
        )
    else
        return string.format(
            "%%#%s# %s %%*",
            config.highlight.groups.winbar_tab_inactive,
            strings.title(type)
        )
    end
end

function M.tabs()
    local tabs = ""

    for _, buffer in pairs(config.buffers) do
        tabs = tabs
            .. string.format(
                '%%{%%v:lua.Nurl.winbar.buffer_tab("%s")%%}',
                buffer[1]
            )
    end

    return tabs
end

function M.winbar()
    return "%{%v:lua.Nurl.winbar.status_code()%}%<%{%v:lua.Nurl.winbar.request_title()%}%{%v:lua.Nurl.winbar.time()%} %=%{%v:lua.Nurl.winbar.tabs()%}"
end

return M

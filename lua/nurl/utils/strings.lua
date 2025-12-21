local M = {}

--- Convert text into a title.
---@param text string
---@return string
function M.title(text)
    local new_text = text:gsub("^%l", string.upper)
    return new_text
end

--- Escape percentage signs found in uri encoded strings.
---@param text string to escape
---@return string text
function M.escape_percentage(text)
    local escaped = text:gsub("%%", "%%%%")
    return escaped
end

return M

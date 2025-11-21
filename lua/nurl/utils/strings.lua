local M = {}

--- Convert text into a title.
---@param text string
---@return string
function M.title(text)
    local new_text = text:gsub("^%l", string.upper)
    return new_text
end

return M

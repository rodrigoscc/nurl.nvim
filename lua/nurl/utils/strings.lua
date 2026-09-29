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

local lua_keywords = {}
for _, keyword in ipairs({
    "and",
    "break",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "goto",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
}) do
    lua_keywords[keyword] = true
end

---Whether text can be a Lua name, such as a table key without brackets.
---@param text string
---@return boolean
function M.is_identifier(text)
    return text:match("^[%a_][%w_]*$") ~= nil and not lua_keywords[text]
end

return M

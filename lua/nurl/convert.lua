local M = {}

---@class nurl.ConvertOpts
---@field indent? string indentation for each nesting level, defaults to 4 spaces

local DEFAULT_INDENT = "    "

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

local empty_dict_mt = getmetatable(vim.empty_dict())

---vim.inspect writes numbers with tostring, which keeps 14 significant digits
---and would change ids such as 123456789012345.
---@param value number
---@return string
local function lua_number(value)
    if value % 1 == 0 and math.abs(value) < 2 ^ 53 then
        return ("%d"):format(value)
    end
    for precision = 15, 17 do
        local text = ("%." .. precision .. "g"):format(value)
        if tonumber(text) == value then
            return text
        end
    end
    return ("%.17g"):format(value)
end

---@param value any a value decoded by vim.json.decode
---@param indent string
---@param depth integer
---@return string
local function to_lua(value, indent, depth)
    if value == vim.NIL then
        return "vim.NIL"
    elseif type(value) == "number" then
        return lua_number(value)
    elseif type(value) ~= "table" then
        return vim.inspect(value)
    elseif next(value) == nil then
        -- vim.json.encode writes a plain empty table as [].
        return getmetatable(value) == empty_dict_mt and "vim.empty_dict()"
            or "{}"
    end

    local fields = {}
    if vim.islist(value) then
        for _, item in ipairs(value) do
            table.insert(fields, to_lua(item, indent, depth + 1))
        end
    else
        local keys = vim.tbl_keys(value)
        table.sort(keys)
        for _, key in ipairs(keys) do
            local name = key
            if not key:match("^[%a_][%w_]*$") or lua_keywords[key] then
                name = "[" .. vim.inspect(key) .. "]"
            end
            table.insert(
                fields,
                name .. " = " .. to_lua(value[key], indent, depth + 1)
            )
        end
    end

    local inner = indent:rep(depth + 1)
    return "{\n"
        .. inner
        .. table.concat(fields, ",\n" .. inner)
        .. ",\n"
        .. indent:rep(depth)
        .. "}"
end

---Convert JSON text to a Lua table constructor with sorted keys. null becomes
---vim.NIL and an empty object vim.empty_dict(), so the table is encoded back
---to the same JSON.
---@param json string
---@param opts? nurl.ConvertOpts
---@return string
function M.json_to_lua(json, opts)
    local ok, value = pcall(vim.json.decode, json)
    if not ok then
        error("Invalid JSON: " .. value, 0)
    end
    return to_lua(value, opts and opts.indent or DEFAULT_INDENT, 0)
end

---Convert a Lua value, such as a table constructor, to formatted JSON with
---sorted keys. vim.NIL becomes null and vim.empty_dict() an empty object.
---@param lua string
---@param opts? nurl.ConvertOpts
---@return string
function M.lua_to_json(lua, opts)
    lua = vim.trim(lua):gsub(",$", "")

    -- Evaluate with access to globals such as vim, for vim.NIL.
    local env = setmetatable({}, { __index = _G })
    local chunk, err = load("return " .. lua, "=selection", "t", env)
    if not chunk then
        error("Invalid Lua table: " .. err, 0)
    end

    local ok, value = pcall(chunk)
    if not ok then
        error("Invalid Lua table: " .. tostring(value), 0)
    end

    local encoded, json = pcall(vim.json.encode, value, {
        indent = opts and opts.indent or DEFAULT_INDENT,
        sort_keys = true,
    })
    if not encoded then
        error("Cannot convert to JSON: " .. json, 0)
    end
    return json
end

---@return string
local function buffer_indent()
    if vim.bo.expandtab then
        return (" "):rep(vim.fn.shiftwidth())
    end

    return "\t"
end

---Replace the selected text, or the whole buffer without a range, with its
---conversion. A character-wise visual selection converts just the selected
---text, such as the JSON after `data = `.
---@param convert fun(text: string, opts: nurl.ConvertOpts): string
---@param params table user command params
function M.replace_region(convert, params)
    local start_row, start_col, end_row, end_col

    local from_charwise_selection = params.range > 0
        and vim.fn.visualmode() == "v"
        and params.line1 == vim.fn.line("'<")
        and params.line2 == vim.fn.line("'>")

    if from_charwise_selection then
        local region = vim.fn.getregionpos(
            vim.fn.getpos("'<"),
            vim.fn.getpos("'>"),
            { type = "v" }
        )
        local first, last = region[1][1], region[#region][2]
        start_row, start_col = first[2] - 1, first[3] - 1
        end_row = last[2] - 1
        local end_line =
            vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, true)[1]
        end_col = math.min(last[3], #end_line)
    else
        local line1 = params.range > 0 and params.line1 or 1
        local line2 = params.range > 0 and params.line2
            or vim.api.nvim_buf_line_count(0)
        start_row, start_col, end_row = line1 - 1, 0, line2 - 1
        end_col = #vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, true)[1]
    end

    local text = table.concat(
        vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {}),
        "\n"
    )

    -- Keep the whitespace and a trailing comma around the selected value.
    local leading, body, trailing = text:match("^(%s*)(.-)(,?%s*)$")
    if body == "" then
        error("Nothing to convert", 0)
    end

    -- Indent continuation lines like the line the selection starts on.
    local first_line =
        vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, true)[1]
    local base_indent = first_line:match("^%s*")

    local converted =
        vim.split(convert(body, { indent = buffer_indent() }), "\n")
    for i = 2, #converted do
        converted[i] = base_indent .. converted[i]
    end

    local replacement =
        vim.split(leading .. table.concat(converted, "\n") .. trailing, "\n")
    vim.api.nvim_buf_set_text(
        0,
        start_row,
        start_col,
        end_row,
        end_col,
        replacement
    )
end

return M

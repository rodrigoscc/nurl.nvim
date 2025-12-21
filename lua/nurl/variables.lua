local M = {}

---@class nurl.ExpandOpts
---@field lazy? boolean if true, do not expand functions wrapped by nurl.lazy()

---@param value any
function M.lazy(value)
    return setmetatable({}, {
        __nurl_lazy = value,
        __tojson = function()
            return "<LAZY>"
        end,
    })
end

function M.is_lazy(fn)
    local mt = getmetatable(fn)
    return mt and mt.__nurl_lazy ~= nil
end

local function resolve_lazy(fn)
    local mt = getmetatable(fn)
    if mt and mt.__nurl_lazy then
        return mt.__nurl_lazy
    end
    return fn
end

---@param tbl table
---@param opts? nurl.ExpandOpts
---@return table
function M.expand_table(tbl, opts)
    opts = opts or {}

    return vim.tbl_map(function(value)
        if M.is_lazy(value) and not opts.lazy then
            value = resolve_lazy(value)
        end

        if value == nil then
            return nil
        elseif type(value) == "table" and not M.is_lazy(value) then
            return M.expand_table(value, opts)
        elseif type(value) == "function" then
            return M.expand(value(), opts)
        end

        return value
    end, tbl)
end

---@param value any
---@param opts? nurl.ExpandOpts
function M.expand(value, opts)
    opts = opts or {}

    if M.is_lazy(value) and not opts.lazy then
        value = resolve_lazy(value)
    end

    if value == nil then
        return nil
    elseif type(value) == "table" and not M.is_lazy(value) then
        return M.expand_table(value, opts)
    elseif type(value) == "function" then
        return M.expand(value(), opts)
    end

    return value
end

M.LAZY_PLACEHOLDER = "<LAZY>"

---@return table
function M.stringify_lazy_table(tbl)
    return vim.tbl_map(function(value)
        if M.is_lazy(value) then
            return M.LAZY_PLACEHOLDER
        end

        if value == nil then
            return nil
        elseif type(value) == "table" then
            return M.stringify_lazy_table(value)
        elseif type(value) == "function" then
            return M.stringify_lazy(value())
        end

        return value
    end, tbl)
end

function M.stringify_lazy(value)
    if M.is_lazy(value) then
        return M.LAZY_PLACEHOLDER
    end

    if value == nil then
        return nil
    elseif type(value) == "table" then
        return M.stringify_lazy_table(value)
    elseif type(value) == "function" then
        return M.stringify_lazy(value())
    end

    return value
end

local function uri_encode_table(tbl)
    local encoded = {}

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            encoded[k] = uri_encode_table(v)
        elseif type(v) == "string" then
            encoded[k] = vim.uri_encode(vim.uri_decode(v))
        else
            encoded[k] = v
        end
    end

    return encoded
end

--- URI-Encodes a string using percentage escapes.
--- This decodes the value first so that already encoded values are not encoded twice.
---@param value any
---@return any encoded string
function M.uri_encode(value)
    if value == nil then
        return nil
    elseif type(value) == "table" then
        return uri_encode_table(value)
    elseif type(value) == "string" then
        return vim.uri_encode(vim.uri_decode(value))
    end

    return value
end

return M

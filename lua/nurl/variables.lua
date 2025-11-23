local M = {}

function M.expand_table(tbl)
    return vim.tbl_map(function(value)
        if value == nil then
            return nil
        elseif type(value) == "table" then
            return M.expand_table(value)
        elseif type(value) == "function" then
            return value()
        end

        return value
    end, tbl)
end

function M.expand(value)
    if value == nil then
        return nil
    elseif type(value) == "table" then
        return M.expand_table(value)
    elseif type(value) == "function" then
        return value()
    end

    return value
end

return M

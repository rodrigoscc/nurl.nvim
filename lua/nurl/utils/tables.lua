local M = {}

function M.collect_value(tbl, key, new_value)
    local new_value_is_list = vim.islist(new_value)
    local new_value_is_table = type(new_value) == "table"
        and not vim.islist(new_value)

    local old_value_is_list = vim.islist(tbl[key])
    local old_value_is_table = type(tbl[key]) == "table"
        and not vim.islist(tbl[key])

    if new_value_is_table then
        error("Deep table not allowed here")
    end
    if old_value_is_table then
        error("Deep table not allowed here")
    end

    local result = vim.deepcopy(tbl)

    if type(result[key]) == "nil" then
        result[key] = new_value
    elseif old_value_is_list then
        if new_value_is_list then
            vim.list_extend(result[key], new_value)
        else
            table.insert(result[key], new_value)
        end
    else
        if new_value_is_list then
            table.insert(new_value, 1, result[key])
            result[key] = new_value
        else
            local current = result[key]
            result[key] = { current, new_value }
        end
    end

    return result
end

function M.shallow_extend(tbl1, tbl2)
    local result = vim.deepcopy(tbl1)

    if tbl2 then
        for k, v in pairs(tbl2) do
            result = M.collect_value(result, k, v)
        end
    end

    return result
end

return M

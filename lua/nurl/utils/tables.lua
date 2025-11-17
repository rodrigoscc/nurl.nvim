local M = {}

function M.extend(list1, list2)
    for _, item in ipairs(list2) do
        table.insert(list1, item)
    end

    return list1
end

return M

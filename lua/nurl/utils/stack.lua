---@class nurl.Stack
---@field items any[]
---@field max_items integer
local Stack = {}

function Stack:new(max_items)
    local stack = setmetatable({ max_items = max_items, items = {} }, self)
    self.__index = self
    return stack
end

-- TODO: do i need to handle concurrency while pushing?
function Stack:push(item)
    if vim.deep_equal(self.items[#self.items], item) then
        -- Do not push if the same item is already at the tip
        return
    end

    table.insert(self.items, item)

    if #self.items >= self.max_items then
        local extra_items = #self.items - self.max_items

        self.items = vim.iter(self.items):skip(extra_items):totable()
    end
end

function Stack:get(idx)
    if idx >= 0 then
        return self.items[idx]
    else
        return self.items[#self.items + idx + 1]
    end
end

return Stack

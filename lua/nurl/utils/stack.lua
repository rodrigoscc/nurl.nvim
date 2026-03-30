---@class nurl.Stack
---@field items any[]
---@field max_items integer
---@field opts { key_fn?: fun(item) }
local Stack = {}

function Stack:new(max_items, opts)
    opts = opts or {}

    local stack =
        setmetatable({ max_items = max_items, items = {}, opts = opts }, self)
    self.__index = self
    return stack
end

-- TODO: do i need to handle concurrency while pushing?
function Stack:push(item)
    if #self.items > 0 then
        if self:_same(item, self.items[#self.items]) then
            -- Do not push if the same item is already at the tip
            return
        end
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

function Stack:_same(item1, item2)
    local key1
    local key2

    if self.opts.key_fn then
        key1 = self.opts.key_fn(item1)
        key2 = self.opts.key_fn(item2)
    else
        key1 = item1
        key2 = item2
    end

    return vim.deep_equal(key1, key2)
end

return Stack

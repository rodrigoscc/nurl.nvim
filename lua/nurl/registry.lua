---@class nurl.RegistryEntry
---@field handle nurl.RequestHandle
---@field buffers? table<nurl.BufferType, integer>
---@field win? integer
---@field _next? nurl.RegistryEntry
---@field _previous? nurl.RegistryEntry

---@class nurl.Registry
---@field private entries table<integer, nurl.RegistryEntry>
---@field private _head? nurl.RegistryEntry
---@field private _tail? nurl.RegistryEntry
local Registry = {}

function Registry:new()
    local o = { entries = {}, _head = nil, _tail = nil }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@param entry nurl.RegistryEntry
function Registry:push(entry)
    if self._head == nil then
        self._head = entry
    end

    if self._tail ~= nil then
        entry._previous = self._tail
        self._tail._next = entry
    end

    self._tail = entry

    self.entries[entry.handle.id] = entry
end

---@param id integer
function Registry:remove(id)
    local entry = self.entries[id]
    if not entry then
        return
    end

    self.entries[id] = nil

    if entry._previous ~= nil then
        entry._previous._next = entry._next
    end

    if entry._next ~= nil then
        entry._next._previous = entry._previous
    end

    if self._head.handle.id == id then
        self._head = entry._next
    end

    if self._tail.handle.id == id then
        self._tail = entry._previous
    end
end

function Registry:get(id)
    return self.entries[id]
end

function Registry:index(idx)
    if idx == 0 then
        return nil
    end

    local entry = nil

    local negative_index = idx < 0

    if negative_index then
        idx = idx * -1 -- Will use idx just as iteration counter

        entry = self._tail

        while idx > 1 and entry ~= nil do
            entry = entry._previous
            idx = idx - 1
        end
    else
        entry = self._head

        while idx > 1 and entry ~= nil do
            entry = entry._next
            idx = idx - 1
        end
    end

    return entry
end

return Registry:new()

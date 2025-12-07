---@class nurl.Override
---@field [1] string[]
---@field [2] any

---@param tbl table
---@param keys string[]
---@param value any
local function set_path(tbl, keys, value)
    for i = 1, #keys - 1 do
        local key = keys[i]

        if tbl[key] == nil then
            tbl[key] = {}
        end

        tbl = tbl[key]
    end

    tbl[keys[#keys]] = value
end

---@param tbl table
---@param overrides nurl.Override[]
return function(tbl, overrides)
    for _, override in ipairs(overrides) do
        local path, value = unpack(override)
        set_path(tbl, path, value)
    end
end

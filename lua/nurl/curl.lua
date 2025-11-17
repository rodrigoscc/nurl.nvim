---@class nurl.Curl
---@field args string[]
---@field result vim.SystemCompleted | nil
local Curl = { args = {}, result = nil }

function Curl:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Curl:run()
    local cmd = { "curl" }

    for _, k in ipairs(self.args) do
        table.insert(cmd, k)
    end

    local result = vim.system(cmd, { text = true }):wait()
    self.result = result
    return result
end

function Curl:string()
    local args = vim.iter(self.args)
        :map(function(arg)
            return vim.fn.shellescape(arg)
        end)
        :totable()
    return "curl " .. table.concat(args, " ")
end

return Curl

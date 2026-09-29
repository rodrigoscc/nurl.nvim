---@class nurl.Curl
---@field args string[]
---@field result? vim.SystemCompleted
local Curl = {}

function Curl:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@return string[]
function Curl:cmd()
    return vim.list_extend({ "curl" }, self.args)
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

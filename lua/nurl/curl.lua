---@class nurl.Curl
---@field args string[]
---@field result vim.SystemCompleted | nil
local Curl = { args = {}, result = nil }

function Curl:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@param on_exit fun(out: vim.SystemCompleted) | nil
function Curl:run(on_exit)
    local cmd = { "curl" }

    for _, k in ipairs(self.args) do
        table.insert(cmd, k)
    end

    if on_exit == nil then
        local result = vim.system(cmd, { text = true }):wait()
        self.result = result
        return result
    else
        vim.system(cmd, { text = true }, function(out)
            self.result = out
            on_exit(out)
        end)
    end
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

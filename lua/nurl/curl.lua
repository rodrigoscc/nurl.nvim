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

---@param on_exit fun(out: vim.SystemCompleted)
---@return vim.SystemObj
function Curl:run(on_exit)
    local cmd = { "curl" }

    for _, k in ipairs(self.args) do
        table.insert(cmd, k)
    end

    return vim.system(cmd, {}, function(out)
        self.result = out
        on_exit(out)
    end)
end

function Curl:string()
    local args = vim.iter(self.args)
        :map(function(arg)
            return vim.fn.shellescape(arg)
        end)
        :totable()
    return "curl " .. table.concat(args, " ")
end

---@param new_text string
---@param header_size integer bytes of the header blocks before the body
function Curl:replace_body(new_text, header_size)
    self.result.stdout = self.result.stdout:sub(1, header_size) .. new_text
end

return Curl

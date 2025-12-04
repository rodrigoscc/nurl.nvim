---@class nurl.Curl
---@field args string[]
---@field result? vim.SystemCompleted
---@field exec_datetime string
---@field pid? integer
local Curl = {}

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

    self.exec_datetime = tostring(os.date("%Y-%m-%dT%H:%M:%S")) -- local time
    if on_exit == nil then
        local result = vim.system(cmd):wait()
        self.result = result
        return result
    else
        local handle = vim.system(cmd, {}, function(out)
            self.result = out
            on_exit(out)
        end)

        self.pid = handle.pid
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

function Curl:replace_body(new_text)
    -- Assuming stdout contains CRLF
    local start_of_body = string.find(self.result.stdout, "\r\n\r\n")

    self.result.stdout = self.result.stdout:sub(1, start_of_body + 3)
        .. new_text
end

return Curl

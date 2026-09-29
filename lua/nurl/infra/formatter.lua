local M = {}

---@class nurl.ResponseFormatter
---@field cmd string[]
---@field available? fun(): boolean

---The formatter for a file type, if there is one and it can run.
---@param formatters table<string, nurl.ResponseFormatter>
---@param file_type string
---@return nurl.ResponseFormatter?
function M.find(formatters, file_type)
    local formatter = formatters[file_type]
    if
        formatter ~= nil
        and (formatter.available == nil or formatter.available())
    then
        return formatter
    end
end

---Format text through the formatter's command. Without on_done, waits for
---the command and returns its result.
---@param formatter nurl.ResponseFormatter
---@param text string
---@param on_done? fun(result: vim.SystemCompleted) called in a fast event context
---@return vim.SystemCompleted?
function M.run(formatter, text, on_done)
    local system = vim.system(formatter.cmd, { text = true, stdin = text }, on_done)

    if on_done == nil then
        return system:wait()
    end
end

return M

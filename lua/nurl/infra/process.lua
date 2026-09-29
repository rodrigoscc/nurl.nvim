local uv = vim.uv or vim.loop

local M = {}

---Start a process. on_exit runs in a fast event context, where most of the
---Neovim API is unavailable, so it should schedule any further work.
---@param cmd string[]
---@param on_exit fun(result: vim.SystemCompleted)
---@return vim.SystemObj
function M.run(cmd, on_exit)
    return vim.system(cmd, {}, on_exit)
end

---@param pid? integer
---@param signame? string the signal to send. Default: "sigterm"
function M.kill(pid, signame)
    if pid == nil then
        vim.notify("Could not kill nil pid", vim.log.levels.ERROR)
        return
    end

    local code, msg = uv.kill(pid, signame or "sigterm")
    if code ~= 0 then
        vim.notify(
            ("Could not kill pid %s: %s"):format(pid, msg),
            vim.log.levels.ERROR
        )
    end
end

return M

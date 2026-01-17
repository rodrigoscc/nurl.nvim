local uv = vim.uv or vim.loop

return function(pid, signame)
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

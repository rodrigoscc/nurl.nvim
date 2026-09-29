local M = {}

---The curl command, and its output once it ran.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    local curl = handle.curl
    if curl == nil then
        return
    end

    -- Arguments can span lines, such as a body with newlines.
    local raw_lines = vim.split(curl:string(), "\n")

    if curl.result then
        if curl.result.stdout then
            local stdout_lines = vim.split(curl.result.stdout, "\n")
            vim.list_extend(raw_lines, stdout_lines)
        end
        if curl.result.stderr then
            local stderr_lines = vim.split(curl.result.stderr, "\n")
            vim.list_extend(raw_lines, stderr_lines)
        end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, raw_lines)
end

return M

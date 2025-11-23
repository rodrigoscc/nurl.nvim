local uv = vim.uv or vim.loop

local M = {}

function M.exists(path)
    local stat = uv.fs_stat(path)
    return stat ~= nil
end

function M.read(path)
    local fd = uv.fs_open(path, "r", 438)
    if fd == nil then
        error("Could not open file: " .. path)
    end

    local stat = uv.fs_fstat(fd)
    if stat == nil then
        error("Could not open file: " .. path)
    end

    local data = uv.fs_read(fd, stat.size)
    uv.fs_close(fd)

    if data == nil then
        error("Could not open file: " .. path)
    end

    return data
end

function M.write(path, contents)
    vim.uv.fs_mkdir(vim.fs.dirname(path), 493)

    local fd, err = uv.fs_open(path, "w+", 438)
    if fd == nil then
        error("Could not open file: " .. path .. err)
    end

    uv.fs_write(fd, contents, -1)
    uv.fs_close(fd)
end

return M

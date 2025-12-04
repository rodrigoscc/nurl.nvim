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
    uv.fs_mkdir(vim.fs.dirname(path), 493)

    local fd, err = uv.fs_open(path, "w+", 438)
    if fd == nil then
        error(("Could not open file %s: %s"):format(path, err))
    end

    uv.fs_write(fd, contents, -1)
    uv.fs_close(fd)
end

function M.unique_path(dir, name, extension)
    uv.fs_mkdir(dir, 493)
    local full_path = vim.fs.joinpath(dir, "XXXXXXXXX")
    local unique_dir = uv.fs_mkdtemp(full_path)
    return vim.fs.joinpath(unique_dir, name .. "." .. extension)
end

function M.delete_dir(dir)
    for file in vim.fs.dir(dir) do
        local status, err, err_name = uv.fs_unlink(vim.fs.joinpath(dir, file))
        if not status and err_name ~= "ENOENT" then
            return status, err
        end
    end

    local status, err, err_name = uv.fs_rmdir(dir)
    if not status and err_name ~= "ENOENT" then
        return status, err
    end

    return true, nil, nil
end

return M

local uv = vim.uv or vim.loop

local M = {}

function M.mkdir(path)
    local parents = {}

    for parent in vim.fs.parents(path) do
        table.insert(parents, 1, parent)
    end

    for _, parent in ipairs(parents) do
        local success, err, err_name = uv.fs_mkdir(parent, tonumber("755", 8))
        if not success and err_name ~= "EEXIST" then
            error(("Could not mkdir %s: %s"):format(parent, err))
        end
    end

    local success, err, err_name = uv.fs_mkdir(path, tonumber("755", 8))
    if not success and err_name ~= "EEXIST" then
        error(("Could not mkdir %s: %s"):format(path, err))
    end
end

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
    M.mkdir(vim.fs.dirname(path))

    local fd, err = uv.fs_open(path, "w+", 438)
    if fd == nil then
        error(("Could not open file %s: %s"):format(path, err))
    end

    uv.fs_write(fd, contents, -1)
    uv.fs_close(fd)
end

function M.unique_path(dir, name, extension)
    M.mkdir(dir)
    local unique_dir = uv.fs_mkdtemp(vim.fs.joinpath(dir, "XXXXXXXXX"))
    return vim.fs.joinpath(unique_dir, name .. "." .. extension)
end

function M.delete_dir(dir)
    vim.fs.rm(dir, { recursive = true, force = true })
end

return M

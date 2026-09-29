local config = require("nurl.config")
local fs = require("nurl.infra.fs")

---The active environment of each directory, kept across sessions.
local M = {}

---@return table<string, string>
local function read()
    if not fs.exists(config.active_environments_file) then
        return {}
    end

    return vim.json.decode(fs.read(config.active_environments_file))
end

---@param dir string
---@return string?
function M.get(dir)
    return read()[dir]
end

---@param dir string
---@param name string
function M.set(dir, name)
    local active = read()
    active[dir] = name
    fs.write(config.active_environments_file, vim.json.encode(active))
end

return M

local config = require("nurl.config")
local fs = require("nurl.infra.fs")

---Which directories may run their Lua files: requests and environments are
---code, and a project just cloned should not run any without asking.
local M = {}

---@alias nurl.TrustState "trusted" | "denied"

---Directories answered "Later" in this session, not asked again until the
---next one.
---@type table<string, true>
local skipped = {}

---Directories already reported as not trusted in this session.
---@type table<string, true>
local reported = {}

---@param dir string
---@return string
local function normalize(dir)
    return vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
end

---@return table<string, nurl.TrustState>
local function read()
    if not fs.exists(config.trust_file) then
        return {}
    end

    return vim.json.decode(fs.read(config.trust_file))
end

---@param dir string
---@param state? nurl.TrustState nil forgets the directory
local function write(dir, state)
    local states = read()
    states[normalize(dir)] = state
    fs.write(config.trust_file, vim.json.encode(states))
end

---@param dir string
function M.trust(dir)
    skipped[normalize(dir)] = nil
    reported[normalize(dir)] = nil
    write(dir, "trusted")
end

---Forget the answer for a directory, so that it is asked again.
---@param dir string
function M.forget(dir)
    skipped[normalize(dir)] = nil
    reported[normalize(dir)] = nil
    write(dir, nil)
end

---@param dir string
local function ask(dir)
    -- One line without commas: some confirm UIs show the lines after the
    -- first one as buttons, split on commas.
    local choice = vim.fn.confirm(
        ("nurl: run the Lua files in %s? They can do anything a plugin can.\n"):format(
            dir
        ),
        "&Trust\n&Later\n&Never",
        2
    )

    if choice == 1 then
        write(dir, "trusted")
        return true
    elseif choice == 3 then
        write(dir, "denied")
    else
        skipped[dir] = true
    end

    return false
end

---Whether the Lua files in a directory may run, asking the first time.
---@param dir string
---@return boolean
function M.allows(dir)
    if not config.trust then
        return true
    end

    dir = normalize(dir)

    local state = read()[dir]
    local allowed = state == "trusted"
        or (state == nil and not skipped[dir] and ask(dir))

    if not allowed and not reported[dir] then
        reported[dir] = true
        vim.notify(
            ("nurl: skipping the Lua files in %s, which is not trusted. Run :Nurl trust to trust it."):format(
                dir
            ),
            vim.log.levels.WARN
        )
    end

    return allowed
end

return M

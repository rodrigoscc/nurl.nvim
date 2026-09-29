local config = require("nurl.config")
local fs = require("nurl.infra.fs")
local active = require("nurl.env.active")
local env_file = require("nurl.env.file")
local strings = require("nurl.utils.strings")

local uv = vim.uv or vim.loop

local M = {}

---@class nurl.EnvOperation
---@field op "set" | "unset"
---@field env string
---@field name string
---@field value? any

---The environments of the project in a directory, loaded from its
---environments file on first use.
---@class nurl.EnvProject
---@field dir string the directory, which keeps its own active environment
---@field path string the environments file
---@field envs table<string, table<string, any>>
---@field active_name? string
---@field private file? nurl.EnvFile the file being edited by set and unset
---@field private queue nurl.EnvOperation[]
---@field private saving boolean
local Project = {}
Project.__index = Project

---Variables are written as `name = value` fields, which need a Lua
---identifier as the name.
---@param name string
local function check_variable_name(name)
    if not strings.is_identifier(name) then
        error(
            ("Invalid variable name %q: it must be a Lua identifier"):format(
                name
            )
        )
    end
end

---@type table<string, nurl.EnvProject> projects by directory
local projects = {}

---@param dir string
---@return nurl.EnvProject
local function load(dir)
    local path = vim.fn.fnamemodify(
        vim.fs.joinpath(dir, config.dir, config.environments_file),
        ":p"
    )
    local project = setmetatable({
        dir = dir,
        path = path,
        envs = {},
        active_name = active.get(dir),
        queue = {},
        saving = false,
    }, Project)

    if not fs.exists(path) then
        return project
    end

    local ok, envs = pcall(dofile, path)
    if not ok or type(envs) ~= "table" then
        vim.notify(
            ("Could not load environments file %s: %s"):format(
                path,
                ok and "it must return a table" or envs
            ),
            vim.log.levels.ERROR
        )
        return project
    end
    project.envs = envs

    local file, err = env_file.parse(path)
    if file then
        project.file = file
    else
        vim.notify(
            "Could not parse environments file: " .. err,
            vim.log.levels.ERROR
        )
    end

    return project
end

---The project of the current directory.
---@return nurl.EnvProject
function M.current()
    local dir = uv.cwd()
    ---@cast dir string
    projects[dir] = projects[dir] or load(dir)
    return projects[dir]
end

---Forget the projects using an environments file, so that they load it
---again when next used.
---@param path string
function M.reload(path)
    path = vim.fn.fnamemodify(path, ":p")
    for dir, project in pairs(projects) do
        if project.path == path then
            projects[dir] = nil
        end
    end
end

---Reload a project's environments when its file is written.
function M.setup()
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup(
            "nurl.environment_reload_group",
            { clear = true }
        ),
        -- A pattern without a slash matches the file name only.
        pattern = config.environments_file,
        callback = function(args)
            M.reload(args.file)
        end,
    })
end

---@return string[]
function Project:names()
    local names = vim.tbl_keys(self.envs)
    table.sort(names)
    return names
end

---An environment by name, or the active one.
---@param name? string
---@return table<string, any>?
function Project:env(name)
    if name ~= nil then
        return self.envs[name]
    end

    if self.active_name == nil then
        return nil
    end

    local env = self.envs[self.active_name]
    if env == nil then
        error(("Active env does not exist: %s"):format(self.active_name))
    end

    return env
end

---@param name string
function Project:activate(name)
    if self.envs[name] == nil then
        error(
            string.format("Could not activate environment %s, not found", name)
        )
    end

    self.active_name = name
    active.set(self.dir, name)
end

---@return fun(next: fun(), input: nurl.RequestInput, cancel: fun())?
function Project:pre_hook()
    local env = self:env()
    return env and env.pre_hook
end

---@return fun(out: nurl.RequestOut)?
function Project:post_hook()
    local env = self:env()
    return env and env.post_hook
end

---The environment an operation applies to: the named one or the active one.
---@param name? string
---@return string name, table<string, any> env
function Project:_target(name)
    name = name or self.active_name
    if name == nil then
        error("No active env")
    end

    local env = self.envs[name]
    if env == nil then
        error(('Env "%s" not found'):format(name))
    end

    if self.file == nil then
        error("No environments file to write to: " .. self.path)
    end

    return name, env
end

---Set a variable, in memory and in the environments file.
---@param env_name? string Default: the active environment
---@param name string
---@param value string | number | boolean | nil
function Project:set(env_name, name, value)
    local value_type = type(value)
    if
        value_type ~= "string"
        and value_type ~= "number"
        and value_type ~= "boolean"
        and value_type ~= "nil"
    then
        error("value type " .. value_type .. " not supported")
    end
    check_variable_name(name)

    local target, env = self:_target(env_name)
    env[name] = value
    self:_write({ op = "set", env = target, name = name, value = value })
end

---Remove a variable, in memory and from the environments file.
---@param env_name? string Default: the active environment
---@param name string
function Project:unset(env_name, name)
    local target, env = self:_target(env_name)
    env[name] = nil
    self:_write({ op = "unset", env = target, name = name })
end

---@param value string | number | boolean | nil
---@return string
local function lua_literal(value)
    if type(value) == "string" then
        -- Escapes quotes, backslashes and control characters.
        return vim.inspect(value)
    end

    return tostring(value)
end

---Apply edits to the file one at a time: saving formats the whole file, so
---an edit applied while saving would be lost.
---@param op nurl.EnvOperation
function Project:_write(op)
    table.insert(self.queue, op)
    self:_flush()
end

function Project:_flush()
    if self.saving or #self.queue == 0 then
        return
    end

    local op = table.remove(self.queue, 1)
    local file = self.file
    ---@cast file nurl.EnvFile

    if op.op == "set" then
        local found = file:set_environment_variable(
            op.env,
            op.name,
            lua_literal(op.value)
        )
        if not found then
            -- Environments are only found when written as `name = { ... }`
            -- in the table the file returns.
            vim.notify(
                ("Could not find environment %s in %s to save %s; the change won't persist"):format(
                    op.env,
                    self.path,
                    op.name
                ),
                vim.log.levels.WARN
            )
        end
    else
        file:unset_environment_variable(op.env, op.name)
    end

    self.saving = true
    file:save(function()
        self.saving = false
        self:_flush()
    end)
end

return M

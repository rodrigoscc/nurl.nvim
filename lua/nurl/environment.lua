-- have a function that returns a function that evaluates a variable in the env
-- should use active env by default, but have a way to use static env in an argument
-- defaults should just be implemented with `or 'default'`
-- should env files also be lua files? could be useful
-- env hooks? confirm requests only on production! (if not GET ...)

local config = require("nurl.config")
local fs = require("nurl.fs")
local FileParser = require("nurl.file_parsing").FileParser
local uv = vim.uv or vim.loop

---@class nurl.Environment
local Environment =
    { name = "default", variables = {}, pre_hook = nil, post_hook = nil }

function Environment:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

local M = {}

---@type string | nil
M.active_environment = nil

M.Environment = Environment

---@type table<string, nurl.Environment>
M.environments = {}

function M.activate(env_name)
    for name in pairs(M.environments) do
        if name == env_name then
            M.active_environment = name

            local active_environments = {}
            if fs.exists(config.environments_file) then
                local content = fs.read(config.active_environments_file)
                active_environments = vim.json.decode(content)
            end

            active_environments[uv.cwd()] = env_name

            fs.write(
                config.active_environments_file,
                vim.json.encode(active_environments)
            )
            return
        end
    end

    error("could not activate environment, not found")
end

function M.get_active()
    if M.active_environment == nil then
        return nil
    end

    return M.environments[M.active_environment]
end

function M.var(variable_name)
    return function()
        local active_env = M.get_active()
        if active_env == nil then
            error("could not resolve variable: " .. variable_name)
        end

        return active_env.variables[variable_name]
    end
end

function M.set(variable_name, value)
    local active_env = M.get_active()
    if active_env == nil then
        error("no active env")
        return
    end

    active_env.variables[variable_name] = value

    local environments_path =
        vim.fs.joinpath(config.dir, config.environments_file)

    local parser = FileParser:new()
    local file = parser:parse(environments_path)

    local new_text
    if type(value) == "string" then
        new_text = string.format([["%s"]], value)
    elseif type(value) == "number" or type(value) == "boolean" then
        new_text = tostring(value)
    elseif value == nil then
        new_text = "nil"
    else
        error("value type " .. type(value) .. " not supported")
    end

    file:replace_environment_variable_value(
        M.active_environment,
        variable_name,
        new_text
    )
    file:save()
end

function M.load()
    local environments_path =
        vim.fs.joinpath(config.dir, config.environments_file)

    if not fs.exists(environments_path) then
        return
    end

    local environments = fs.read_lua_file(environments_path)

    M.environments = environments

    if not fs.exists(config.active_environments_file) then
        return
    end

    local content = fs.read(config.active_environments_file)
    local active_environments = vim.json.decode(content)

    M.active_environment = active_environments[uv.cwd()]
end

return M

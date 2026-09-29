local variables = require("nurl.core.variables")
local project = require("nurl.env.project")

---Variables of the active environment of the current project, available as
---Nurl.env. Each function takes an optional environment name to use instead
---of the active one.
---@class nurl.env
local M = {}

---A function resolving a variable when the request is sent, to use in
---request tables.
---@param variable_name string
---@param use_env? string
---@return fun(): any
function M.var(variable_name, use_env)
    return function()
        local env = project.current():env(use_env)
        if env == nil then
            return nil
        end

        return env[variable_name]
    end
end

---The value of a variable, for use inside functions.
---@param variable_name string
---@param use_env? string
---@return any
function M.get(variable_name, use_env)
    local env = project.current():env(use_env)
    if env == nil then
        return nil
    end

    return variables.expand(env[variable_name])
end

---Set a variable, also saving it to the environments file.
---@param variable_name string
---@param value string | number | boolean | nil
---@param use_env? string
function M.set(variable_name, value, use_env)
    project.current():set(use_env, variable_name, value)
end

---Remove a variable, also from the environments file.
---@param variable_name string
---@param use_env? string
function M.unset(variable_name, use_env)
    project.current():unset(use_env, variable_name)
end

---Make an environment the active one of the current directory.
---@param env_name string
function M.activate(env_name)
    project.current():activate(env_name)
end

return M

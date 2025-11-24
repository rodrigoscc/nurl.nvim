-- have a function that returns a function that evaluates a variable in the env
-- should use active env by default, but have a way to use static env in an argument
-- defaults should just be implemented with `or 'default'`
-- should env files also be lua files? could be useful
-- env hooks? confirm requests only on production! (if not GET ...)

local config = require("nurl.config")
local fs = require("nurl.fs")
local FileParser = require("nurl.file_parsing").FileParser
local uv = vim.uv or vim.loop
local variables = require("nurl.variables")

local M = {}

---@type string | nil
M.project_active_env = nil

---@type table<string, table<string, any>>
M.project_envs = {}

function M.activate(env_name)
    for name in pairs(M.project_envs) do
        if name == env_name then
            M.project_active_env = name

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
    if M.project_active_env == nil then
        return nil
    end

    return M.project_envs[M.project_active_env]
end

function M.get_pre_hook()
    if M.project_active_env == nil then
        return nil
    end

    return M.project_envs[M.project_active_env].pre_hook
end

function M.get_post_hook()
    if M.project_active_env == nil then
        return nil
    end

    return M.project_envs[M.project_active_env].post_hook
end

function M.var(variable_name, use_env)
    return function()
        local env

        if use_env == nil then
            env = M.get_active()
        else
            env = M.project_envs[use_env]
        end

        if env == nil then
            error(
                "could not resolve variable since no environment is active: "
                    .. variable_name
            )
        end

        return variables.expand(env[variable_name])
    end
end

function M.set(variable_name, value)
    local active_env = M.get_active()
    if active_env == nil then
        error("no active env")
        return
    end

    active_env[variable_name] = value

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

    file:set_environment_variable(M.project_active_env, variable_name, new_text)
    file:save()
end

function M.load()
    local environments_path =
        vim.fs.joinpath(config.dir, config.environments_file)

    if not fs.exists(environments_path) then
        return
    end

    local environments = dofile(environments_path)

    M.project_envs = environments

    if not fs.exists(config.active_environments_file) then
        return
    end

    local content = fs.read(config.active_environments_file)
    local active_environments = vim.json.decode(content)

    M.project_active_env = active_environments[uv.cwd()]
end

local reload_group_id = vim.api.nvim_create_augroup(
    "nurl.environment_reload_group",
    { clear = true }
)

function M.setup_reload_autocmd()
    local environments_path =
        vim.fs.joinpath(config.dir, config.environments_file)

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = reload_group_id,
        pattern = vim.fs.abspath(environments_path),
        callback = function()
            M.load()
        end,
    })
end

return M

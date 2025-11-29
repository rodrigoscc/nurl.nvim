-- have a function that returns a function that evaluates a variable in the env
-- should use active env by default, but have a way to use static env in an argument
-- defaults should just be implemented with `or 'default'`
-- should env files also be lua files? could be useful
-- env hooks? confirm requests only on production! (if not GET ...)

local config = require("nurl.config")
local fs = require("nurl.data.fs")
local file_parsing = require("nurl.utils.file_parsing")
local variables = require("nurl.variables")
local uv = vim.uv or vim.loop

local M = {}

---@type string | nil
M.project_active_env = nil

---@type table<string, table<string, any>>
M.project_envs = {}

---@class nurl.EnvOperation
---@field op "set" | "unset"
---@field name string
---@field value? any

---@type nurl.EnvOperation[]
local operations_queue = {}

M.project_env_file = nil

local function safe_coroutine_resume(my_coroutine)
    if coroutine.status(my_coroutine) == "dead" then
        vim.notify(
            "Environment worker is dead, cannot process operations",
            vim.log.levels.ERROR
        )
        -- clear queue since it won't be processed
        operations_queue = {}
        return
    end

    local ok, err = coroutine.resume(my_coroutine)
    if not ok then
        vim.notify(
            ("Environment worker crashed: %s"):format(err),
            vim.log.levels.ERROR
        )
        -- clear queue since it won't be processed
        operations_queue = {}
    end
end

M.file_worker_coroutine = coroutine.create(function()
    while true do
        if M.project_env_file == nil then
            error("Environment file wasn't loaded. Stopping worker...")
        end

        while #operations_queue == 0 do
            coroutine.yield()
        end

        ---@type nurl.EnvOperation
        local op = table.remove(operations_queue, 1)

        if op.op == "set" then
            local new_text
            if type(op.value) == "string" then
                new_text = string.format([["%s"]], op.value)
            elseif
                type(op.value) == "number" or type(op.value) == "boolean"
            then
                new_text = tostring(op.value)
            elseif op.value == nil then
                new_text = "nil"
            else
                error("value type " .. type(op.value) .. " not supported")
            end

            M.project_env_file:set_environment_variable(
                M.project_active_env,
                op.name,
                new_text
            )
        elseif op.op == "unset" then
            M.project_env_file:unset_environment_variable(
                M.project_active_env,
                op.name
            )
        end

        local saved = false

        M.project_env_file:save(function()
            saved = true
            vim.schedule(function()
                -- running inside vim.schedule just in case
                safe_coroutine_resume(M.file_worker_coroutine)
            end)
        end)

        while not saved do
            coroutine.yield()
        end
    end
end)

function M.activate(env_name)
    for name in pairs(M.project_envs) do
        if name == env_name then
            M.project_active_env = name

            local active_environments = {}
            if fs.exists(config.active_environments_file) then
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
            return nil
        end

        return env[variable_name]
    end
end

function M.set(variable_name, value)
    local active_env = M.get_active()
    if active_env == nil then
        error("no active env")
        return
    end

    active_env[variable_name] = value

    table.insert(
        operations_queue,
        { op = "set", name = variable_name, value = value }
    )

    safe_coroutine_resume(M.file_worker_coroutine)
end

function M.unset(variable_name)
    local active_env = M.get_active()
    if active_env == nil then
        error("no active env")
        return
    end

    active_env[variable_name] = nil

    table.insert(operations_queue, { op = "unset", name = variable_name })

    safe_coroutine_resume(M.file_worker_coroutine)
end

function M.get(variable_name, use_env)
    local env

    if use_env == nil then
        env = M.get_active()
    else
        env = M.project_envs[use_env]
    end

    if env == nil then
        return nil
    end

    return variables.expand(env[variable_name])
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

    local file, err = file_parsing.parse(environments_path)
    if not file then
        vim.notify(
            "Could not parse environments file: " .. err,
            vim.log.levels.ERROR
        )
        return
    end

    M.project_env_file = file
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

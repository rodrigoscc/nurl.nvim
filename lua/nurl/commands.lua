local parsing = require("nurl.commands_parsing")

local SUBCOMMANDS = {
    "jump",
    "history",
    "resend",
    "env",
    "env_file",
    "yank",
    "json_to_lua",
    "lua_to_json",
}

local M = {}

---@enum nurl.TargetEnum
local Target = {
    project = "project",
    file = "file",
    cursor = "cursor",
}

local function parse_target(arg)
    if arg == nil or arg == "" then
        return Target.project
    elseif arg == "." then
        return Target.cursor
    else
        return Target.file
    end
end

-- The rest of the plugin is only loaded once a command runs, not on setup.

---@return nurl.app.client
local function client()
    return require("nurl.app.client")
end

---@return nurl.app.targets
local function targets()
    return require("nurl.app.targets")
end

---@param action fun(item: nurl.RequestItem)
---@param overrides? nurl.Override[]
---@return fun(item: nurl.RequestItem)
local function with_overrides(action, overrides)
    return function(item)
        local request = require("nurl.override")(item.request, overrides or {})
        action(vim.tbl_extend("force", item, { request = request }))
    end
end

---Run an action on the requests of a target: pick one of the project's, one
---of a file's unless it has only one, or the one at the cursor.
---@param arg? string the target: nothing for the project, "." for the cursor, or a file
---@param title string
---@param action? fun(item: nurl.RequestItem) Default: jump to the request
local function run_on_target(arg, title, action)
    local target = parse_target(arg)

    if target == Target.project then
        require("nurl.pickers").pick(title, targets().project(), action)
    elseif target == Target.file then
        ---@cast arg string
        targets().choose(title, targets().file(arg), action)
    else
        local item = targets().cursor()
        if item == nil then
            vim.notify("No request found at cursor", vim.log.levels.ERROR)
        elseif action == nil then
            vim.notify("Cannot jump at cursor", vim.log.levels.WARN)
        else
            action(item)
        end
    end
end

---@param item nurl.RequestItem
local function send_item(item)
    -- A request at the cursor in a response window is sent again there.
    client().send(item.request, { display = item.win and { win = item.win } or true })
end

---@param item nurl.RequestItem
local function yank_item(item)
    client().yank(item.request)
end

---Send a request of a target, showing its response.
---@param arg? string
---@param overrides? nurl.Override[]
function M.send(arg, overrides)
    run_on_target(arg, "Nurl: send", with_overrides(send_item, overrides))
end

---Copy the curl command of a request of a target.
---@param arg? string
---@param overrides? nurl.Override[]
function M.yank(arg, overrides)
    run_on_target(arg, "Nurl: yank", with_overrides(yank_item, overrides))
end

---Jump to where a request of a target is defined.
---@param arg? string
function M.jump(arg)
    run_on_target(arg, "Nurl: jump")
end

---Pick a recent request and send it again.
---@param overrides? nurl.Override[]
function M.pick_resend(overrides)
    local items = vim.tbl_map(function(recent)
        return { request = recent.request }
    end, client().recent.items)

    if #items == 0 then
        vim.notify("No recent requests to resend", vim.log.levels.WARN)
        return
    end

    require("nurl.pickers").pick(
        "Nurl: resend",
        items,
        with_overrides(function(item)
            client().send(item.request, { display = true })
        end, overrides)
    )
end

function M.pick_env()
    local environments = require("nurl.environments")
    vim.ui.select(
        vim.tbl_keys(environments.project_envs),
        { prompt = "Nurl: activate environment" },
        function(choice)
            if choice ~= nil then
                M.activate_env(choice)
            end
        end
    )
end

---@param env string to activate
function M.activate_env(env)
    require("nurl.environments").activate(env)
    vim.cmd.redrawstatus() -- in case the user is showing the active env in statusline
end

function M.open_environments_file()
    local config = require("nurl.config")
    vim.cmd.edit(vim.fs.joinpath(config.dir, config.environments_file))
end

function M.pick_history()
    require("nurl.ui.history_explorer").open(client())
end

local function resend_subcommand(arg, overrides)
    if arg == nil or arg == "" then
        M.pick_resend(overrides)
    else
        local index = tonumber(arg)
        if index then
            client().resend(index, overrides)
        else
            vim.notify("Invalid resend index: " .. arg, vim.log.levels.ERROR)
        end
    end
end

local function env_subcommand(arg)
    if arg == nil then
        M.pick_env()
    else
        M.activate_env(arg)
    end
end

---@param name "json_to_lua" | "lua_to_json"
local function conversion_subcommand(name)
    return function(_, _, params)
        local convert = require("nurl.convert")
        local ok, err = pcall(convert.replace_region, convert[name], params)
        if not ok then
            vim.notify(err, vim.log.levels.ERROR)
        end
    end
end

---@type table<string, fun(arg?: string, overrides: nurl.Override[], params: table)>
M.subcommand_handlers = {
    jump = M.jump,
    history = M.pick_history,
    resend = resend_subcommand,
    env = env_subcommand,
    env_file = M.open_environments_file,
    yank = M.yank,
    json_to_lua = conversion_subcommand("json_to_lua"),
    lua_to_json = conversion_subcommand("lua_to_json"),
}

function M.run(params)
    local command = parsing.parse_command(params.args)
    if not command then
        error("Invalid Nurl command")
    end

    if command.subcommand then
        local handler = M.subcommand_handlers[command.subcommand]
        handler(command.arg, command.overrides, params)
    else
        M.send(command.arg, command.overrides)
    end
end

function M.complete(_, cmdline)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    local num_args = #args

    if cmdline:match("%s$") then
        num_args = num_args + 1
    end

    if num_args <= 2 then
        return SUBCOMMANDS
    end

    local subcommand = args[2]
    if subcommand == "env" then
        local environments = require("nurl.environments")
        return vim.tbl_keys(environments.project_envs)
    end

    return {}
end

function M.setup()
    vim.api.nvim_create_user_command("Nurl", M.run, {
        nargs = "*",
        range = true,
        desc = "Nurl: HTTP client",
        complete = M.complete,
    })
end

return M

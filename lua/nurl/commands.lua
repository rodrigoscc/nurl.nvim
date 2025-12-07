local parsing = require("nurl.commands_parsing")

local SUBCOMMANDS = { "jump", "history", "resend", "env", "env_file", "yank" }

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

local function default_command(arg, overrides)
    local nurl = require("nurl")
    local target = parse_target(arg)

    if target == Target.project then
        nurl.send_project_request(overrides)
    elseif target == Target.cursor then
        nurl.send_request_at_cursor(overrides)
    elseif target == Target.file then
        nurl.send_file_request(arg, overrides)
    end
end

local function jump_subcommand(arg)
    local nurl = require("nurl")
    local target = parse_target(arg)

    if target == Target.project then
        nurl.jump_to_project_request()
    elseif target == Target.cursor then
        vim.notify("Cannot jump at cursor", vim.log.levels.WARN)
    elseif target == Target.file then
        nurl.jump_to_file_request(arg)
    end
end

local function yank_subcommand(arg, overrides)
    local nurl = require("nurl")
    local target = parse_target(arg)

    if target == Target.project then
        nurl.yank_project_request(overrides)
    elseif target == Target.cursor then
        nurl.yank_curl_at_cursor(overrides)
    elseif target == Target.file then
        nurl.yank_file_request(arg, overrides)
    end
end

local function resend_subcommand(arg, overrides)
    local nurl = require("nurl")

    if arg == nil or arg == "" then
        nurl.pick_resend(overrides)
    else
        local index = tonumber(arg)
        if index then
            nurl.resend_last_request(index, overrides)
        else
            vim.notify("Invalid resend index: " .. arg, vim.log.levels.ERROR)
        end
    end
end

local function env_subcommand(arg)
    local nurl = require("nurl")
    local env_name = arg

    if env_name == nil then
        nurl.pick_env()
    else
        nurl.activate_env(env_name)
    end
end

local function end_file_subcommand()
    require("nurl").open_environments_file()
end

local function history_subcommand()
    require("nurl").pick_history()
end

---@type table<string, fun(args: string[])>
M.subcommand_handlers = {
    jump = jump_subcommand,
    history = history_subcommand,
    resend = resend_subcommand,
    env = env_subcommand,
    env_file = end_file_subcommand,
    yank = yank_subcommand,
}

function M.run(params)
    local command = parsing.parse_command(params.args)
    if not command then
        error("Invalid Nurl command")
    end

    if command.subcommand then
        local handler = M.subcommand_handlers[command.subcommand]
        handler(command.arg, command.overrides)
    else
        default_command(command.arg, command.overrides)
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
        desc = "Nurl: HTTP client",
        complete = M.complete,
    })
end

return M

local M = {}

local SUBCOMMANDS = { "jump", "history", "resend", "env", "env_file", "yank" }

local function is_subcommand(arg)
    return vim.tbl_contains(SUBCOMMANDS, arg)
end

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

local function default_command(args)
    local nurl = require("nurl")
    local target = parse_target(args[1])

    if target == Target.project then
        nurl.send_project_request()
    elseif target == Target.cursor then
        nurl.send_request_at_cursor()
    elseif target == Target.file then
        nurl.send_file_request(args[1])
    end
end

local function jump_subcommand(args)
    local nurl = require("nurl")
    local target = parse_target(args[1])

    if target == Target.project then
        nurl.jump_to_project_request()
    elseif target == Target.cursor then
        vim.notify("Cannot jump at cursor", vim.log.levels.WARN)
    elseif target == Target.file then
        nurl.jump_to_file_request(args[1])
    end
end

local function yank_subcommand(args)
    local nurl = require("nurl")
    local target = parse_target(args[1])

    if target == Target.project then
        nurl.yank_project_request()
    elseif target == Target.cursor then
        nurl.yank_curl_at_cursor()
    elseif target == Target.file then
        nurl.yank_file_request(args[1])
    end
end

local function resend_subcommand(args)
    local nurl = require("nurl")
    local arg = args[1]

    if arg == nil or arg == "" then
        nurl.pick_resend()
    else
        local index = tonumber(arg)
        if index then
            nurl.resend_last_request(index)
        else
            vim.notify("Invalid resend index: " .. arg, vim.log.levels.ERROR)
        end
    end
end

local function env_subcommand(args)
    local nurl = require("nurl")
    local env_name = args[1]

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
    require("nurl").open_history()
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
    local args = vim.split(params.args, "%s+", { trimempty = true })
    local first_arg = args[1]

    if is_subcommand(first_arg) then
        local handler = M.subcommand_handlers[first_arg]
        handler(vim.list_slice(args, 2))
    else
        default_command(args)
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

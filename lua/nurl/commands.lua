local M = {}

---@type table<string, fun(args: string[])>
M.commands = {
    send_at_cursor = function()
        require("nurl").send_request_at_cursor()
    end,
    send = function()
        require("nurl").send_project_request()
    end,
    send_from_buffer = function()
        require("nurl").send_buffer_request()
    end,
    jump = function()
        require("nurl").jump_to_project_request()
    end,
    history = function()
        require("nurl").open_history()
    end,
    env = function(args)
        require("nurl").activate_env(args[1])
    end,
    env_file = function()
        require("nurl").open_environments_file()
    end,
    yank_at_cursor = function()
        require("nurl").yank_curl_at_cursor()
    end,
    resend = function(args)
        local index = args[1] and tonumber(args[1]) or nil
        require("nurl").resend_last_request(index)
    end,
}

---@param arg_lead string
---@return string[]
function M.complete(arg_lead)
    local candidates = vim.tbl_keys(M.commands)
    table.sort(candidates)

    if arg_lead == "" then
        return candidates
    end

    return vim.tbl_filter(function(cmd)
        return vim.startswith(cmd, arg_lead)
    end, candidates)
end

function M.run(params)
    local args = vim.split(params.args, "%s+", { trimempty = true })
    local cmd = args[1]

    if not cmd or cmd == "" then
        vim.ui.select(
            vim.tbl_keys(M.commands),
            { prompt = "Nurl" },
            function(choice)
                if choice then
                    M.commands[choice]({})
                end
            end
        )
        return
    end

    local fn = M.commands[cmd]
    if not fn then
        vim.notify("Unknown command: " .. cmd, vim.log.levels.ERROR)
        return
    end

    fn(vim.list_slice(args, 2))
end

function M.setup()
    vim.api.nvim_create_user_command("Nurl", M.run, {
        nargs = "?",
        desc = "Nurl: HTTP client",
        complete = function(arg_lead, cmdline)
            local args = vim.split(cmdline, "%s+", { trimempty = true })
            if #args <= 1 or (#args == 2 and not cmdline:match("%s$")) then
                return M.complete(arg_lead)
            end
            return {}
        end,
    })
end

return M

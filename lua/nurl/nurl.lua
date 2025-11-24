local requests = require("nurl.requests")
local responses = require("nurl.responses")
local config = require("nurl.config")
local winbar = require("nurl.winbar")
local projects = require("nurl.projects")
local environments = require("nurl.environments")
local activate = require("nurl.environments").activate
local ResponseWindow = require("nurl.response_window")

local M = {}

_G.Nurl = M

M.winbar = winbar

---@type nurl.Request | nil
M.last_request = nil
---@type integer | nil
M.last_request_win = nil

---@class nurl.RequestOpts
---@field win? integer | nil
---@field on_response? fun(response: nurl.Response | nil, curl: nurl.Curl) | nil

---@param request nurl.SuperRequest | nurl.Request
---@param opts? nurl.RequestOpts | nil
function M.send(request, opts)
    opts = opts or {}

    local response_window

    local win = opts.win

    local function next_function()
        local internal_request = requests.expand(request)

        M.last_request = internal_request

        local curl = requests.build_curl(internal_request)

        local should_prepare_response_ui = opts.on_response == nil
        if should_prepare_response_ui then
            response_window = ResponseWindow:new({
                win = win,
                request = internal_request,
                curl = curl,
            })
            win = response_window:open()
            M.last_request_win = win
        end

        local function default_on_response(response, curl)
            response_window:update(response, curl)
        end

        curl:run(function(system_completed)
            local stdout = vim.split(system_completed.stdout, "\n")
            local stderr = vim.split(system_completed.stderr, "\n")

            local response = nil
            if system_completed.code == 0 then
                response = responses.parse(stdout, stderr)
            end

            vim.schedule(function()
                if internal_request.post_hook ~= nil then
                    local status, result = pcall(
                        internal_request.post_hook,
                        internal_request,
                        response
                    )

                    if not status then
                        vim.notify(
                            "Request post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                local env_post_hook = environments.get_post_hook()
                if env_post_hook ~= nil then
                    local status, result =
                        pcall(env_post_hook, internal_request, response)

                    if not status then
                        vim.notify(
                            "Environment post hook failed: " .. result,
                            vim.log.levels.ERROR
                        )
                    end
                end

                if opts.on_response then
                    opts.on_response(response, curl)
                else
                    default_on_response(response, curl)
                end
            end)
        end)
    end

    local function env_next_function()
        if request.pre_hook ~= nil then
            request.pre_hook(next_function, request)
        else
            next_function()
        end
    end

    local env_pre_hook = environments.get_pre_hook()
    if env_pre_hook == nil then
        env_next_function()
    else
        env_pre_hook(env_next_function, request)
    end
end

function M.resend_last_request()
    M.send(M.last_request, { win = M.last_request_win })
end

function M.send_buffer_request()
    local buffer_requests = dofile(vim.fn.expand("%"))

    local items = vim.iter(ipairs(buffer_requests))
        :map(function(i, request)
            local expanded = requests.expand(request)

            local item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = request,
                score = 1,
                preview = {
                    text = vim.json.encode(
                        expanded.data
                            or expanded.data_urlencode
                            or expanded.form
                    ),
                    ft = "json",
                },
            }

            return item
        end)
        :totable()

    Snacks.picker.pick("requests", {
        title = "Nurl: run",
        items = items,
        preview = "preview",
        format = "text",
        formatters = {
            text = {
                ft = "http",
            },
        },
        confirm = function(picker, item)
            picker:close()
            M.send(item.request)
        end,
    })
end

function M.send_project_request()
    local project_requests = projects.requests()

    local snacks_items = vim.iter(ipairs(project_requests))
        :map(function(i, item)
            local expanded = requests.expand(item.request)

            local preview_json = ""
            if expanded.data then
                preview_json = vim.json.encode(expanded.data)
            elseif expanded.data_urlencode then
                preview_json = vim.json.encode(expanded.data_urlencode)
            elseif expanded.form then
                preview_json = vim.json.encode(expanded.form)
            end

            local snacks_item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = item.request,
                score = 1,
                preview = {
                    text = preview_json,
                    ft = "json",
                },
            }

            return snacks_item
        end)
        :totable()

    Snacks.picker.pick("requests", {
        title = "Nurl: run",
        items = snacks_items,
        preview = "preview",
        format = "text",
        formatters = {
            text = {
                ft = "http",
            },
        },
        confirm = function(picker, item)
            picker:close()
            M.send(item.request)
        end,
    })
end

function M.jump_to_project_request()
    local project_requests = projects.requests()

    local snacks_items = vim.iter(ipairs(project_requests))
        :map(function(i, item)
            local expanded = requests.expand(item.request)

            local snacks_item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = item,
                file = item.file,
                score = 1,
                pos = { item.start_row, item.start_col },
            }

            return snacks_item
        end)
        :totable()

    local file = require("snacks.picker.format").file
    local text = require("snacks.picker.format").text

    Snacks.picker.pick("requests", {
        title = "Nurl: jump",
        items = snacks_items,
        format = function(item, picker)
            return vim.list_extend(file(item, picker), text(item, picker))
        end,
    })
end

function M.send_request_at_cursor()
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local project_requests = projects.requests()

    for _, request in ipairs(project_requests) do
        local request_contains_cursor = (
            request.start_row <= cursor_row
            and request.end_row >= cursor_row
            and (cursor_row ~= request.end_row or cursor_col < request.end_col)
            and (
                cursor_row ~= request.start_row
                or cursor_col >= request.start_col
            )
        )

        if request_contains_cursor then
            M.send(request.request)
            return
        end
    end
end

function M.yank_curl_at_cursor()
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local project_requests = projects.requests()

    for _, request in ipairs(project_requests) do
        local request_contains_cursor = (
            request.start_row <= cursor_row
            and request.end_row >= cursor_row
            and (cursor_row ~= request.end_row or cursor_col < request.end_col)
            and (
                cursor_row ~= request.start_row
                or cursor_col > request.start_col
            )
        )

        if request_contains_cursor then
            local internal_request = requests.expand(request.request)

            local curl = requests.build_curl(internal_request)

            vim.fn.setreg("+", curl:string())
            vim.notify("Yanked curl command to clipboard")

            return
        end
    end
end

function M.activate_env()
    vim.ui.select(
        vim.tbl_keys(environments.project_envs),
        { prompt = "Activate environment" },
        function(choice)
            if choice ~= nil then
                activate(choice)
                vim.cmd.redrawstatus() -- in case the user is showing the active env in statusline
            end
        end
    )
end

function M.open_environments_file()
    local environments_file =
        vim.fs.joinpath(config.dir, config.environments_file)
    vim.cmd.edit(environments_file)
end

function M.get_active_env()
    return environments.project_active_env
end

require("nurl.config").setup()
require("nurl.highlights").setup_highlights()

require("nurl.environments").load()
require("nurl.environments").setup_reload_autocmd()

vim.keymap.set("n", "gh", function()
    Nurl.jump_to_project_request()
end)
vim.keymap.set("n", "gH", function()
    Nurl.send_project_request()
end)
vim.keymap.set("n", "gL", function()
    Nurl.resend_last_request()
end)
vim.keymap.set("n", "R", function()
    Nurl.send_request_at_cursor()
end)

return M

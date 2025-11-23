local requests = require("nurl.requests")
local responses = require("nurl.responses")
local load_environments = require("nurl.environment").load
local config = require("nurl.config")
local buffers = require("nurl.buffers")
local ElapsedTimeFloating = require("nurl.elapsed_time")
local winbar = require("nurl.winbar")
local projects = require("nurl.projects")
local environments = require("nurl.environment").environments
local activate = require("nurl.environment").activate

local M = {}

_G.Nurl = M

M.winbar = winbar

---@param request nurl.SuperRequest | nurl.Request
function M.send(request)
    local internal_request = requests.expand(request)

    local curl = requests.build_curl(internal_request)

    local function next_function()
        local response_buffers = buffers.create(internal_request, nil, curl)

        assert(
            #config.buffers > 0,
            "Must configure at least one response buffer"
        )
        local first_buffer_type = config.buffers[1][1]

        local win = vim.api.nvim_open_win(
            response_buffers[first_buffer_type],
            false,
            config.win_config
        )

        vim.wo[win].winbar = M.winbar.winbar()

        for _, bufnr in pairs(response_buffers) do
            vim.api.nvim_create_autocmd("BufWinEnter", {
                once = true,
                callback = function()
                    vim.wo[win].winbar = M.winbar.winbar()
                end,
                buffer = bufnr,
            })
        end

        local elapsed_time = ElapsedTimeFloating:new(win)
        elapsed_time:start()

        -- Stop timer if parent window is closed
        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            pattern = tostring(win),
            callback = function()
                elapsed_time:stop()
            end,
        })

        curl:run(function(system_completed)
            elapsed_time:stop()

            local stdout = vim.split(system_completed.stdout, "\n")
            local stderr = vim.split(system_completed.stderr, "\n")

            local response = nil
            if system_completed.code == 0 then
                response = responses.parse(stdout, stderr)
            end

            vim.schedule(function()
                buffers.update(
                    internal_request,
                    response,
                    curl,
                    response_buffers
                )

                if
                    system_completed.code ~= 0
                    and response_buffers[buffers.Buffer.Raw]
                then
                    vim.api.nvim_win_set_buf(
                        win,
                        response_buffers[buffers.Buffer.Raw]
                    )
                end

                if internal_request.post_hook ~= nil then
                    internal_request.post_hook(internal_request, response)
                end
            end)
        end)
    end

    if internal_request.pre_hook ~= nil then
        internal_request.pre_hook(next_function)
    else
        next_function()
    end
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
                or cursor_col > request.start_col
            )
        )

        if request_contains_cursor then
            M.send(request.request)
            return
        end
    end
end

function M.activate_env()
    vim.ui.select(
        vim.tbl_keys(environments),
        { prompt = "Activate environment" },
        function(choice)
            activate(choice)
        end
    )
end

-- vim.schedule(function()
--     load_environments()
-- end)

-- local env = require("nurl.environment").var
-- local activate = require("nurl.environment").activate
load_environments()

require("nurl.config").setup()
require("nurl.highlights").setup_highlights()
-- activate("default")
-- local response = M.run({
--     url = "https://jsonplaceholder.typicode.com/posts",
--     method = "POST",
--     headers = { ["Content-Type"] = "application/json" },
--     data = {
--         title = env("title"),
--     },
-- })
-- print(vim.inspect(response))

vim.keymap.set("n", "gh", function()
    Nurl.jump_to_project_request()
end)
vim.keymap.set("n", "gH", function()
    Nurl.send_project_request()
end)
vim.keymap.set("n", "R", function()
    Nurl.send_request_at_cursor()
end)

return M

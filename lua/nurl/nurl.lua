local requests = require("nurl.requests")
local responses = require("nurl.responses")
local load_environments = require("nurl.environment").load
local config = require("nurl.config")
local buffers = require("nurl.buffers")
local ElapsedTimeFloating = require("nurl.elapsed_time")
local winbar = require("nurl.winbar")

local M = {}

_G.Nurl = M

M.winbar = winbar

---@param request nurl.SuperRequest | nurl.Request
function M.run(request)
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

function M.run_buffer_request()
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
            M.run(item.request)
        end,
    })
end

function M.run_project_request()
    local lua_files = vim.fs.find(function(name)
        return vim.endswith(name, ".lua") and name ~= config.environments_file
    end, { type = "file", limit = math.huge, path = config.dir })

    local cwd_requests = {}

    for _, file in ipairs(lua_files) do
        local file_requests = dofile(file)
        for _, request in ipairs(file_requests) do
            table.insert(cwd_requests, request)
        end
    end

    local items = vim.iter(ipairs(cwd_requests))
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
            M.run(item.request)
        end,
    })
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

vim.keymap.set("n", "gH", function()
    Nurl.run_project_request()
end)

return M

local requests = require("nurl.requests")
local responses = require("nurl.responses")
local load_environments = require("nurl.environment").load
local config = require("nurl.config")
local buffers = require("nurl.buffers")

local M = {}

_G.Nurl = M

---@param request nurl.SuperRequest | nurl.Request
function M.run(request)
    local internal_request = requests.expand(request)

    local curl = requests.build_curl(internal_request)

    local system_completed = curl:run()
    if system_completed.code ~= 0 then
        return
    end

    local stdout = vim.split(system_completed.stdout, "\n")
    local stderr = vim.split(system_completed.stderr, "\n")

    local response = responses.parse(stdout, stderr)

    buffers.open(internal_request, response, curl)

    return response
end

function M.run_from_buffer()
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
            vim.schedule(function()
                M.run(item.request)
            end)
        end,
    })
end

function M.run_from_cwd()
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
            vim.schedule(function()
                M.run(item.request)
            end)
        end,
    })
end

-- vim.schedule(function()
--     load_environments()
-- end)

-- local env = require("nurl.environment").var
-- local activate = require("nurl.environment").activate
load_environments()
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

return M

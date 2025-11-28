local config = require("nurl.config")
local file_parsing = require("nurl.file_parsing")

local M = {}

---@class nurl.ProjectRequestItem
---@field request nurl.Request
---@field file string
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@return nurl.ProjectRequestItem[]
function M.requests()
    local lua_files = vim.fs.find(function(name)
        return vim.endswith(name, ".lua") and name ~= config.environments_file
    end, { type = "file", limit = math.huge, path = config.dir })

    ---@type nurl.ProjectRequestItem[]
    local project_requests = {}

    for _, file_path in ipairs(lua_files) do
        local file, err = file_parsing.parse(file_path)
        if file then
            local request_ranges = file:list_requests_ranges()

            local status, file_requests = pcall(dofile, file_path)
            if not status then
                vim.notify(
                    ("Skipping file %s: %s"):format(file_path, file_requests),
                    vim.log.levels.WARN
                )
            else
                for i, request in ipairs(file_requests) do
                    local request_range = request_ranges[i]
                    local start_row, start_col, end_row, end_col =
                        unpack(request_range)

                    table.insert(project_requests, {
                        file = file_path,
                        request = request,
                        start_row = start_row + 1,
                        start_col = start_col,
                        end_row = end_row + 1,
                        end_col = end_col,
                    })
                end
            end
        else
            vim.notify("Skipping file: " .. err, vim.log.levels.WARN)
        end
    end

    return project_requests
end

return M

local config = require("nurl.config")
local FileParser = require("nurl.file_parsing").FileParser

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
        local file_parser = FileParser:new()
        local file = file_parser:parse(file_path)

        local request_ranges = file:list_requests_ranges()

        local file_requests = dofile(file_path)

        for i, request in ipairs(file_requests) do
            local request_range = request_ranges[i]
            local start_row, start_col, end_row, end_col = unpack(request_range)

            table.insert(project_requests, {
                file = file_path,
                request = request,
                start_row = start_row + 1, -- treesitter ranges starts at 0
                start_col = start_col,
                end_row = end_row + 1, -- treesitter ranges starts at 0
                end_col = end_col,
            })
        end
    end

    return project_requests
end

return M

local config = require("nurl.config")
local file_parsing = require("nurl.utils.file_parsing")

local M = {}

---A request defined in a project file. The position is missing when the
---file does not return its requests as a literal table, since they cannot
---be matched with the table's fields then.
---@class nurl.ProjectRequestItem: nurl.RequestItem
---@field request nurl.SuperRequest
---@field file string

---@param file_path string
---@return nurl.ProjectRequestItem[]
function M.file_requests(file_path)
    local file, err = file_parsing.parse(file_path)
    if not file then
        vim.notify("Skipping file: " .. err, vim.log.levels.WARN)
        return {}
    end

    local status, file_requests = pcall(dofile, file_path)
    if not status then
        vim.notify(
            ("Skipping file %s: %s"):format(file_path, file_requests),
            vim.log.levels.WARN
        )
        return {}
    end

    -- Requests get the positions of the returned table's fields, which only
    -- match when the file returns a literal table of them. A file building
    -- its requests in code, such as in a loop, returns requests that do not
    -- line up with the fields, so they get no position rather than wrong ones.
    local ranges = file:list_requests_ranges()
    local positioned = #ranges == #file_requests

    ---@type nurl.ProjectRequestItem[]
    local items = {}

    for i, request in ipairs(file_requests) do
        local item = { file = file_path, request = request }

        if positioned then
            local start_row, start_col, end_row, end_col = unpack(ranges[i])
            item.start_row = start_row + 1
            item.start_col = start_col
            item.end_row = end_row + 1
            item.end_col = end_col
        end

        table.insert(items, item)
    end

    return items
end

---@return nurl.ProjectRequestItem[]
function M.requests()
    local lua_files = vim.fs.find(function(name)
        return vim.endswith(name, ".lua") and name ~= config.environments_file
    end, { type = "file", limit = math.huge, path = config.dir })

    local items = {}
    for _, file_path in ipairs(lua_files) do
        vim.list_extend(items, M.file_requests(file_path))
    end
    return items
end

---@param item nurl.ProjectRequestItem
function M.jump_to(item)
    vim.cmd("edit " .. item.file)
    if item.start_row then
        vim.api.nvim_win_set_cursor(0, { item.start_row, item.start_col + 1 })
    end
end

return M

local config = require("nurl.config")
local fs = require("nurl.infra.fs")
local trust = require("nurl.trust")

local M = {}

local QUERY_REQUESTS = [[
(return_statement (expression_list (table_constructor (field) @request)))
]]

---@type vim.treesitter.Query?
local requests_query

---The ranges of the fields of the table a file returns, which are its
---requests when it returns a literal table of them.
---@param contents string
---@return integer[][] ranges array of {start_row, start_col, end_row, end_col}
local function request_ranges(contents)
    requests_query = requests_query
        or vim.treesitter.query.parse("lua", QUERY_REQUESTS)

    local root = vim.treesitter.get_string_parser(contents, "lua"):parse()[1]:root()

    local ranges = {}
    for _, match in requests_query:iter_matches(root, contents, 0, -1) do
        for id, nodes in pairs(match) do
            if requests_query.captures[id] == "request" then
                for _, node in ipairs(nodes) do
                    local start_row, start_col, end_row, end_col = node:range()
                    table.insert(ranges, { start_row, start_col, end_row, end_col })
                end
            end
        end
    end

    return ranges
end

---A request defined in a project file. The position is missing when the
---file does not return its requests as a literal table, since they cannot
---be matched with the table's fields then.
---@class nurl.ProjectRequestItem: nurl.RequestItem
---@field request nurl.SuperRequest
---@field file string

---Run the contents of a request file and position the requests it returns.
---@param contents string
---@param file_path string
---@return nurl.ProjectRequestItem[]
local function requests_of(contents, file_path)
    local status, file_requests = pcall(function()
        return assert(load(contents, "@" .. file_path))()
    end)
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
    local ranges = request_ranges(contents)
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

---@param file_path string
---@return nurl.ProjectRequestItem[]
function M.file_requests(file_path)
    local read, contents = pcall(fs.read, file_path)
    if not read then
        vim.notify("Skipping file: " .. contents, vim.log.levels.WARN)
        return {}
    end

    if not trust.allows(vim.fs.dirname(vim.fn.fnamemodify(file_path, ":p"))) then
        return {}
    end

    return requests_of(contents, file_path)
end

---The requests of a buffer, from its lines rather than its file, so that
---changes not written yet are included. A buffer without a file holds what
---was typed in it, so it is not asked to be trusted.
---@param buf integer
---@return nurl.ProjectRequestItem[]
function M.buffer_requests(buf)
    local file_path = vim.api.nvim_buf_get_name(buf)

    if file_path ~= "" and not trust.allows(vim.fs.dirname(file_path)) then
        return {}
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return requests_of(table.concat(lines, "\n"), file_path)
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
    vim.cmd("edit " .. vim.fn.fnameescape(item.file))
    if item.start_row then
        vim.api.nvim_win_set_cursor(0, { item.start_row, item.start_col })
    end
end

return M

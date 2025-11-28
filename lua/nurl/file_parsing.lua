local fs = require("nurl.fs")

local M = {}

local QUERY_ENV_VAR_VALUE = [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor
                (field
                  name: (identifier) @variable_name (#eq? @variable_name "%s")
                  value: (_) @variable_value))))))
]]

local QUERY_ENV_VAR_FIELD = [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor
                (field
                  name: (identifier) @variable_name (#eq? @variable_name "%s")
                  value: (_) @variable_value) @field)))))
]]

local QUERY_LAST_ENV_VAR = [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor
                 (field) @last_field .)))))
]]

local QUERY_ENV_TABLE = [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor) @env_table))))
]]

local QUERY_REQUESTS = [[
(return_statement (expression_list (table_constructor (field) @request)))
]]

---@type table<string, vim.treesitter.Query>
local query_cache = {}

---@param query_string string
---@return vim.treesitter.Query
local function get_query(query_string)
    if not query_cache[query_string] then
        query_cache[query_string] =
            vim.treesitter.query.parse("lua", query_string)
    end
    return query_cache[query_string]
end

---@param query vim.treesitter.Query
---@param root TSNode
---@param source string
---@param capture_name string
---@return TSNode|nil, string|nil
local function find_capture(query, root, source, capture_name)
    for _, match in query:iter_matches(root, source, 0, -1) do
        for id, nodes in pairs(match) do
            if query.captures[id] == capture_name then
                local node = nodes[1]
                local text = vim.treesitter.get_node_text(node, source)
                return node, text
            end
        end
    end
    return nil, nil
end

---@param query vim.treesitter.Query
---@param root TSNode
---@param source string
---@param capture_name string
---@return {node: TSNode, text: string}[]
local function find_all_captures(query, root, source, capture_name)
    local results = {}
    for _, match in query:iter_matches(root, source, 0, -1) do
        for id, nodes in pairs(match) do
            if query.captures[id] == capture_name then
                for _, node in ipairs(nodes) do
                    local text = vim.treesitter.get_node_text(node, source)
                    table.insert(results, { node = node, text = text })
                end
            end
        end
    end
    return results
end

---@class nurl.File
---@field contents string
---@field path string
---@field private _tree TSTree
local File = {}
File.__index = File

---@param path string
---@param contents string
---@param tree TSTree
---@return nurl.File
function File:new(path, contents, tree)
    return setmetatable({
        path = path,
        contents = contents,
        _tree = tree,
    }, self)
end

function File:_reparse()
    local parser = vim.treesitter.get_string_parser(self.contents, "lua")
    self._tree = parser:parse()[1]
end

---@return TSNode
function File:_root()
    return self._tree:root()
end

---@param text string
function File:append_line(text)
    self.contents = self.contents .. "\n" .. text
    self:_reparse()
end

---@param i number
---@param new_text string
function File:insert(i, new_text)
    self.contents = self.contents:sub(1, i)
        .. new_text
        .. self.contents:sub(i + 1)
    self:_reparse()
end

---@param i number
---@param j number
---@param new_text string
function File:replace(i, j, new_text)
    self.contents = self.contents:sub(1, i - 1)
        .. new_text
        .. self.contents:sub(j + 1)
    self:_reparse()
end

---@param i number
---@param j number
function File:remove(i, j)
    self.contents = self.contents:sub(1, i - 1) .. self.contents:sub(j + 1)
    self:_reparse()
end

---@param environment string
---@param variable string
---@return TSNode | nil, string | nil
function File:find_environment_variable_value_node(environment, variable)
    local query_string =
        string.format(QUERY_ENV_VAR_VALUE, environment, variable)
    local query = get_query(query_string)
    return find_capture(query, self:_root(), self.contents, "variable_value")
end

---@param environment string
---@param variable string
---@return TSNode | nil, string | nil
function File:find_environment_variable_node(environment, variable)
    local query_string =
        string.format(QUERY_ENV_VAR_FIELD, environment, variable)
    local query = get_query(query_string)
    return find_capture(query, self:_root(), self.contents, "field")
end

---@param environment string
---@return TSNode | nil, string | nil
function File:find_last_environment_variable_node(environment)
    local query_string = string.format(QUERY_LAST_ENV_VAR, environment)
    local query = get_query(query_string)
    return find_capture(query, self:_root(), self.contents, "last_field")
end

---@param environment string
---@return TSNode | nil, string | nil
function File:find_environment_table_node(environment)
    local query_string = string.format(QUERY_ENV_TABLE, environment)
    local query = get_query(query_string)
    return find_capture(query, self:_root(), self.contents, "env_table")
end

---@return integer[][] ranges array of {start_row, start_col, end_row, end_col}
function File:list_requests_ranges()
    local query = get_query(QUERY_REQUESTS)
    local captures =
        find_all_captures(query, self:_root(), self.contents, "request")

    local ranges = {}
    for _, capture in ipairs(captures) do
        local start_row, start_col, end_row, end_col = capture.node:range()
        table.insert(ranges, { start_row, start_col, end_row, end_col })
    end
    return ranges
end

---@param node TSNode
---@param new_text string
function File:replace_node(node, new_text)
    local _, _, start_bytes, _, _, end_bytes = node:range(true)
    self:replace(start_bytes, end_bytes, new_text)
end

---@param node TSNode
function File:remove_node(node)
    local _, _, start_bytes, _, _, end_bytes = node:range(true)

    if self.contents:sub(end_bytes + 1, end_bytes + 1) == "," then
        end_bytes = end_bytes + 1
    end
    self:remove(start_bytes, end_bytes)
end

---@param node TSNode
---@param new_text string
function File:insert_after_node(node, new_text)
    local _, _, _, _, _, end_bytes = node:range(true)

    if self.contents:sub(end_bytes + 1, end_bytes + 1) == "," then
        end_bytes = end_bytes + 1
    else
        new_text = "," .. new_text
    end

    self:insert(end_bytes, new_text)
end

---@param environment string
---@param variable string
---@param new_text string
function File:set_environment_variable(environment, variable, new_text)
    local value_node =
        self:find_environment_variable_value_node(environment, variable)

    if value_node ~= nil then
        self:replace_node(value_node, new_text)
        return
    end

    local last_variable_node =
        self:find_last_environment_variable_node(environment)
    if last_variable_node then
        local formatted = string.format("%s = %s", variable, new_text)
        self:insert_after_node(last_variable_node, formatted)
        return
    end

    -- Environment table is empty
    local env_table_node = self:find_environment_table_node(environment)
    if env_table_node then
        local formatted = string.format("{ %s = %s }", variable, new_text)
        self:replace_node(env_table_node, formatted)
        return
    end
end

---@param environment string
---@param variable string
function File:unset_environment_variable(environment, variable)
    local node = self:find_environment_variable_node(environment, variable)
    if node ~= nil then
        self:remove_node(node)
    end
end

---@param on_save? fun(success: boolean)
function File:save(on_save)
    if vim.fn.executable("stylua") == 1 then
        vim.system(
            { "stylua", "-" },
            { text = true, stdin = self.contents },
            function(out)
                if out.code ~= 0 then
                    vim.notify(
                        string.format(
                            "Failed formatting %s: %s",
                            self.path,
                            out.stderr
                        ),
                        vim.log.levels.WARN
                    )
                else
                    self.contents = out.stdout
                    self:_reparse()
                end

                local status, err = pcall(fs.write, self.path, self.contents)
                if not status then
                    vim.notify(
                        string.format(
                            "Failed writing file %s: %s",
                            self.path,
                            err
                        ),
                        vim.log.levels.WARN
                    )
                end

                if on_save then
                    on_save(status)
                end
            end
        )
    else
        vim.schedule(function()
            local status, err = pcall(fs.write, self.path, self.contents)

            if not status then
                vim.notify(
                    string.format("Failed writing file %s: %s", self.path, err),
                    vim.log.levels.WARN
                )
            end

            if on_save then
                on_save(status)
            end
        end)
    end
end

---@param path string
---@return nurl.File | nil, string | nil
function M.parse(path)
    local contents = fs.read(path)
    if not contents then
        return nil, "Failed to read file: " .. path
    end

    local parser = vim.treesitter.get_string_parser(contents, "lua")
    local tree = parser:parse()[1]

    return File:new(path, contents, tree), nil
end

M.File = File

return M

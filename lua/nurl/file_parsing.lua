local fs = require("nurl.fs")
local M = {}

---@class nurl.File
local File = {
    contents = "",
    path = "",
    ---@type vim.treesitter.LanguageTree
    tree = nil,
}

function File:new(o)
    o = o or {}

    assert(o.tree, "tree cannot be nil")

    o = setmetatable(o, self)
    self.__index = self
    return o
end

--- Append line to file
---@param text string
function File:append_line(text)
    self.contents = self.contents .. "\n" .. text
end

--- Insert text in position
---@param i number
---@param new_text string
function File:insert(i, new_text)
    self.contents = self.contents:sub(1, i) .. new_text .. self.contents:sub(i)
end

--- Replace some text with other text
---@param i number
---@param j number
---@param new_text string
function File:replace(i, j, new_text)
    self.contents = self.contents:sub(1, i) .. new_text .. self.contents:sub(j)
end

--- Remove some text in a range
---@param i number
---@param j number
function File:remove(i, j)
    self.contents = self.contents:sub(1, i) .. self.contents:sub(j)
end

function File:find_environment_variable_value_node(environment, variable)
    local query = vim.treesitter.query.parse(
        "lua",
        string.format(
            [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor
                 (field
                   name: (identifier) @f (#eq? @f "variables")
                   value: (table_constructor
                            (field
                              name: (identifier) @variable_name (#eq? @variable_name "%s")
                              value: (_) @variable_value))))))))
    ]],
            environment,
            variable
        )
    )

    for pattern, match in
        query:iter_matches(self.tree:root(), self.contents, 0, -1)
    do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            for _, node in ipairs(nodes) do
                if name == "variable_value" then
                    local text =
                        vim.treesitter.get_node_text(node, self.contents)
                    return node, text
                end
            end
        end
    end
end

function File:find_environment_variable_node(environment, variable)
    local query = vim.treesitter.query.parse(
        "lua",
        string.format(
            [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "%s")
        value: (table_constructor
                 (field
                   name: (identifier) @f (#eq? @f "variables")
                   value: (table_constructor
                            (field
                              name: (identifier) @variable_name (#eq? @variable_name "%s")
                              value: (_) @variable_value) @field)))))))
    ]],
            environment,
            variable
        )
    )

    for _, match in query:iter_matches(self.tree:root(), self.contents, 0, -1) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            for _, node in ipairs(nodes) do
                if name == "field" then
                    local text =
                        vim.treesitter.get_node_text(node, self.contents)
                    return node, text
                end
            end
        end
    end
end

function File:list_requests_ranges()
    local query = vim.treesitter.query.parse(
        "lua",
        [[
(return_statement (expression_list (table_constructor (field) @request)))
    ]]
    )

    local ranges = {}

    for _, match in query:iter_matches(self.tree:root(), self.contents, 0, -1) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            for _, node in ipairs(nodes) do
                if name == "request" then
                    local row, col, end_row, end_col = node:range()
                    table.insert(ranges, { row, col, end_row, end_col })
                end
            end
        end
    end

    return ranges
end

function File:find_index_at_position(row, col)
    local query = vim.treesitter.query.parse(
        "lua",
        [[
(return_statement (expression_list (table_constructor (field) @item)))
    ]]
    )

    local index = 1

    for _, match in query:iter_matches(self.tree:root(), self.contents, 0, -1) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            for _, node in ipairs(nodes) do
                if vim.treesitter.node_contains(node, { row, col }) then
                    return index
                end

                index = index + 1
            end
        end
    end

    return nil
end

function File:replace_node(node, new_text)
    local _, _, start_bytes, _, _, end_bytes = node:range(true)
    self:replace(start_bytes, end_bytes + 1, new_text)
end

function File:remove_node(node)
    local _, _, start_bytes, _, _, end_bytes = node:range(true)
    if self.contents:sub(end_bytes + 1, end_bytes + 1) == "," then
        end_bytes = end_bytes + 1
    end
    self:remove(start_bytes, end_bytes + 1)
end

function File:replace_environment_variable_value(
    environment,
    variable,
    new_text
)
    local node =
        self:find_environment_variable_value_node(environment, variable)
    self:replace_node(node, new_text)
end

function File:remove_environment_variable(environment, variable)
    local node = self:find_environment_variable_node(environment, variable)
    self:remove_node(node)
end

function File:save()
    fs.write(self.path, self.contents)
end

---@class nurl.FileParser
local FileParser = {}

function FileParser:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function FileParser:parse(path)
    local file_contents = fs.read(path)

    local parser = vim.treesitter.get_string_parser(file_contents, "lua")
    local tree = parser:parse()[1]

    return File:new({ path = path, tree = tree, contents = file_contents })
end

-- local p = FileParser:new()
-- local f = p:parse(".scratch/scratch.20251109212244.lua")

-- f:replace_environment_variable_value("default", "session_id", [["dani"]])
-- f:remove_environment_variable("default", "session_id")

-- f:save()

M.FileParser = FileParser

return M

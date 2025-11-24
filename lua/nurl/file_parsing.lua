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
    self.contents = self.contents:sub(1, i)
        .. new_text
        .. self.contents:sub(i + 1)
end

--- Replace some text with other text
---@param i number
---@param j number
---@param new_text string
function File:replace(i, j, new_text)
    self.contents = self.contents:sub(1, i - 1)
        .. new_text
        .. self.contents:sub(j + 1)
end

--- Remove some text in a range
---@param i number
---@param j number
function File:remove(i, j)
    self.contents = self.contents:sub(1, i - 1) .. self.contents:sub(j + 1)
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
                  name: (identifier) @variable_name (#eq? @variable_name "%s")
                  value: (_) @variable_value))))))
    ]],
            environment,
            variable
        )
    )

    for _, match in query:iter_matches(self.tree:root(), self.contents, 0, -1) do
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

    return nil, nil
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
                  name: (identifier) @variable_name (#eq? @variable_name "%s")
                  value: (_) @variable_value) @field)))))
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

    return nil, nil
end

function File:find_last_environment_variable_node(environment)
    local query = vim.treesitter.query.parse(
        "lua",
        string.format(
            [[
(return_statement
  (expression_list
    (table_constructor
      (field
        name: (identifier) @env (#eq? @env "default")
        value: (table_constructor
                 (field) @last_field .)))))
    ]],
            environment
        )
    )

    for _, match in query:iter_matches(self.tree:root(), self.contents, 0, -1) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            for _, node in ipairs(nodes) do
                if name == "last_field" then
                    local text =
                        vim.treesitter.get_node_text(node, self.contents)
                    return node, text
                end
            end
        end
    end

    return nil, nil
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
                    local start_row, start_col, end_row, end_col = node:range()
                    table.insert(
                        ranges,
                        { start_row, start_col, end_row, end_col }
                    )
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
    self:replace(start_bytes, end_bytes, new_text)
end

function File:remove_node(node)
    local _, _, start_bytes, _, _, end_bytes = node:range(true)

    if self.contents:sub(end_bytes + 1, end_bytes + 1) == "," then
        end_bytes = end_bytes + 1
    end
    self:remove(start_bytes, end_bytes)
end

function File:insert_after_node(node, new_text)
    local _, _, _, _, _, end_bytes = node:range(true)

    if self.contents:sub(end_bytes + 1, end_bytes + 1) == "," then
        end_bytes = end_bytes + 1
    end

    self:insert(end_bytes, new_text)
end

function File:set_environment_variable(environment, variable, new_text)
    local value_node =
        self:find_environment_variable_value_node(environment, variable)

    if value_node ~= nil then
        self:replace_node(value_node, new_text)
    else
        local last_variable_node =
            self:find_last_environment_variable_node(environment)
        new_text = string.format("%s = %s", variable, new_text)
        self:insert_after_node(last_variable_node, new_text)
    end
end

function File:unset_environment_variable(environment, variable)
    local node = self:find_environment_variable_node(environment, variable)
    if node ~= nil then
        self:remove_node(node)
    end
end

function File:save()
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
                    fs.write(self.path, self.contents)
                else
                    fs.write(self.path, out.stdout)
                end
            end
        )
    else
        fs.write(self.path, self.contents)
    end
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
-- local f = p:parse(".nurl/environments.lua")

-- f:replace_environment_variable_value("default", "session_id", [["dani"]])
-- f:unset_environment_variable("default", "title")
-- f:save()

M.FileParser = FileParser

return M

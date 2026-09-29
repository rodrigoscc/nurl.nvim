---@class nurl.TextHighlight
---@field col_start integer
---@field col_end integer
---@field hl_group string

---@class nurl.TextLine
---@field text string
---@field highlights nurl.TextHighlight[]

---Builds highlighted text line by line, to render into a read-only buffer.
---@class nurl.TextBuilder
---@field lines nurl.TextLine[]
---@field current_line integer
local TextBuilder = {}
TextBuilder.__index = TextBuilder

---@return nurl.TextBuilder
function TextBuilder:new()
    return setmetatable({ lines = {}, current_line = 0 }, self)
end

---Append text to the current line.
---@param text string
---@param hl_group? string
---@return nurl.TextBuilder
function TextBuilder:append(text, hl_group)
    if not self.lines[self.current_line + 1] then
        self.lines[self.current_line + 1] = { text = "", highlights = {} }
    end

    local line = self.lines[self.current_line + 1]
    local col_start = #line.text

    line.text = line.text .. text

    if hl_group then
        table.insert(line.highlights, {
            col_start = col_start,
            col_end = col_start + #text,
            hl_group = hl_group,
        })
    end

    return self
end

---Start a new line. The current line is kept even if nothing was appended to
---it, so calling this twice leaves an empty line.
---@return nurl.TextBuilder
function TextBuilder:newline()
    if not self.lines[self.current_line + 1] then
        self.lines[self.current_line + 1] = { text = "", highlights = {} }
    end

    self.current_line = self.current_line + 1

    return self
end

---Start a new line that is kept even if nothing is appended to it. Followed
---by newline(), it leaves an empty line.
---@return nurl.TextBuilder
function TextBuilder:blankline()
    self:newline()
    self.lines[self.current_line + 1] = { text = "", highlights = {} }
    return self
end

---@return string[] lines
---@return {line: integer, col_start: integer, col_end: integer, hl_group: string}[] highlights
function TextBuilder:build()
    local text_lines = {}
    local all_highlights = {}

    for i, line in ipairs(self.lines) do
        table.insert(text_lines, line.text)

        for _, hl in ipairs(line.highlights) do
            table.insert(all_highlights, {
                line = i - 1,
                col_start = hl.col_start,
                col_end = hl.col_end,
                hl_group = hl.hl_group,
            })
        end
    end

    return text_lines, all_highlights
end

---Replace the buffer's text and its highlights in ns, leaving the buffer
---read-only.
---@param bufnr integer
---@param ns integer
function TextBuilder:render(bufnr, ns)
    local lines, highlights = self:build()

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, hl.line, hl.col_start, {
            end_col = hl.col_end,
            hl_group = hl.hl_group,
        })
    end

    vim.bo[bufnr].modifiable = false
end

return TextBuilder

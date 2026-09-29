local TextBuilder = require("nurl.ui.text_builder")

describe("text builder", function()
    it("tracks the columns of highlighted text", function()
        local lines, highlights = TextBuilder:new()
            :append("status ")
            :append("200", "Ok")
            :newline()
            :append("done", "Done")
            :build()

        assert.are.same({ "status 200", "done" }, lines)
        assert.are.same({
            { line = 0, col_start = 7, col_end = 10, hl_group = "Ok" },
            { line = 1, col_start = 0, col_end = 4, hl_group = "Done" },
        }, highlights)
    end)

    it("keeps empty lines", function()
        local lines = TextBuilder:new()
            :append("a")
            :newline()
            :newline()
            :append("b")
            :blankline()
            :newline()
            :append("c")
            :build()

        assert.are.same({ "a", "", "b", "", "c" }, lines)
    end)

    it("keeps a line started with blankline", function()
        assert.are.same(
            { "a", "" },
            TextBuilder:new():append("a"):blankline():build()
        )
        assert.are.same(
            { "a" },
            TextBuilder:new():append("a"):newline():build()
        )
    end)

    it("renders into a read-only buffer, replacing its highlights", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("nurl.text_builder_spec")

        TextBuilder:new():append("old", "Old"):render(bufnr, ns)
        TextBuilder:new():append("new ", "New"):append("text"):render(bufnr, ns)

        assert.are.same({ "new text" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        assert.is_false(vim.bo[bufnr].modifiable)
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
        assert.are.equal(1, #marks)
        assert.are.equal("New", marks[1][4].hl_group)
        assert.are.equal(4, marks[1][4].end_col)
    end)
end)

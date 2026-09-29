local targets = require("nurl.app.targets")
local pickers = require("nurl.pickers")
local projects = require("nurl.projects")
local client = require("nurl.app.client")
local Curl = require("nurl.core.curl")

local REQUESTS = [[
return {
    { "https://example.org/one" },
    {
        "https://example.org/two",
        method = "POST",
    },
}
]]

---@param dir string
---@param name string
---@param content string
---@return string path
local function write(dir, name, content)
    local path = vim.fs.joinpath(dir, name)
    vim.fn.writefile(vim.split(content, "\n"), path)
    return path
end

describe("targets", function()
    local dir, file

    before_each(function()
        dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        require("nurl").setup({ dir = dir, formatters = {} })
        file = write(dir, "requests.lua", REQUESTS)
    end)

    after_each(function()
        vim.cmd("silent! only")
        vim.cmd("silent! %bwipeout!")
        vim.fn.delete(dir, "rf")
    end)

    it("lists the requests of a file with their positions", function()
        local items = targets.file(file)

        assert.are.equal(2, #items)
        assert.are.equal("https://example.org/one", items[1].request[1])
        assert.are.same({ file, 2, 4, 2, 33 }, {
            items[1].file,
            items[1].start_row,
            items[1].start_col,
            items[1].end_row,
            items[1].end_col,
        })
        assert.are.equal(3, items[2].start_row)
        assert.are.equal(6, items[2].end_row)
    end)

    it("lists the requests of every project file", function()
        write(dir, "more.lua", 'return { { "https://example.org/three" } }')
        write(dir, "environments.lua", "return { dev = {} }")

        local urls = vim.tbl_map(function(item)
            return item.request[1]
        end, targets.project())
        table.sort(urls)

        assert.are.same({
            "https://example.org/one",
            "https://example.org/three",
            "https://example.org/two",
        }, urls)
    end)

    describe("at the cursor", function()
        before_each(function()
            vim.cmd.edit(file)
        end)

        for _, case in ipairs({
            { { 2, 4 }, "https://example.org/one" },
            { { 2, 20 }, "https://example.org/one" },
            { { 4, 8 }, "https://example.org/two" },
            { { 6, 4 }, "https://example.org/two" },
        }) do
            it(("finds the request at %d:%d"):format(unpack(case[1])), function()
                vim.api.nvim_win_set_cursor(0, case[1])
                assert.are.equal(case[2], targets.cursor().request[1])
            end)
        end

        for _, position in ipairs({ { 1, 0 }, { 2, 0 }, { 7, 0 } }) do
            it(("finds nothing at %d:%d"):format(unpack(position)), function()
                vim.api.nvim_win_set_cursor(0, position)
                assert.is_nil(targets.cursor())
            end)
        end
    end)

    it("finds the request shown in a response window", function()
        local request = { method = "GET", url = "https://example.org", headers = {} }
        local view = client.open_history_item({
            "2026-09-26T10:00:00",
            request,
            {
                status_code = 200,
                reason_phrase = "OK",
                protocol = "HTTP/1.1",
                headers = {},
                body = "",
                time = {},
                size = {},
                speed = {},
            },
            Curl:new({
                args = {},
                result = { code = 0, signal = 0, stdout = "", stderr = "" },
            }),
        })

        local item = targets.cursor()

        assert.are.equal(request, item.request)
        assert.are.equal(view.win, item.win)
    end)

    it("keeps requests a file builds without positions", function()
        local built = write(dir, "built.lua", [[
local requests = {}
for i = 1, 2 do
    table.insert(requests, { "https://example.org/" .. i })
end
return requests
]])

        local items = targets.file(built)
        assert.are.equal(2, #items)
        assert.is_nil(items[1].start_row)

        vim.cmd.edit(built)
        vim.api.nvim_win_set_cursor(0, { 3, 4 })
        assert.is_nil(targets.cursor())

        projects.jump_to(items[1])
        assert.are.equal(built, vim.api.nvim_buf_get_name(0))
    end)

    describe("choose", function()
        local pick = pickers.pick
        local picked

        before_each(function()
            picked = nil
            pickers.pick = function(title, items, on_pick)
                picked = { title = title, items = items, on_pick = on_pick }
            end
        end)

        after_each(function()
            pickers.pick = pick
        end)

        it("acts on the only item without a picker", function()
            local chosen
            targets.choose("title", { { request = {} } }, function(item)
                chosen = item
            end)

            assert.is_nil(picked)
            assert.is_not_nil(chosen)
        end)

        it("picks one of several items", function()
            local on_choose = function() end
            targets.choose("title", targets.file(file), on_choose)

            assert.are.equal("title", picked.title)
            assert.are.equal(2, #picked.items)
            assert.are.equal(on_choose, picked.on_pick)
        end)

        it("jumps to the only item without an action", function()
            targets.choose("title", { targets.file(file)[2] })

            assert.are.equal(file, vim.api.nvim_buf_get_name(0))
            assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
        end)
    end)
end)

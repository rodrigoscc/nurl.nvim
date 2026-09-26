local convert = require("nurl.convert")

describe("convert", function()
    describe("json_to_lua", function()
        it("sorts keys and nests tables", function()
            assert.are.equal(
                [[
{
    author = {
        active = true,
        name = "Ada",
    },
    tags = {
        "a",
        "b",
    },
    title = "Hello",
    userId = 1,
}]],
                convert.json_to_lua(
                    [[{"title": "Hello", "userId": 1, "tags": ["a", "b"],
                    "author": {"name": "Ada", "active": true}}]]
                )
            )
        end)

        it("quotes keys that are not Lua names", function()
            assert.are.equal(
                [[
{
    [""] = 3,
    ["1st"] = 2,
    ["Content-Type"] = "json",
    ["end"] = 1,
    snake_case = 4,
}]],
                convert.json_to_lua(
                    [[{"Content-Type": "json", "end": 1, "1st": 2, "": 3, "snake_case": 4}]]
                )
            )
        end)

        it("converts null, empty objects and empty arrays", function()
            assert.are.equal(
                [[
{
    a = vim.NIL,
    b = vim.empty_dict(),
    c = {},
}]],
                convert.json_to_lua([[{"a": null, "b": {}, "c": []}]])
            )
        end)

        it("keeps every digit of numbers and escapes strings", function()
            assert.are.equal(
                [[
{
    -1500,
    123456789012345,
    0.30000000000000004,
    'say "hi"\n\ttab\\',
    "é ✓ 😀",
}]],
                convert.json_to_lua(
                    [=[[-1.50e3, 123456789012345, 0.30000000000000004,
                    "say \"hi\"\n\ttab\\", "\u00e9 ✓ \ud83d\ude00"]]=]
                )
            )
        end)

        it("uses the given indentation", function()
            assert.are.equal(
                "{\n\tid = 1,\n}",
                convert.json_to_lua('{"id": 1}', { indent = "\t" })
            )
        end)

        it("round-trips through Lua and JSON encoding", function()
            local json = [[{"a": [1, 2.5, {"b": null}], "c": "x/y", "d": {}, "e": false}]]
            local value = assert(load("return " .. convert.json_to_lua(json)))()
            assert.are.same(vim.json.decode(json), value)
            assert.are.equal("{}", vim.json.encode(value.d))
        end)

        it("reports invalid JSON", function()
            local ok, err = pcall(convert.json_to_lua, '{"a": 1, "b" 2}')
            assert.is_false(ok)
            assert.matches("^Invalid JSON: ", err)
        end)
    end)

    describe("lua_to_json", function()
        it("formats tables as JSON with sorted keys", function()
            assert.are.equal(
                [[
{
    "author": {
        "name": "Ada"
    },
    "tags": [
        "a",
        "b"
    ],
    "title": "Hello",
    "url": "https://example.org/a"
}]],
                convert.lua_to_json(
                    [[{ title = "Hello", tags = { "a", "b" }, author = { name = "Ada" },
                    url = "https://example.org/a" }]]
                )
            )
        end)

        it("converts vim.NIL, empty tables and numbers", function()
            assert.are.equal(
                '{\n    "a": null,\n    "b": {},\n    "c": [],\n    "d": 0.1,\n    "e": -3\n}',
                convert.lua_to_json(
                    "{ a = vim.NIL, b = vim.empty_dict(), c = {}, d = 0.1, e = -3 }"
                )
            )
        end)

        it("allows a trailing comma", function()
            assert.are.equal("[\n    1\n]", convert.lua_to_json("{ 1 },"))
        end)

        it("reports values JSON cannot represent", function()
            local ok, err = pcall(
                convert.lua_to_json,
                "{ user = { token = function() end } }"
            )
            assert.is_false(ok)
            assert.matches("^Cannot convert to JSON: .*function", err)
        end)

        it("reports invalid Lua", function()
            local ok, err = pcall(convert.lua_to_json, "{ a = }")
            assert.is_false(ok)
            assert.matches("^Invalid Lua table", err)
        end)
    end)

    describe("commands", function()
        before_each(function()
            require("nurl").setup({})
            vim.cmd.enew({ bang = true })
            vim.bo.expandtab = true
            vim.bo.shiftwidth = 4
        end)

        local function lines()
            return vim.api.nvim_buf_get_lines(0, 0, -1, false)
        end

        it("converts a character-wise selection in place", function()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "return {",
                "    {",
                '        data = {"name": "Ada", "tags": ["x"]},',
                "    },",
                "}",
            })
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            vim.cmd("normal! f{v%\27")
            vim.cmd("'<,'>Nurl json_to_lua")

            assert.are.same({
                "return {",
                "    {",
                "        data = {",
                '            name = "Ada",',
                "            tags = {",
                '                "x",',
                "            },",
                "        },",
                "    },",
                "}",
            }, lines())

            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            vim.cmd("normal! f{v%\27")
            vim.cmd("'<,'>Nurl lua_to_json")
            assert.are.same({
                "return {",
                "    {",
                "        data = {",
                '            "name": "Ada",',
                '            "tags": [',
                '                "x"',
                "            ]",
                "        },",
                "    },",
                "}",
            }, lines())
        end)

        it("converts selected lines, keeping their indentation", function()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "data =",
                '    {"a": 1,',
                '     "b": [true]}',
                "rest",
            })
            vim.cmd("2,3Nurl json_to_lua")

            assert.are.same({
                "data =",
                "    {",
                "        a = 1,",
                "        b = {",
                "            true,",
                "        },",
                "    }",
                "rest",
            }, lines())
        end)

        it("converts the whole buffer without a range", function()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[1, 2]" })
            vim.cmd("Nurl json_to_lua")
            assert.are.same({ "{", "    1,", "    2,", "}" }, lines())
        end)

        it("leaves the buffer unchanged and reports invalid input", function()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { '{"a": }' })
            local notify = vim.notify
            local messages = {}
            vim.notify = function(message, level)
                table.insert(messages, { message, level })
            end
            vim.cmd("Nurl json_to_lua")
            vim.notify = notify

            assert.are.same({ '{"a": }' }, lines())
            assert.are.equal(vim.log.levels.ERROR, messages[1][2])
            assert.matches("^Invalid JSON: ", messages[1][1])
        end)
    end)
end)

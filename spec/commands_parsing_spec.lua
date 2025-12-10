local commands_parsing = require("nurl.commands_parsing")

describe("commands_parsing", function()
    describe("parse_command", function()
        describe("no arguments", function()
            it("parses empty string", function()
                local result = commands_parsing.parse_command("")
                assert.are.same(
                    { subcommand = nil, arg = nil, overrides = {} },
                    result
                )
            end)
        end)

        describe("subcommands without args", function()
            it("parses jump", function()
                local result = commands_parsing.parse_command("jump")
                assert.are.same(
                    { subcommand = "jump", arg = nil, overrides = {} },
                    result
                )
            end)

            it("parses history", function()
                local result = commands_parsing.parse_command("history")
                assert.are.same(
                    { subcommand = "history", arg = nil, overrides = {} },
                    result
                )
            end)

            it("parses env_file", function()
                local result = commands_parsing.parse_command("env_file")
                assert.are.same(
                    { subcommand = "env_file", arg = nil, overrides = {} },
                    result
                )
            end)

            it("parses yank", function()
                local result = commands_parsing.parse_command("yank")
                assert.are.same(
                    { subcommand = "yank", arg = nil, overrides = {} },
                    result
                )
            end)

            it("parses env", function()
                local result = commands_parsing.parse_command("env")
                assert.are.same(
                    { subcommand = "env", arg = nil, overrides = {} },
                    result
                )
            end)

            it("parses resend", function()
                local result = commands_parsing.parse_command("resend")
                assert.are.same(
                    { subcommand = "resend", arg = nil, overrides = {} },
                    result
                )
            end)
        end)

        describe("subcommands with args", function()
            it("parses jump with cursor target", function()
                local result = commands_parsing.parse_command("jump .")
                assert.are.same(
                    { subcommand = "jump", arg = ".", overrides = {} },
                    result
                )
            end)

            it("parses jump with buffer target", function()
                local result = commands_parsing.parse_command("jump %")
                assert.are.same(
                    { subcommand = "jump", arg = "%", overrides = {} },
                    result
                )
            end)

            it("parses jump with filepath", function()
                local result =
                    commands_parsing.parse_command("jump requests/login.lua")
                assert.are.same({
                    subcommand = "jump",
                    arg = "requests/login.lua",
                    overrides = {},
                }, result)
            end)

            it("parses env with name", function()
                local result = commands_parsing.parse_command("env production")
                assert.are.same(
                    { subcommand = "env", arg = "production", overrides = {} },
                    result
                )
            end)

            it("parses resend with positive number", function()
                local result = commands_parsing.parse_command("resend 3")
                assert.are.same(
                    { subcommand = "resend", arg = "3", overrides = {} },
                    result
                )
            end)

            it("parses resend with negative number", function()
                local result = commands_parsing.parse_command("resend -2")
                assert.are.same(
                    { subcommand = "resend", arg = "-2", overrides = {} },
                    result
                )
            end)

            it("parses yank with cursor target", function()
                local result = commands_parsing.parse_command("yank .")
                assert.are.same(
                    { subcommand = "yank", arg = ".", overrides = {} },
                    result
                )
            end)
        end)

        describe("default command (no subcommand)", function()
            it("parses cursor target", function()
                local result = commands_parsing.parse_command(".")
                assert.are.same(
                    { subcommand = nil, arg = ".", overrides = {} },
                    result
                )
            end)

            it("parses buffer target", function()
                local result = commands_parsing.parse_command("%")
                assert.are.same(
                    { subcommand = nil, arg = "%", overrides = {} },
                    result
                )
            end)

            it("parses filepath", function()
                local result =
                    commands_parsing.parse_command("requests/users.lua")
                assert.are.same({
                    subcommand = nil,
                    arg = "requests/users.lua",
                    overrides = {},
                }, result)
            end)
        end)

        describe("overrides", function()
            it("parses single override with string value", function()
                local result =
                    commands_parsing.parse_command(". data.name=John")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "name" }, "John" } },
                }, result)
            end)

            it("parses single override with number value", function()
                local result = commands_parsing.parse_command(". data.id=42")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "id" }, 42 } },
                }, result)
            end)

            it("parses single override with boolean true", function()
                local result =
                    commands_parsing.parse_command(". data.active=true")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "active" }, true } },
                }, result)
            end)

            it("parses single override with boolean false", function()
                local result =
                    commands_parsing.parse_command(". data.enabled=false")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "enabled" }, false } },
                }, result)
            end)

            it("parses override with quoted string value", function()
                local result =
                    commands_parsing.parse_command('. data.name="John Doe"')
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "name" }, "John Doe" } },
                }, result)
            end)

            it("parses override with array index", function()
                local result = commands_parsing.parse_command(". url[2]=42")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "url", 2 }, 42 } },
                }, result)
            end)

            it("parses override with bracket string key", function()
                local result = commands_parsing.parse_command(
                    '. headers["Content-Type"]="application/json"'
                )
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = {
                        { { "headers", "Content-Type" }, "application/json" },
                    },
                }, result)
            end)

            it("parses deeply nested path", function()
                local result = commands_parsing.parse_command(
                    ". data.user.address.city=NYC"
                )
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = {
                        { { "data", "user", "address", "city" }, "NYC" },
                    },
                }, result)
            end)

            it("parses mixed dot and bracket notation", function()
                local result =
                    commands_parsing.parse_command(". data.items[0].name=test")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "items", 0, "name" }, "test" } },
                }, result)
            end)

            it("parses multiple overrides", function()
                local result =
                    commands_parsing.parse_command(". data.id=1 data.name=John")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = {
                        { { "data", "id" }, 1 },
                        { { "data", "name" }, "John" },
                    },
                }, result)
            end)

            it("parses multiple overrides with mixed types", function()
                local result = commands_parsing.parse_command(
                    '. data.id=42 data.active=true data.name="Jane Doe"'
                )
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = {
                        { { "data", "id" }, 42 },
                        { { "data", "active" }, true },
                        { { "data", "name" }, "Jane Doe" },
                    },
                }, result)
            end)

            it("parses override without arg (project-wide)", function()
                local result = commands_parsing.parse_command("data.id=5")
                assert.are.same({
                    subcommand = nil,
                    arg = nil,
                    overrides = { { { "data", "id" }, 5 } },
                }, result)
            end)

            it("parses filepath with overrides", function()
                local result = commands_parsing.parse_command(
                    "requests/login.lua data.user=admin"
                )
                assert.are.same({
                    subcommand = nil,
                    arg = "requests/login.lua",
                    overrides = { { { "data", "user" }, "admin" } },
                }, result)
            end)

            it("parses subcommand with arg and overrides", function()
                local result =
                    commands_parsing.parse_command("yank . data.id=99")
                assert.are.same({
                    subcommand = "yank",
                    arg = ".",
                    overrides = { { { "data", "id" }, 99 } },
                }, result)
            end)

            it("parses bracket-only path for index 1", function()
                local result = commands_parsing.parse_command(". [1]=hello")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { 1 }, "hello" } },
                }, result)
            end)

            it("parses bracket-only path with quoted key", function()
                local result =
                    commands_parsing.parse_command('. ["Content-Type"]=json')
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "Content-Type" }, "json" } },
                }, result)
            end)

            it("parses single-quoted string value", function()
                local result =
                    commands_parsing.parse_command(". data.name='John Doe'")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "data", "name" }, "John Doe" } },
                }, result)
            end)

            it("parses single-quoted key", function()
                local result =
                    commands_parsing.parse_command(". headers['Content-Type']=json")
                assert.are.same({
                    subcommand = nil,
                    arg = ".",
                    overrides = { { { "headers", "Content-Type" }, "json" } },
                }, result)
            end)
        end)
    end)
end)

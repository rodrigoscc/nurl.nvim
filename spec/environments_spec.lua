-- The tests change directory, and the busted config finds modules relative
-- to the current one.
local repo = vim.uv.cwd()
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;"):format(repo, repo)
    .. package.path

local env_project = require("nurl.env.project")

local ENVIRONMENTS = [[
vim.g.nurl_env_loads = (vim.g.nurl_env_loads or 0) + 1

return {
    dev = {
        name = "%s",
        token = "old",
    },
    prod = {
        name = "%s prod",
    },
}
]]

describe("environments", function()
    local root, a, b, active_file
    local cwd = vim.uv.cwd()
    local notify = vim.notify
    local notifications

    ---@param dir string
    ---@param content string
    ---@return string path
    local function write_environments(dir, content)
        vim.fn.mkdir(vim.fs.joinpath(dir, ".nurl"), "p")
        local path = vim.fs.joinpath(dir, ".nurl", "environments.lua")
        vim.fn.writefile(vim.split(content, "\n"), path)
        return path
    end

    ---@param path string
    ---@return string
    local function read(path)
        return table.concat(vim.fn.readfile(path), "\n")
    end

    ---Wait until the environments file of a directory contains text.
    ---@param dir string
    ---@param text string
    local function wait_for_file(dir, text)
        local path = vim.fs.joinpath(dir, ".nurl", "environments.lua")
        assert(
            vim.wait(2000, function()
                return read(path):find(text, 1, true) ~= nil
            end),
            "environments file never contained " .. text .. ":\n" .. read(path)
        )
    end

    before_each(function()
        root = vim.fn.resolve(vim.fn.tempname())
        a = vim.fs.joinpath(root, "a")
        b = vim.fs.joinpath(root, "b")
        write_environments(a, ENVIRONMENTS:format("a", "a"))
        write_environments(b, ENVIRONMENTS:format("b", "b"))
        active_file = vim.fs.joinpath(root, "envs.json")

        require("nurl").setup({
            formatters = {},
            active_environments_file = active_file,
        })
        vim.g.nurl_env_loads = nil
        vim.cmd.cd(a)

        notifications = {}
        vim.notify = function(msg)
            table.insert(notifications, msg)
        end
    end)

    after_each(function()
        vim.notify = notify
        for _, dir in ipairs({ a, b }) do
            env_project.reload(vim.fs.joinpath(dir, ".nurl", "environments.lua"))
        end
        vim.cmd("silent! %bwipeout!")
        vim.cmd.cd(cwd)
        vim.fn.delete(root, "rf")
    end)

    it("loads the environments file on first use only", function()
        require("nurl").setup({ active_environments_file = active_file })
        assert.is_nil(vim.g.nurl_env_loads)

        Nurl.env.get("name", "dev")
        Nurl.env.get("name", "dev")

        assert.are.equal(1, vim.g.nurl_env_loads)
    end)

    it("uses the project of the current directory", function()
        assert.are.equal("a", Nurl.env.get("name", "dev"))

        vim.cmd.cd(b)

        assert.are.equal("b", Nurl.env.get("name", "dev"))
    end)

    it("keeps the active environment of each directory", function()
        Nurl.activate_env("dev")
        assert.are.equal("dev", Nurl.get_active_env())
        assert.are.equal("a", Nurl.env.get("name"))

        vim.cmd.cd(b)
        assert.is_nil(Nurl.get_active_env())
        assert.is_nil(Nurl.env.get("name"))

        vim.cmd.cd(a)
        env_project.reload(vim.fs.joinpath(a, ".nurl", "environments.lua"))
        assert.are.equal("dev", Nurl.get_active_env())
        assert.are.same({ [a] = "dev" }, vim.json.decode(read(active_file)))
    end)

    it("does not activate an unknown environment", function()
        assert.has_error(function()
            Nurl.activate_env("staging")
        end, "Could not activate environment staging, not found")
    end)

    it("resolves variables when the request is sent", function()
        Nurl.activate_env("dev")
        local name = Nurl.env.var("name")

        vim.cmd.cd(b)
        Nurl.activate_env("prod")

        assert.are.equal("b prod", name())
    end)

    it("reloads a project when its environments file is written", function()
        assert.are.equal("a", Nurl.env.get("name", "dev"))

        vim.cmd.edit(vim.fs.joinpath(a, ".nurl", "environments.lua"))
        vim.cmd([[%s/name = "a",/name = "edited",/]])
        vim.cmd("silent write")

        assert.are.equal("edited", Nurl.env.get("name", "dev"))
    end)

    it("sets and unsets variables in memory and in the file", function()
        Nurl.activate_env("dev")

        Nurl.env.set("token", "new")
        Nurl.env.set("count", 3)
        Nurl.env.set("name", "b prod", "prod")
        Nurl.env.unset("name")

        assert.are.equal("new", Nurl.env.get("token"))
        assert.are.equal(3, Nurl.env.get("count"))
        assert.is_nil(Nurl.env.get("name"))
        assert.are.equal("b prod", Nurl.env.get("name", "prod"))

        wait_for_file(a, "count = 3")
        local written = dofile(vim.fs.joinpath(a, ".nurl", "environments.lua"))
        assert.are.same({
            dev = { token = "new", count = 3 },
            prod = { name = "b prod" },
        }, written)
    end)

    it("queues edits while the formatter runs", function()
        -- cat stands in for stylua, keeping the text as it is.
        require("nurl").setup({
            formatters = { lua = { cmd = { "cat" } } },
            active_environments_file = active_file,
        })
        Nurl.activate_env("dev")

        for i = 1, 5 do
            Nurl.env.set("n" .. i, i)
        end

        wait_for_file(a, "n5 = 5")
        local written = dofile(vim.fs.joinpath(a, ".nurl", "environments.lua"))
        assert.are.same(
            { name = "a", token = "old", n1 = 1, n2 = 2, n3 = 3, n4 = 4, n5 = 5 },
            written.dev
        )
    end)

    it("escapes the values it writes", function()
        local values = {
            quote = 'say "hi"',
            backslash = [[C:\temp]],
            newline = "line 1\nline 2",
            control = "tab\tbell\a",
        }

        for name, value in pairs(values) do
            Nurl.env.set(name, value, "dev")
        end

        wait_for_file(a, "control =")
        local written = dofile(vim.fs.joinpath(a, ".nurl", "environments.lua"))
        for name, value in pairs(values) do
            assert.are.equal(value, written.dev[name], name)
        end
    end)

    for _, name in ipairs({ "api-key", "end", "1st", "" }) do
        it(("refuses the variable name %q"):format(name), function()
            local path = vim.fs.joinpath(a, ".nurl", "environments.lua")
            local before = read(path)

            assert.has_error(function()
                Nurl.env.set(name, "x", "dev")
            end, ("Invalid variable name %q: it must be a Lua identifier"):format(name))

            assert.is_nil(Nurl.env.get(name, "dev"))
            vim.wait(50)
            assert.are.equal(before, read(path))
        end)
    end

    it("warns when the environment is not written as a name in the file", function()
        local path = write_environments(a, [[
return {
    ["my-env"] = {
        token = "old",
    },
}
]])

        Nurl.env.set("token", "new", "my-env")

        assert.are.equal("new", Nurl.env.get("token", "my-env"))
        assert.is_true(vim.wait(1000, function()
            return #notifications > 0
        end))
        assert.matches("Could not find environment my%-env in", notifications[1])
        assert.matches('token = "old"', read(path))
    end)

    it("refuses to set without an active environment", function()
        assert.has_error(function()
            Nurl.env.set("token", "new")
        end, "No active env")
    end)

    it("refuses to set without an environments file", function()
        local empty = vim.fs.joinpath(root, "empty")
        vim.fn.mkdir(empty, "p")
        vim.cmd.cd(empty)

        assert.is_nil(Nurl.env.get("name", "dev"))
        assert.has_error(function()
            Nurl.env.set("token", "new", "dev")
        end, 'Env "dev" not found')
    end)

    it("reports an environments file that fails to load", function()
        write_environments(a, "return {")

        assert.is_nil(Nurl.env.get("name", "dev"))
        assert.matches("Could not load environments file", notifications[1])
    end)
end)

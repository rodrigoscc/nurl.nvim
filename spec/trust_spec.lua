-- The tests change directory, and the busted config finds modules relative
-- to the current one.
local repo = vim.uv.cwd()
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;"):format(repo, repo)
    .. package.path

local trust = require("nurl.trust")
local targets = require("nurl.app.targets")
local env_project = require("nurl.env.project")

describe("trust", function()
    local root, project, nurl_dir, trust_file
    local cwd = vim.uv.cwd()
    local confirm, notify = vim.fn.confirm, vim.notify
    local prompts, notifications, answer

    before_each(function()
        root = vim.fn.resolve(vim.fn.tempname())
        project = vim.fs.joinpath(root, "project")
        nurl_dir = vim.fs.joinpath(project, ".nurl")
        vim.fn.mkdir(nurl_dir, "p")
        vim.fn.writefile({
            "vim.g.nurl_trust_ran = true",
            'return { { "https://example.org/one" } }',
        }, vim.fs.joinpath(nurl_dir, "one.lua"))
        vim.fn.writefile(
            { 'return { { "https://example.org/two" } }' },
            vim.fs.joinpath(nurl_dir, "two.lua")
        )
        vim.fn.writefile(
            { 'return { dev = { token = "secret" } }' },
            vim.fs.joinpath(nurl_dir, "environments.lua")
        )

        trust_file = vim.fs.joinpath(root, "trust.json")
        require("nurl").setup({
            trust = { file = trust_file },
            formatters = {},
        })
        vim.cmd.cd(project)
        vim.g.nurl_trust_ran = nil

        prompts, notifications, answer = {}, {}, 2
        vim.fn.confirm = function(msg)
            table.insert(prompts, msg)
            return answer
        end
        vim.notify = function(msg)
            table.insert(notifications, msg)
        end
    end)

    after_each(function()
        vim.fn.confirm, vim.notify = confirm, notify
        env_project.reload(vim.fs.joinpath(nurl_dir, "environments.lua"))
        vim.cmd.cd(cwd)
        vim.fn.delete(root, "rf")
    end)

    ---@return table<string, string>
    local function saved()
        if vim.fn.filereadable(trust_file) == 0 then
            return {}
        end
        return vim.json.decode(table.concat(vim.fn.readfile(trust_file), "\n"))
    end

    it("asks once for all the files of a directory", function()
        answer = 1

        local items = targets.project()

        assert.are.equal(2, #items)
        assert.are.equal(1, #prompts)
        assert.matches("run the Lua files in " .. vim.pesc(nurl_dir), prompts[1])
        assert.are.same({ [nurl_dir] = "trusted" }, saved())
    end)

    it("remembers a trusted directory", function()
        answer = 1
        targets.project()

        targets.project()
        assert.are.equal("secret", Nurl.env.get("token", "dev"))

        assert.are.equal(1, #prompts)
    end)

    it("runs nothing until asked again next session with Later", function()
        answer = 2

        assert.are.same({}, targets.project())
        assert.is_nil(Nurl.env.get("token", "dev"))
        assert.are.same({}, targets.project())

        assert.is_nil(vim.g.nurl_trust_ran)
        assert.are.equal(1, #prompts)
        assert.are.same({}, saved())
        assert.are.equal(1, #notifications)
        assert.matches("not trusted. Run :Nurl trust", notifications[1])
    end)

    it("remembers a denied directory with Never", function()
        answer = 3

        assert.are.same({}, targets.project())

        assert.are.same({ [nurl_dir] = "denied" }, saved())
        assert.is_false(trust.allows(nurl_dir))
        assert.are.equal(1, #prompts)
    end)

    it("trusts the project with :Nurl trust", function()
        answer = 3
        assert.is_nil(Nurl.env.get("token", "dev"))

        vim.cmd("Nurl trust")

        assert.are.same({ [nurl_dir] = "trusted" }, saved())
        assert.are.equal("secret", Nurl.env.get("token", "dev"))
        assert.are.equal(2, #targets.project())
    end)

    it("asks again after :Nurl untrust", function()
        answer = 1
        targets.project()

        vim.cmd("Nurl untrust .nurl")
        answer = 2

        assert.are.same({}, saved())
        assert.are.same({}, targets.project())
        assert.are.equal(2, #prompts)
    end)

    it("shows the active environment without running or asking", function()
        require("nurl").setup({
            trust = { file = trust_file },
            active_environments_file = vim.fs.joinpath(root, "envs.json"),
        })
        require("nurl.env.active").set(project, "dev")

        -- Such as a statusline showing it as it redraws.
        local line = vim.api.nvim_eval_statusline(
            "%{v:lua.Nurl.get_active_env()}",
            {}
        ).str

        assert.are.equal("dev", line)
        assert.are.same({}, prompts)

        -- The variables need the file, which asks first.
        assert.is_nil(Nurl.env.get("token", "dev"))
        assert.are.equal(1, #prompts)
    end)

    it("refuses to use the active environment of a directory not trusted", function()
        require("nurl").setup({
            trust = { file = trust_file },
            active_environments_file = vim.fs.joinpath(root, "envs.json"),
        })
        require("nurl.env.active").set(project, "dev")
        local message = (
            "Cannot use environment dev: the Lua files in %s are not trusted. Run :Nurl trust to trust them."
        ):format(nurl_dir)

        assert.has_error(function()
            Nurl.env.get("token")
        end, message)
        assert.has_error(function()
            Nurl.send({ "https://example.org" })
        end, message)
        assert.are.equal(1, #prompts)
    end)

    it("trusts every directory when disabled", function()
        require("nurl").setup({
            trust = { enabled = false, file = trust_file },
        })

        assert.are.equal(2, #targets.project())

        assert.are.same({}, prompts)
        assert.are.equal(0, vim.fn.filereadable(trust_file))
    end)
end)

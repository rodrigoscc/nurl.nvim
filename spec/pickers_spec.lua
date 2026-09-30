local pickers = require("nurl.pickers")

describe("pickers", function()
    local modules = {
        "snacks",
        "telescope",
        "mini.pick",
        "nurl.pickers.snacks",
        "nurl.pickers.telescope",
        "nurl.pickers.mini",
    }
    local saved = {}
    local used

    ---Make the picker modules installed or missing, with interfaces that
    ---record which one is used.
    ---@param installed table<string, boolean>
    local function install(installed)
        for _, name in ipairs({ "snacks", "telescope", "mini" }) do
            local module = name == "mini" and "mini.pick" or name
            if installed[name] then
                package.loaded[module] = {}
            else
                package.loaded[module] = nil
                package.preload[module] = function()
                    error("not installed")
                end
            end
            package.loaded["nurl.pickers." .. name] = {
                pick = function()
                    used = name
                end,
            }
        end
    end

    before_each(function()
        used = nil
        for _, module in ipairs(modules) do
            saved[module] = {
                loaded = package.loaded[module],
                preload = package.preload[module],
            }
        end
    end)

    after_each(function()
        for _, module in ipairs(modules) do
            package.loaded[module] = saved[module].loaded
            package.preload[module] = saved[module].preload
        end
        require("nurl").setup()
    end)

    it("uses the first installed picker by default", function()
        require("nurl").setup()
        install({ telescope = true, mini = true })

        pickers.pick("title", {})

        assert.are.equal("telescope", used)
    end)

    it("uses the configured picker", function()
        require("nurl").setup({ picker = "mini" })
        install({ snacks = true, telescope = true, mini = true })

        pickers.pick("title", {})

        assert.are.equal("mini", used)
    end)

    it("errors when the configured picker is not installed", function()
        require("nurl").setup({ picker = "telescope" })
        install({ snacks = true })

        assert.has_error(function()
            pickers.pick("title", {})
        end, "Picker telescope is not supported or not installed")
    end)
end)

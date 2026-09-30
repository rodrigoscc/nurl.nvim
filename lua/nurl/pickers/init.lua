local config = require("nurl.config")
local items = require("nurl.pickers.items")

local M = {}

local pickers_interfaces = {
    { name = "snacks", module = "snacks", interface = "nurl.pickers.snacks" },
    {
        name = "telescope",
        module = "telescope",
        interface = "nurl.pickers.telescope",
    },
    { name = "mini", module = "mini.pick", interface = "nurl.pickers.mini" },
}

local function find_picker_interface()
    for _, opts in ipairs(pickers_interfaces) do
        if config.picker == nil or config.picker == opts.name then
            local status = pcall(require, opts.module)

            if status then
                return require(opts.interface)
            end
        end
    end

    if config.picker ~= nil then
        error(
            ("Picker %s is not supported or not installed"):format(
                config.picker
            )
        )
    end

    error("No supported picker found")
end

---Pick a request. Without on_pick, the picker jumps to where the request is
---defined, with its own ways to open it (split, tab, ...).
---@param title string
---@param request_items nurl.RequestItem[]
---@param on_pick? fun(item: nurl.RequestItem)
function M.pick(title, request_items, on_pick)
    local picker = find_picker_interface()
    picker.pick(title, items.prepare(request_items), on_pick)
end

return M

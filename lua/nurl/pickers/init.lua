local items = require("nurl.pickers.items")

local M = {}

local pickers_interfaces = {
    { module = "snacks", interface = "nurl.pickers.snacks" },
    { module = "telescope", interface = "nurl.pickers.telescope" },
}

local function find_picker_interface()
    for _, opts in ipairs(pickers_interfaces) do
        local status = pcall(require, opts.module)
        if status then
            return require(opts.interface)
        end
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

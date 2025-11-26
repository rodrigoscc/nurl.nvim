local M = {}

local pickers_interfaces = { snacks = "nurl.pickers.snacks" }

local function find_picker_interface()
    for picker_module, interface_module in pairs(pickers_interfaces) do
        local status = pcall(require, picker_module)
        if status then
            return require(interface_module)
        end
    end

    error("No supported picker found")
end

---@param title string
---@param super_requests nurl.SuperRequest[]
---@param on_pick? fun(request: nurl.SuperRequest)
function M.pick_request(title, super_requests, on_pick)
    local picker = find_picker_interface()
    picker.pick_request(title, super_requests, on_pick)
end

---@param title string
---@param project_request_items nurl.ProjectRequestItem[]
---@param on_pick? fun(item: nurl.ProjectRequestItem)
function M.pick_project_request_item(title, project_request_items, on_pick)
    local picker = find_picker_interface()
    picker.pick_project_request_item(title, project_request_items, on_pick)
end

---@param title string
---@param history_items nurl.HistoryItem[]
---@param on_pick? fun(item: nurl.HistoryItem)
function M.pick_request_history_item(title, history_items, on_pick)
    local picker = find_picker_interface()
    picker.pick_request_history_item(title, history_items, on_pick)
end

return M

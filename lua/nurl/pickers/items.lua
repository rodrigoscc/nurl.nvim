local requests = require("nurl.requests")

local M = {}

---A request to pick. Requests from project files know where they are.
---@class nurl.RequestItem
---@field request nurl.SuperRequest | nurl.Request
---@field file? string
---@field start_row? integer
---@field start_col? integer
---@field end_row? integer
---@field end_col? integer
---@field win? integer a response window already showing the request

---An item ready to show in a picker.
---@class nurl.PickerItem
---@field item nurl.RequestItem the item, with its request expanded except for lazy values, passed on pick
---@field preview nurl.Request the request with lazy values as placeholders, to display
---@field text string text to match the prompt against

---Expand the requests for display. Lazy values are kept for when the request
---is sent, so the picker never evaluates them. Requests that fail to expand
---are skipped with a warning.
---@param items nurl.RequestItem[]
---@return nurl.PickerItem[]
function M.prepare(items)
    ---@type nurl.PickerItem[]
    local prepared = {}

    for _, item in ipairs(items) do
        local ok, expanded = pcall(requests.expand, item.request, { lazy = true })

        if ok then
            local preview = requests.stringify_lazy(expanded)
            table.insert(prepared, {
                item = vim.tbl_extend("force", item, { request = expanded }),
                preview = preview,
                text = requests.text(preview, { suffix = item.file }),
            })
        else
            local location = item.file
                    and (" in %s:%s"):format(item.file, item.start_row)
                or ""
            vim.notify(
                ("Skipped request%s after error: %s"):format(location, expanded),
                vim.log.levels.WARN
            )
        end
    end

    return prepared
end

return M

local requests = require("nurl.requests")
local actions = require("snacks.picker.actions")
local http_message = require("nurl.ui.http_message")

local M = {}

---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format_item(item)
    local ret = {}

    table.insert(ret, { "", "SnacksPickerIcon" })
    table.insert(ret, { " " })

    if item.preview.title then
        table.insert(ret, { item.preview.title, "SnacksPickerLabel" })
        table.insert(ret, { " " })
    else
        table.insert(ret, { item.preview.method, "SnacksPickerFileType" })
        table.insert(ret, { " " })

        table.insert(
            ret,
            { requests.full_url(item.preview), "SnacksPickerLabel" }
        )
        table.insert(ret, { " " })
    end

    if item.file then
        table.insert(ret, { item.file, "SnacksPickerDir" })
        table.insert(ret, { " " })
    end

    return ret
end

---@param title string
---@param items nurl.PickerItem[]
---@param on_pick? fun(item: nurl.RequestItem)
function M.pick(title, items, on_pick)
    local snacks_items = vim.iter(ipairs(items))
        :map(function(i, item)
            return {
                idx = i,
                score = 1,
                text = item.text,
                value = item.item,
                preview = item.preview,
                file = item.item.file,
                pos = item.item.file
                    and { item.item.start_row, item.item.start_col },
            }
        end)
        :totable()

    Snacks.picker.pick("nurl_requests", {
        title = title,
        items = snacks_items,
        format = format_item,
        confirm = function(picker, item, action)
            picker:close()

            if on_pick == nil then
                actions.jump(picker, item, action)
            else
                on_pick(item.value)
            end
        end,
        preview = function(ctx)
            ctx.preview:set_lines(http_message.render(ctx.item.preview))
            ctx.preview:highlight({ ft = "http" })
        end,
    })
end

return M

local MiniPick = require("mini.pick")
local request_format = require("nurl.core.request_format")
local http_message = require("nurl.ui.http_message")

local M = {}

local ns_id = vim.api.nvim_create_namespace("nurl_mini_pick")

---The line of an item in columns, as in the telescope picker: the method, the
---title or URL, and the file. Titled requests leave the method empty.
---@param item nurl.PickerItem
---@return string line
---@return table[] highlights array of {start_col, end_col, hl_group}
local function format_item(item)
    local request = item.preview

    local columns = {
        { ("%-7s"):format(request.title and "" or request.method), "Function" },
        { request.title or request_format.full_url(request), "Special" },
        { item.item.file, "Comment" },
    }

    local line, highlights = "", {}

    for i, column in ipairs(columns) do
        local text, hl_group = column[1], column[2]

        if text then
            if i > 1 then
                line = line .. " "
            end

            if hl_group then
                table.insert(highlights, { #line, #line + #text, hl_group })
            end

            line = line .. text
        end
    end

    return line, highlights
end

---Show the items as MiniPick does, then highlight their columns under its
---match highlights.
---@param buf_id integer
---@param items table[]
---@param query string[]
local function show(buf_id, items, query)
    MiniPick.default_show(buf_id, items, query)

    vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

    for i, item in ipairs(items) do
        for _, highlight in ipairs(item.highlights) do
            local start_col, end_col, hl_group = unpack(highlight)

            vim.api.nvim_buf_set_extmark(buf_id, ns_id, i - 1, start_col, {
                end_col = end_col,
                hl_group = hl_group,
                priority = 199,
            })
        end
    end
end

---@param buf_id integer
---@param item table
local function preview(buf_id, item)
    local lines = http_message.render(item.preview)
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.bo[buf_id].filetype = "http"
end

---@param title string
---@param items nurl.PickerItem[]
---@param on_pick? fun(item: nurl.RequestItem)
function M.pick(title, items, on_pick)
    local mini_items = vim.iter(items)
        :map(function(item)
            local line, highlights = format_item(item)

            return {
                text = line,
                highlights = highlights,
                value = item.item,
                preview = item.preview,
                path = item.item.file,
                lnum = item.item.start_row,
                col = item.item.start_col and item.item.start_col + 1,
            }
        end)
        :totable()

    MiniPick.start({
        source = {
            name = title,
            items = mini_items,
            show = show,
            preview = preview,
            choose = function(item)
                if on_pick == nil then
                    MiniPick.default_choose(item)
                else
                    -- Let the picker close before the request is sent.
                    vim.schedule(function()
                        on_pick(item.value)
                    end)
                end
            end,
        },
    })
end

return M

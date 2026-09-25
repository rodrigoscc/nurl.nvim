local requests = require("nurl.requests")
local actions = require("snacks.picker.actions")
local preview = require("nurl.preview")

local M = {}

---@param item snacks.picker.Item
---@param picker snacks.Picker
---@return snacks.picker.Highlight[]
local function format_project_request_item(item)
    local ret = {}

    table.insert(ret, { "", "SnacksPickerIcon" })
    table.insert(ret, { " " })

    if item.lazy.title then
        table.insert(ret, { item.lazy.title, "SnacksPickerLabel" })
        table.insert(ret, { " " })
    else
        table.insert(ret, { item.lazy.method, "SnacksPickerFileType" })
        table.insert(ret, { " " })

        table.insert(ret, { requests.full_url(item.lazy), "SnacksPickerLabel" })
        table.insert(ret, { " " })
    end

    table.insert(ret, { item.file, "SnacksPickerDir" })
    table.insert(ret, { " " })

    return ret
end

---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format_request_item(item)
    local ret = {}

    table.insert(ret, { "", "SnacksPickerIcon" })
    table.insert(ret, { " " })

    if item.lazy.title then
        table.insert(ret, { item.lazy.title, "SnacksPickerLabel" })
        table.insert(ret, { " " })
    else
        table.insert(ret, { item.lazy.method, "SnacksPickerFileType" })
        table.insert(ret, { " " })

        table.insert(ret, { requests.full_url(item.lazy), "SnacksPickerLabel" })
        table.insert(ret, { " " })
    end

    return ret
end

---@param super_requests nurl.SuperRequest[]
---@return snacks.picker.Item[]
local function super_requests_to_snacks_items(super_requests)
    return vim.iter(ipairs(super_requests))
        :map(function(i, request)
            local status, expanded =
                pcall(requests.expand, request, { lazy = true })
            if not status then
                vim.notify(
                    ("Skipped request after error: %s"):format(expanded),
                    vim.log.levels.WARN
                )
                return nil -- filter out
            end

            local lazy = requests.stringify_lazy(expanded)

            local item = {
                idx = i,
                text = requests.text(lazy),
                request = expanded,
                lazy = lazy,
                score = 1,
            }

            return item
        end)
        :totable()
end

---@param project_request_items nurl.ProjectRequestItem[]
---@return snacks.picker.Item[]
local function project_request_items_to_snacks_items(project_request_items)
    return vim.iter(ipairs(project_request_items))
        :map(function(i, request_item)
            local status, expanded =
                pcall(requests.expand, request_item.request, { lazy = true })
            if not status then
                vim.notify(
                    ("Skipped request in %s:%s after error: %s"):format(
                        request_item.file,
                        request_item.start_row,
                        expanded
                    ),
                    vim.log.levels.WARN
                )
                return nil -- filter out
            end

            local lazy = requests.stringify_lazy(expanded)

            request_item.request = expanded

            local snacks_item = {
                idx = i,
                item = request_item,
                lazy = lazy,
                score = 1,
                text = requests.text(lazy, { suffix = request_item.file }),
                file = request_item.file,
                pos = { request_item.start_row, request_item.start_col },
            }

            return snacks_item
        end)
        :totable()
end

---@param title string
---@param super_requests nurl.SuperRequest[]
---@param on_pick? fun(request: nurl.SuperRequest)
function M.pick_request(title, super_requests, on_pick)
    local items = super_requests_to_snacks_items(super_requests)

    Snacks.picker.pick("buffer_requests", {
        title = title,
        items = items,
        format = format_request_item,
        confirm = function(picker, item)
            picker:close()
            if on_pick ~= nil then
                on_pick(item.request)
            end
        end,
        preview = function(ctx)
            ctx.preview:set_lines(preview.render(ctx.item.lazy))
            ctx.preview:highlight({ ft = "http" })
        end,
    })
end

---@param title string
---@param project_request_items nurl.ProjectRequestItem[]
---@param on_pick? fun(item: nurl.ProjectRequestItem)
function M.pick_project_request_item(title, project_request_items, on_pick)
    local snacks_items =
        project_request_items_to_snacks_items(project_request_items)

    Snacks.picker.pick("project_requests", {
        title = title,
        items = snacks_items,
        format = format_project_request_item,
        confirm = function(picker, item, action)
            picker:close()

            if on_pick == nil then
                actions.jump(picker, item, action)
            else
                on_pick(item.item)
            end
        end,
        preview = function(ctx)
            ctx.preview:set_lines(preview.render(ctx.item.lazy))
            ctx.preview:highlight({ ft = "http" })
        end,
    })
end

return M

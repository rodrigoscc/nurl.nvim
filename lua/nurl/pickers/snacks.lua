local requests = require("nurl.requests")
local actions = require("snacks.picker.actions")

local M = {}

---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
local function format_history_item(item)
    local ret = {}

    local request, response, curl = unpack(item.item)

    table.insert(ret, { "", "SnacksPickerIcon" })
    table.insert(ret, { " " })

    table.insert(ret, { curl.exec_datetime, "SnacksPickerComment" })
    table.insert(ret, { " " })

    table.insert(ret, { request.method, "SnacksPickerFileType" })
    table.insert(ret, { " " })

    table.insert(ret, { request.url, "SnacksPickerLabel" })
    table.insert(ret, { " " })

    table.insert(ret, { tostring(response.status_code), "SnacksPickerIdx" })

    return ret
end

---@param item snacks.picker.Item
---@param picker snacks.Picker
---@return snacks.picker.Highlight[]
local function format_project_request_item(item, picker)
    local ret = {}

    table.insert(ret, { "", "SnacksPickerIcon" })
    table.insert(ret, { " " })

    table.insert(ret, { item.item.request.method, "SnacksPickerFileType" })
    table.insert(ret, { " " })

    table.insert(ret, { item.item.request.url, "SnacksPickerLabel" })
    table.insert(ret, { " " })

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

    table.insert(ret, { item.request.method, "SnacksPickerFileType" })
    table.insert(ret, { " " })

    table.insert(ret, { item.request.url, "SnacksPickerLabel" })
    table.insert(ret, { " " })

    return ret
end

---@param history_items nurl.HistoryItem[]
---@return snacks.picker.Item[]
local function history_items_to_snacks_items(history_items)
    return vim.iter(ipairs(history_items))
        :map(function(i, item)
            local request, response, curl = unpack(item)

            local preview_json = ""
            if request.data then
                preview_json = vim.json.encode(request.data)
            elseif request.data_urlencode then
                preview_json = vim.json.encode(request.data_urlencode)
            elseif request.form then
                preview_json = vim.json.encode(request.form)
            end

            local snacks_item = {
                idx = i,
                score = 1,
                item = item,
                text = string.format(
                    "%s %s %s %s",
                    curl.exec_datetime,
                    request.method,
                    request.url,
                    response.status_code
                ),
                response = response,
                curl = curl,
                preview = {
                    text = preview_json,
                    ft = "json",
                },
            }

            return snacks_item
        end)
        :totable()
end

---@param super_requests nurl.SuperRequest[]
---@return snacks.picker.Item[]
local function super_requests_to_snacks_items(super_requests)
    return vim.iter(ipairs(super_requests))
        :map(function(i, request)
            local expanded = requests.expand(request)

            local preview_json = ""
            if expanded.data then
                preview_json = vim.json.encode(expanded.data)
            elseif expanded.data_urlencode then
                preview_json = vim.json.encode(expanded.data_urlencode)
            elseif expanded.form then
                preview_json = vim.json.encode(expanded.form)
            end

            local item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = expanded,
                score = 1,
                preview = {
                    text = preview_json,
                    ft = "json",
                },
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
            local expanded = requests.expand(request_item.request)

            local preview_json = ""
            if expanded.data then
                preview_json = vim.json.encode(expanded.data)
            elseif expanded.data_urlencode then
                preview_json = vim.json.encode(expanded.data_urlencode)
            elseif expanded.form then
                preview_json = vim.json.encode(expanded.form)
            end

            request_item.request = expanded

            local snacks_item = {
                idx = i,
                item = request_item,
                score = 1,
                text = expanded.method
                    .. " "
                    .. expanded.url
                    .. " "
                    .. request_item.file,
                preview = {
                    text = preview_json,
                    ft = "json",
                },
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

    Snacks.picker.pick("requests", {
        title = title,
        items = items,
        preview = "preview",
        format = format_request_item,
        formatters = {
            text = {
                ft = "http",
            },
        },
        confirm = function(picker, item)
            picker:close()
            if on_pick ~= nil then
                on_pick(item.request)
            end
        end,
    })
end

---@param title string
---@param project_request_items nurl.ProjectRequestItem[]
---@param on_pick? fun(item: nurl.ProjectRequestItem)
function M.pick_project_request_item(title, project_request_items, on_pick)
    local snacks_items =
        project_request_items_to_snacks_items(project_request_items)

    Snacks.picker.pick("requests", {
        title = title,
        items = snacks_items,
        preview = "preview",
        format = format_project_request_item,
        confirm = function(picker, item, action)
            picker:close()

            if on_pick == nil then
                actions.jump(picker, item, action)
            else
                on_pick(item.item)
            end
        end,
    })
end

---@param title string
---@param history_items nurl.HistoryItem[]
---@param on_pick? fun(item: nurl.HistoryItem)
function M.pick_request_history_item(title, history_items, on_pick)
    local snacks_items = history_items_to_snacks_items(history_items)

    Snacks.picker.pick("requests", {
        title = title,
        items = snacks_items,
        preview = "preview",
        format = format_history_item,
        confirm = function(picker, item)
            picker:close()
            if on_pick ~= nil then
                on_pick(item.item)
            end
        end,
    })
end

return M

local requests = require("nurl.requests")

local M = {}

function M.format_history_item(item)
    local ret = {}

    table.insert(ret, { item.curl.exec_datetime, "SnacksPickerComment" })
    table.insert(ret, { " " })

    table.insert(ret, { item.request.method, "SnacksPickerFileType" })
    table.insert(ret, { " " })

    table.insert(ret, { item.request.url, "SnacksPickerLabel" })
    table.insert(ret, { " " })

    table.insert(
        ret,
        { tostring(item.response.status_code), "SnacksPickerIdx" }
    )

    return ret
end

---@param history_items nurl.HistoryItem[]
function M.history_items_to_snacks_items(history_items)
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
                request = request,
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
function M.super_requests_to_snacks_items(super_requests)
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
                request = request,
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
function M.project_request_items_to_send_snacks_items(project_request_items)
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

            local snacks_item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = request_item.request,
                score = 1,
                preview = {
                    text = preview_json,
                    ft = "json",
                },
            }

            return snacks_item
        end)
        :totable()
end

---@param project_request_items nurl.ProjectRequestItem[]
function M.project_request_items_to_jump_snacks_items(project_request_items)
    return vim.iter(ipairs(project_request_items))
        :map(function(i, item)
            local expanded = requests.expand(item.request)

            local snacks_item = {
                idx = i,
                text = expanded.method .. " " .. expanded.url,
                request = item,
                file = item.file,
                score = 1,
                pos = { item.start_row, item.start_col },
            }

            return snacks_item
        end)
        :totable()
end

return M

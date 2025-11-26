local requests = require("nurl.requests")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")

local M = {}

local function make_request_previewer()
    return previewers.new_buffer_previewer({
        title = "Request Body",
        define_preview = function(self, entry)
            local preview_text = entry.preview_text or ""
            if preview_text ~= "" then
                local lines = vim.split(preview_text, "\n")
                vim.api.nvim_buf_set_lines(
                    self.state.bufnr,
                    0,
                    -1,
                    false,
                    lines
                )
                vim.bo[self.state.bufnr].filetype = "json"
            end
        end,
    })
end

local function get_preview_json(request)
    if request.data then
        return vim.json.encode(request.data)
    elseif request.data_urlencode then
        return vim.json.encode(request.data_urlencode)
    elseif request.form then
        return vim.json.encode(request.form)
    end
    return ""
end

---@param title string
---@param super_requests nurl.SuperRequest[]
---@param on_pick? fun(request: nurl.SuperRequest)
function M.pick_request(title, super_requests, on_pick)
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 1 },
            { width = 7 },
            { remaining = true },
        },
    })

    local make_display = function(entry)
        return displayer({
            { "", "TelescopeResultsIdentifier" },
            { entry.method, "TelescopeResultsFunction" },
            { entry.url, "TelescopeResultsTitle" },
        })
    end

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = super_requests,
                entry_maker = function(request)
                    local expanded = requests.expand(request)
                    return {
                        value = expanded,
                        display = make_display,
                        ordinal = expanded.method .. " " .. expanded.url,
                        method = expanded.method,
                        url = expanded.url,
                        preview_text = get_preview_json(expanded),
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = make_request_previewer(),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection and on_pick then
                        on_pick(selection.value)
                    end
                end)
                return true
            end,
        })
        :find()
end

---@param title string
---@param project_request_items nurl.ProjectRequestItem[]
---@param on_pick? fun(item: nurl.ProjectRequestItem)
function M.pick_project_request_item(title, project_request_items, on_pick)
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 1 },
            { width = 7 },
            { remaining = true },
            { remaining = true },
        },
    })

    local make_display = function(entry)
        return displayer({
            { "", "TelescopeResultsIdentifier" },
            { entry.method, "TelescopeResultsFunction" },
            { entry.url, "TelescopeResultsTitle" },
            { entry.file, "TelescopeResultsComment" },
        })
    end

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = project_request_items,
                entry_maker = function(request_item)
                    local expanded = requests.expand(request_item.request)
                    request_item.request = expanded
                    return {
                        value = request_item,
                        display = make_display,
                        ordinal = expanded.method
                            .. " "
                            .. expanded.url
                            .. " "
                            .. request_item.file,
                        method = expanded.method,
                        url = expanded.url,
                        file = request_item.file,
                        filename = request_item.file,
                        lnum = request_item.start_row,
                        col = request_item.start_col,
                        preview_text = get_preview_json(expanded),
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = make_request_previewer(),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection then
                        if on_pick then
                            on_pick(selection.value)
                        else
                            vim.cmd("edit " .. selection.filename)
                            vim.api.nvim_win_set_cursor(
                                0,
                                { selection.lnum, selection.col + 1 }
                            )
                        end
                    end
                end)
                return true
            end,
        })
        :find()
end

---@param title string
---@param history_items nurl.HistoryItem[]
---@param on_pick? fun(item: nurl.HistoryItem)
function M.pick_request_history_item(title, history_items, on_pick)
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 1 },
            { width = 19 },
            { width = 7 },
            { width = 50 },
            { remaining = true },
        },
    })

    local make_display = function(entry)
        return displayer({
            { "", "TelescopeResultsIdentifier" },
            { entry.datetime, "TelescopeResultsComment" },
            { entry.method, "TelescopeResultsFunction" },
            { entry.url, "TelescopeResultsTitle" },
            { tostring(entry.status_code), "TelescopeResultsConstant" },
        })
    end

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = history_items,
                entry_maker = function(item)
                    local request, response, curl = unpack(item)
                    return {
                        value = item,
                        display = make_display,
                        ordinal = curl.exec_datetime
                            .. " "
                            .. request.method
                            .. " "
                            .. request.url
                            .. " "
                            .. response.status_code,
                        datetime = curl.exec_datetime,
                        method = request.method,
                        url = request.url,
                        status_code = response.status_code,
                        preview_text = get_preview_json(request),
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = make_request_previewer(),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection and on_pick then
                        on_pick(selection.value)
                    end
                end)
                return true
            end,
        })
        :find()
end

return M

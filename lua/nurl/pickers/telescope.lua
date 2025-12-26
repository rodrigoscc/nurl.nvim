local requests = require("nurl.requests")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local projects = require("nurl.projects")
local preview = require("nurl.preview")

local M = {}

local function make_request_previewer()
    return previewers.new_buffer_previewer({
        title = "Request",
        define_preview = function(self, entry)
            local lines = preview.render(entry.request)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "http"
        end,
    })
end

local function make_history_previewer()
    return previewers.new_buffer_previewer({
        title = "Request & Response",
        define_preview = function(self, entry)
            local lines = preview.render(entry.request, entry.response)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "http"
        end,
    })
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
        if entry.request.title then
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { "", "TelescopeResultsFunction" },
                { entry.request.title, "TelescopeResultsTitle" },
            })
        else
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { entry.request.method, "TelescopeResultsFunction" },
                { requests.full_url(entry.request), "TelescopeResultsTitle" },
            })
        end
    end

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = super_requests,
                entry_maker = function(request)
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
                    return {
                        value = expanded,
                        display = make_display,
                        ordinal = requests.text(lazy),
                        request = lazy,
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
        if entry.request.title then
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { "", "TelescopeResultsFunction" },
                { entry.request.title, "TelescopeResultsTitle" },
                { entry.file, "TelescopeResultsComment" },
            })
        else
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { entry.request.method, "TelescopeResultsFunction" },
                { requests.full_url(entry.request), "TelescopeResultsTitle" },
                { entry.file, "TelescopeResultsComment" },
            })
        end
    end

    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = project_request_items,
                entry_maker = function(request_item)
                    local status, expanded = pcall(
                        requests.expand,
                        request_item.request,
                        { lazy = true }
                    )
                    if not status then
                        vim.notify(
                            ("Skipped request in %s:%s after error: %s"):format(
                                request_item.file,
                                request_item.start_row,
                                expanded
                            ),
                            vim.log.levels.WARN
                        )
                        return nil -- fitler out
                    end

                    local lazy = requests.stringify_lazy(expanded)
                    request_item.request = expanded
                    return {
                        value = request_item,
                        display = make_display,
                        ordinal = requests.text(
                            lazy,
                            { suffix = request_item.file }
                        ),
                        request = lazy,
                        file = request_item.file,
                        filename = request_item.file,
                        lnum = request_item.start_row,
                        col = request_item.start_col,
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
                            projects.jump_to(selection.value)
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
        if entry.request.title then
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { entry.curl.exec_datetime, "TelescopeResultsComment" },
                { "", "TelescopeResultsFunction" },
                { entry.request.title, "TelescopeResultsTitle" },
                {
                    tostring(entry.response.status_code),
                    "TelescopeResultsConstant",
                },
            })
        else
            return displayer({
                { "", "TelescopeResultsIdentifier" },
                { entry.curl.exec_datetime, "TelescopeResultsComment" },
                { entry.request.method, "TelescopeResultsFunction" },
                { requests.full_url(entry.request), "TelescopeResultsTitle" },
                {
                    tostring(entry.response.status_code),
                    "TelescopeResultsConstant",
                },
            })
        end
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
                        ordinal = requests.text(request, {
                            prefix = curl.exec_datetime,
                            suffix = response.status_code,
                        }),
                        request = request,
                        response = response,
                        curl = curl,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = make_history_previewer(),
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

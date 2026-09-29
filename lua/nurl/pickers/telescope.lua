local request_format = require("nurl.core.request_format")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local projects = require("nurl.projects")
local http_message = require("nurl.ui.http_message")

local M = {}

local function make_request_previewer()
    return previewers.new_buffer_previewer({
        title = "Request",
        define_preview = function(self, entry)
            local lines = http_message.render(entry.request)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "http"
        end,
    })
end

local displayer = entry_display.create({
    separator = " ",
    items = {
        { width = 1 },
        { width = 7 },
        { remaining = true },
        { remaining = true },
    },
})

local function make_display(entry)
    local file = { entry.file or "", "TelescopeResultsComment" }

    if entry.request.title then
        return displayer({
            { "", "TelescopeResultsIdentifier" },
            { "", "TelescopeResultsFunction" },
            { entry.request.title, "TelescopeResultsTitle" },
            file,
        })
    end

    return displayer({
        { "", "TelescopeResultsIdentifier" },
        { entry.request.method, "TelescopeResultsFunction" },
        { request_format.full_url(entry.request), "TelescopeResultsTitle" },
        file,
    })
end

---@param title string
---@param items nurl.PickerItem[]
---@param on_pick? fun(item: nurl.RequestItem)
function M.pick(title, items, on_pick)
    pickers
        .new({}, {
            prompt_title = title,
            finder = finders.new_table({
                results = items,
                ---@param item nurl.PickerItem
                entry_maker = function(item)
                    return {
                        value = item.item,
                        display = make_display,
                        ordinal = item.text,
                        request = item.preview,
                        file = item.item.file,
                        filename = item.item.file,
                        lnum = item.item.start_row,
                        col = item.item.start_col,
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

return M

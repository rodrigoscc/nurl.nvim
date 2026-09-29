local projects = require("nurl.projects")
local pickers = require("nurl.pickers")
local ResponseView = require("nurl.ui.response_view")

---@class nurl.app.targets
local M = {}

---All the requests of the project.
---@return nurl.ProjectRequestItem[]
function M.project()
    return projects.requests()
end

---The requests of a file.
---@param path string
---@return nurl.ProjectRequestItem[]
function M.file(path)
    return projects.file_requests(vim.fn.expand(path))
end

---@param item nurl.ProjectRequestItem
---@param row integer
---@param col integer
---@return boolean
local function contains(item, row, col)
    return item.start_row ~= nil
        and item.start_row <= row
        and item.end_row >= row
        and (row ~= item.end_row or col < item.end_col)
        and (row ~= item.start_row or col >= item.start_col)
end

---The request under the cursor: the one shown in a response window, or the
---one defined at the cursor in a request file.
---@return nurl.RequestItem?
function M.cursor()
    local view = ResponseView.for_buf(vim.api.nvim_get_current_buf())
    if view then
        return { request = view.handle.request, win = view.win }
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    for _, item in ipairs(M.file(vim.fn.expand("%"))) do
        if contains(item, row, col) then
            return item
        end
    end
end

---Act on the only item, or pick one. Without on_choose, jump to it.
---@param title string
---@param items nurl.RequestItem[]
---@param on_choose? fun(item: nurl.RequestItem)
function M.choose(title, items, on_choose)
    if #items == 1 then
        (on_choose or projects.jump_to)(items[1])
    else
        pickers.pick(title, items, on_choose)
    end
end

return M

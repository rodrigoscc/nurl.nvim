local config = require("nurl.config")

local M = {}

---@enum nurl.BufferType
M.Buffer = {
    Body = "body",
    Headers = "headers",
    Info = "info",
    Raw = "raw",
    Request = "request",
    Test = "test",
}

---@class nurl.BufferAction
---@field [1] string
---@field opts table

---@class nurl.Buffer
---@field [1] nurl.BufferType
---@field keys table<string, string|nurl.BufferAction>

---Renders one part of a request into its buffer. Parts that need the response
---leave the buffer empty until the request is done.
---@class nurl.Tab
---@field render fun(bufnr: integer, handle: nurl.RequestHandle)

---@type table<nurl.BufferType, nurl.Tab>
local tabs = {
    body = require("nurl.ui.response_view.tabs.body"),
    headers = require("nurl.ui.response_view.tabs.headers"),
    info = require("nurl.ui.response_view.tabs.info"),
    raw = require("nurl.ui.response_view.tabs.raw"),
    request = require("nurl.ui.response_view.tabs.request"),
    test = require("nurl.ui.response_view.tabs.test"),
}

---@param bufnr integer
---@param type nurl.BufferType
---@param handle nurl.RequestHandle
local function render(bufnr, type, handle)
    if vim.api.nvim_buf_is_valid(bufnr) then
        tabs[type].render(bufnr, handle)
    end
end

---Create a buffer for every configured part of the request.
---@param handle nurl.RequestHandle
---@return table<nurl.BufferType, integer>
function M.create(handle)
    ---@type table<nurl.BufferType, integer>
    local buffers = {}

    for _, buffer in ipairs(config.buffers) do
        local type = buffer[1]
        local bufnr = vim.api.nvim_create_buf(false, true)
        buffers[type] = bufnr
        render(bufnr, type, handle)
    end

    return buffers
end

---Render the buffers again, such as once the request is done.
---@param handle nurl.RequestHandle
---@param buffers table<nurl.BufferType, integer>
function M.update(handle, buffers)
    for type, bufnr in pairs(buffers) do
        render(bufnr, type, handle)
    end
end

return M

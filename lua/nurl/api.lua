local client = require("nurl.app.client")
local commands = require("nurl.commands")
local environments = require("nurl.environments")
local winbar = require("nurl.ui.response_view.winbar")
local variables = require("nurl.core.variables")
local helpers = require("nurl.helpers")
local convert = require("nurl.convert")

---The public API, available as require("nurl") and the Nurl global.
local M = {}

M.winbar = winbar

M.lazy = variables.lazy

M.env = environments

M.helpers = helpers

M.json_to_lua = convert.json_to_lua

M.lua_to_json = convert.lua_to_json

M.send = client.send

M.get_request = client.request_in

---@param index? integer position from the end, -1 being the last
---@param overrides? nurl.Override[]
function M.resend_last_request(index, overrides)
    client.resend(index, overrides)
end

M.pick_resend = commands.pick_resend

---@param overrides? nurl.Override[]
function M.send_project_request(overrides)
    commands.send(nil, overrides)
end

---@param filepath string
---@param overrides? nurl.Override[]
function M.send_file_request(filepath, overrides)
    commands.send(filepath, overrides)
end

---@param overrides? nurl.Override[]
function M.send_request_at_cursor(overrides)
    commands.send(".", overrides)
end

---@param overrides? nurl.Override[]
function M.yank_project_request(overrides)
    commands.yank(nil, overrides)
end

---@param filepath string
---@param overrides? nurl.Override[]
function M.yank_file_request(filepath, overrides)
    commands.yank(filepath, overrides)
end

---@param overrides? nurl.Override[]
function M.yank_curl_at_cursor(overrides)
    commands.yank(".", overrides)
end

function M.jump_to_project_request()
    commands.jump(nil)
end

---@param filepath string
function M.jump_to_file_request(filepath)
    commands.jump(filepath)
end

M.pick_env = commands.pick_env

M.activate_env = commands.activate_env

M.open_environments_file = commands.open_environments_file

function M.get_active_env()
    return environments.project_active_env
end

M.pick_history = commands.pick_history

return M

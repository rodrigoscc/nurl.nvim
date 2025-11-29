local uv = vim.uv or vim.loop
local Spinner = require("nurl.ui.spinner")

local elapsed_time_ns = vim.api.nvim_create_namespace("nurl.elapsed-time")

local FLOAT_WIDTH = 10
local FLOAT_HEIGHT = 1

---@class nurl.ElapsedTimeFloating
---@field private bufnr integer | nil
---@field private win integer | nil
---@field private ref_win integer
---@field private spinner Spinner
---@field private spinner_extmark_id integer | nil
---@field private seconds_extmark_id integer | nil
---@field private start_time_ns number | nil
---@field private timer uv.uv_timer_t | nil
local E = {}

function E:new(ref_win)
    local o = {
        bufnr = nil,
        win = nil,
        ref_win = ref_win,
        spinner = Spinner:new(),
        spinner_extmark_id = nil,
        seconds_extmark_id = nil,
    }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@private
---@return { row: number, col: number }
function E:_get_centered_position()
    local height = vim.api.nvim_win_get_height(self.ref_win)
    local width = vim.api.nvim_win_get_width(self.ref_win)

    return {
        row = (height / 2) - (FLOAT_HEIGHT / 2),
        col = (width / 2) - (FLOAT_WIDTH / 2),
    }
end

function E:start()
    self.bufnr = vim.api.nvim_create_buf(true, true)

    local pos = self:_get_centered_position()
    self.win = vim.api.nvim_open_win(self.bufnr, false, {
        focusable = false,
        relative = "win",
        win = self.ref_win,
        row = pos.row,
        col = pos.col,
        width = FLOAT_WIDTH,
        height = FLOAT_HEIGHT,
    })

    self.timer = uv.new_timer()
    assert(self.timer ~= nil, "Timer must be created")

    self.start_time_ns = uv.hrtime()

    self.timer:start(0, 50, function()
        local current_time_ns = uv.hrtime()
        local seconds =
            string.format("%.2f", (current_time_ns - self.start_time_ns) / 1e9)

        vim.schedule(function()
            if not vim.api.nvim_win_is_valid(self.ref_win) then
                self:stop()
                return
            end

            if not vim.api.nvim_win_is_valid(self.win) then
                return
            end

            local new_pos = self:_get_centered_position()
            vim.api.nvim_win_set_config(self.win, {
                relative = "win",
                win = self.ref_win,
                row = new_pos.row,
                col = new_pos.col,
            })

            local frame = self.spinner:frame()
            local unit = seconds .. "s"

            vim.api.nvim_buf_set_lines(
                self.bufnr,
                0,
                -1,
                true,
                { frame .. " " .. unit }
            )

            self.spinner_extmark_id = vim.api.nvim_buf_set_extmark(
                self.bufnr,
                elapsed_time_ns,
                0,
                0,
                {
                    end_col = #frame,
                    hl_group = "Number",
                    id = self.spinner_extmark_id,
                }
            )

            self.seconds_extmark_id = vim.api.nvim_buf_set_extmark(
                self.bufnr,
                elapsed_time_ns,
                0,
                #frame + 1,
                {
                    end_col = #frame + 1 + #unit,
                    hl_group = "LineNr",
                    id = self.seconds_extmark_id,
                }
            )
        end)
    end)
end

function E:stop()
    assert(self.timer ~= nil, "Timer must be created")
    assert(self.win ~= nil, "Window must be opened")

    self.timer:stop()

    vim.schedule(function()
        if vim.api.nvim_win_is_valid(self.win) then -- win could already be closed
            vim.api.nvim_win_close(self.win, true)
        end

        if vim.api.nvim_buf_is_valid(self.bufnr) then
            vim.api.nvim_buf_delete(self.bufnr, { force = true })
        end
    end)
end

return E

local Spinner = require("nurl.spinner")

local elapsed_time_ns = vim.api.nvim_create_namespace("nurl.elapsed-time")

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
E.__index = E

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

function E:start()
    local height = vim.api.nvim_win_get_height(self.ref_win)
    local width = vim.api.nvim_win_get_width(self.ref_win)

    self.bufnr = vim.api.nvim_create_buf(true, true)

    self.win = vim.api.nvim_open_win(self.bufnr, false, {
        focusable = false,
        relative = "win",
        win = self.ref_win,
        row = (height / 2) - 1,
        col = (width / 2) - 1 - 5,
        width = 24,
        height = 1,
    })

    self.timer = vim.uv.new_timer()
    assert(self.timer ~= nil, "Timer must be created")

    self.start_time_ns = vim.uv.hrtime()

    self.timer:start(0, 50, function()
        local current_time_ns = vim.uv.hrtime()
        local seconds =
            string.format("%.2f", (current_time_ns - self.start_time_ns) / 1e9)

        vim.schedule(function()
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

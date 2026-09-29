local M = {}

---Keymap actions for the response buffers. Each takes the view whose buffers
---it is mapped in, and its options from the config, and returns the mapping.
---@type table<string, fun(view: nurl.ResponseView, opts?: table): fun()>
M.builtin = {
    next_buffer = function(view)
        return function()
            view:cycle(vim.api.nvim_get_current_win(), 1)
        end
    end,
    previous_buffer = function(view)
        return function()
            view:cycle(vim.api.nvim_get_current_win(), -1)
        end
    end,
    switch_buffer = function(view, opts)
        return function()
            view:switch(vim.api.nvim_get_current_win(), opts.buffer)
        end
    end,
    rerun = function(view)
        return function()
            local focus_buffer =
                view:type_of(vim.api.nvim_win_get_buf(view.win))

            require("nurl").send(view.handle.request, {
                display = {
                    win = view.win,
                    -- Focus the active buffer after resending request.
                    -- Useful to run tests again.
                    focus_buffer = focus_buffer,
                },
            })
        end
    end,
    close = function()
        return function()
            vim.cmd.close()
        end
    end,
    cancel = function(view)
        return function()
            view.handle:cancel("sigterm")
        end
    end,
    toggle_secondary = function(view, opts)
        opts = vim.tbl_deep_extend("force", {
            buffer = "info",
            win_config = { split = "below", height = 10, style = "minimal" },
        }, opts or {})

        return function()
            view:toggle_secondary(opts.buffer, opts.win_config)
        end
    end,
}

return M

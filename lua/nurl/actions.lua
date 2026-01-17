local M = {}

M.builtin = {
    ---@param opts? table
    ---@return fun()
    next_buffer = function(_)
        return function()
            local config = require("nurl.config")
            local registry = require("nurl.registry")

            local buffer_index = vim.iter(config.buffers)
                :enumerate()
                :filter(function(_, buffer)
                    return buffer[1] == vim.b.nurl_data.buffer_type
                end)
                :map(function(i)
                    return i
                end)
                :next()

            if buffer_index == nil then
                return
            end

            local next_buffer_index = buffer_index % #config.buffers + 1

            local next_buffer_type = config.buffers[next_buffer_index][1]
            assert(next_buffer_type, "Next response buffer missing")

            local entry = registry:get(vim.b.nurl_data.handle_id)
            local next_buffer = entry.buffers[next_buffer_type]

            if next_buffer == nil then
                return
            end

            vim.api.nvim_win_set_buf(
                vim.api.nvim_get_current_win(),
                next_buffer
            )
        end
    end,
    ---@param opts? table
    ---@return fun()
    previous_buffer = function(_)
        return function()
            local config = require("nurl.config")
            local registry = require("nurl.registry")

            local buffer_index = vim.iter(config.buffers)
                :enumerate()
                :filter(function(_, buffer)
                    return buffer[1] == vim.b.nurl_data.buffer_type
                end)
                :map(function(i)
                    return i
                end)
                :next()

            if buffer_index == nil then
                return
            end

            local previous_buffer_index = (buffer_index - 2) % #config.buffers
                + 1

            local previous_buffer_type =
                config.buffers[previous_buffer_index][1]
            assert(previous_buffer_type, "Previous response buffer missing")

            local entry = registry:get(vim.b.nurl_data.handle_id)
            local previous_buffer = entry.buffers[previous_buffer_type]

            if previous_buffer == nil then
                return
            end

            vim.api.nvim_win_set_buf(
                vim.api.nvim_get_current_win(),
                previous_buffer
            )
        end
    end,
    ---@param opts? table
    ---@return fun()
    switch_buffer = function(opts)
        return function()
            local registry = require("nurl.registry")

            local entry = registry:get(vim.b.nurl_data.handle_id)
            local new_buffer = entry.buffers[opts.buffer]
            if new_buffer == nil then
                return
            end

            vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), new_buffer)
        end
    end,
    ---@param opts? table
    ---@return fun()
    rerun = function(_)
        return function()
            local nurl = require("nurl")
            local registry = require("nurl.registry")

            local entry = registry:get(vim.b.nurl_data.handle_id)
            nurl.send(entry.handle.request, {
                display = {
                    win = vim.api.nvim_get_current_win(),
                    -- Focus the active buffer after resending request.
                    -- Useful to run tests again.
                    focus_buffer = vim.b.nurl_data.buffer_type,
                },
            })
        end
    end,
    ---@param opts? table
    ---@return fun()
    close = function(_)
        return function()
            vim.cmd.close()
        end
    end,
    ---@param opts? table
    ---@return fun()
    cancel = function(_)
        return function()
            local registry = require("nurl.registry")

            local entry = registry:get(vim.b.nurl_data.handle_id)

            entry.handle:cancel("sigterm")
        end
    end,
    ---@param opts? table
    ---@return fun()
    toggle_secondary = function(opts)
        local Buffer = require("nurl.ui.buffers").Buffer
        local registry = require("nurl.registry")

        local default_opts = {
            buffer = Buffer.Info,
            win_config = { split = "below", height = 10, style = "minimal" },
        }

        opts = vim.tbl_deep_extend(
            "force",
            {},
            vim.deepcopy(default_opts),
            opts or {}
        )

        local secondary_window = nil

        return function()
            local entry = registry:get(vim.b.nurl_data.handle_id)
            local SecondaryWindow = require("nurl.ui.seconday_window")

            if secondary_window == nil then
                secondary_window = SecondaryWindow:new({
                    buffers = entry.buffers,
                    win_config = opts.win_config,
                })
            end

            secondary_window:toggle(opts.buffer)
        end
    end,
}

return M

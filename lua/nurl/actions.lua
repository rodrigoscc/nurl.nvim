local M = {}

M.builtin = {
    ---@param opts? table
    ---@return fun()
    next_buffer = function(_)
        return function()
            local config = require("nurl.config")

            local buffer_index = vim.iter(config.buffers)
                :enumerate()
                :filter(function(_, buffer)
                    return buffer[1] == vim.b.nurl_buffer_type
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

            local next_buffer = vim.b.nurl_buffers[next_buffer_type]

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

            local buffer_index = vim.iter(config.buffers)
                :enumerate()
                :filter(function(_, buffer)
                    return buffer[1] == vim.b.nurl_buffer_type
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

            local previous_buffer = vim.b.nurl_buffers[previous_buffer_type]

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
            local new_buffer = vim.b.nurl_buffers[opts.buffer]
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
            nurl.send(
                vim.b.nurl_request,
                { win = vim.api.nvim_get_current_win() }
            )
        end
    end,
    ---@param opts? table
    ---@return fun()
    close = function(_)
        return function()
            vim.cmd.close()
        end
    end,
}

return M

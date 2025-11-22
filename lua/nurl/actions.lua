local M = {}

M.builtin = {
    next_buffer = function(opts)
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
    switch_buffer = function(opts)
        return function()
            local new_buffer = vim.b.nurl_buffers[opts.buffer]
            if new_buffer == nil then
                return
            end

            vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), new_buffer)
        end
    end,
    rerun = function(opts)
        return function()
            Nurl.send(vim.b.nurl_request)
        end
    end,
    close = function(opts)
        return function()
            vim.cmd.close()
        end
    end,
}

return M

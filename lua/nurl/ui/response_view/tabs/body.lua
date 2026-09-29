local config = require("nurl.config")
local responses = require("nurl.responses")

local M = {}

---@param bufnr integer
---@param content string
---@param file_type string
local function set_body_buffer(bufnr, content, file_type)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local lines = vim.split(content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.api.nvim_set_option_value("filetype", file_type, { buf = bufnr })
end

local function open_file_in_buffer(bufnr, file)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local existing_buffer = vim.fn.bufnr(file)
    if existing_buffer ~= -1 then
        -- Specially important for when the user opens a request in history which buffers are still open.
        vim.api.nvim_buf_delete(existing_buffer, { force = true })
    end

    vim.api.nvim_buf_set_name(bufnr, file)
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit") -- WORKAROUND: Snacks.image won't render the file without this
    end)
    -- above :edit lists the buffer, so mark it as unlisted again.
    vim.bo[bufnr].buflisted = false
end

---The response body, formatted for its content type. A body saved to a file
---is opened from the file.
---@param bufnr integer
---@param handle nurl.RequestHandle
function M.render(bufnr, handle)
    local response = handle.response
    if response == nil then
        return
    end

    if response.body_file then
        vim.schedule(function()
            open_file_in_buffer(bufnr, response.body_file)
        end)
        return
    end

    local file_type = responses.guess_file_type(response.headers)
    local formatter = config.formatters[file_type]

    if
        formatter ~= nil
        and (formatter.available == nil or formatter.available())
    then
        vim.system(
            formatter.cmd,
            { text = true, stdin = response.body },
            function(out)
                vim.schedule(function()
                    local content
                    if out.code == 0 then
                        content = vim.trim(out.stdout) or ""
                    else
                        content = response.body
                        vim.notify(
                            ('Formatter "%s" for "%s" failed: %s\n%s'):format(
                                formatter.cmd[1],
                                file_type,
                                out.stdout,
                                out.stderr
                            ),
                            vim.log.levels.ERROR
                        )
                    end

                    set_body_buffer(bufnr, content, file_type)
                end)
            end
        )
    else
        vim.schedule(function()
            set_body_buffer(bufnr, response.body, file_type)
        end)
    end
end

return M

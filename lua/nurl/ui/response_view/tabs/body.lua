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

---@param bufnr integer
---@param file string
local function open_file_in_buffer(bufnr, file)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if vim.api.nvim_buf_get_name(bufnr) ~= "" then
        -- Tabs may be rendered again, and this buffer already shows the file:
        -- it is created without a name and only named here.
        return
    end

    if vim.fn.bufexists(file) == 1 then
        -- Buffer names are unique, so this buffer cannot be named after the
        -- file while another one is: another window showing the same response
        -- from history, or the file opened by the user. Taking the name would
        -- mean deleting that buffer, which closes the windows showing it, so
        -- show where the body is instead.
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, {
            "[Body saved to file: " .. file .. "]",
        })
        return
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

---@class nurl.config: nurl.Config
local M = {}

---@class nurl.Config
local defaults = {
    dir = ".nurl",
    environments_file = "environments.lua",
    active_environments_file = vim.fn.stdpath("data") .. "/nurl/envs.json",
    history = {
        ---@type boolean
        enabled = true,
        ---@type string
        db_file = vim.fn.stdpath("data") .. "/nurl/history.sqlite3",
    },
    ---Window config for the response window. Refer to :help nvim_open_win for the available keys.
    ---@type table
    win_config = { split = "right" },
    ---@type nurl.Buffer[]
    buffers = {
        {
            "body",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "headers",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "info",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "raw",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
    },
    highlight = {
        groups = {
            spinner = "NurlSpinner",
            elapsed_time = "NurlElapsedTime",
            winbar_tab_active = "NurlWinbarTabActive",
            winbar_tab_inactive = "NurlWinbarTabInactive",
            winbar_success_status_code = "NurlWinbarSuccessStatusCode",
            winbar_error_status_code = "NurlWinbarErrorStatusCode",
            winbar_loading = "NurlWinbarLoading",
            winbar_time = "NurlWinbarTime",
            winbar_error = "NurlWinbarError",
        },
    },
}

local config = vim.deepcopy(defaults) --[[@as nurl.Config]]

---@param opts? nurl.Config
function M.setup(opts)
    config =
        vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})
end

setmetatable(M, {
    __index = function(_, key)
        return config[key]
    end,
})

return M

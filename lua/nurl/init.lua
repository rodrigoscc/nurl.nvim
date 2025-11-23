local M = {}

---@param opts? nurl.Config
function M.setup(opts)
    require("nurl.config").setup(opts)
    require("nurl.highlights").setup_highlights()
    require("nurl.environments").load()
    require("nurl.environments").setup_reload_autocmd()
end

return M

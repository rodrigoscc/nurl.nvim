local M = {}

---@param opts? nurl.Config
function M.setup(opts)
    require("nurl.config").setup(opts)
    require("nurl.highlights").setup_highlights()
end

return M

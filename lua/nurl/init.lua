local M = {}

---@param opts? nurl.Config
function M.setup(opts)
    require("nurl.config").setup(opts)
end

return M

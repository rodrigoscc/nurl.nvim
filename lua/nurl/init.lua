---@class nurl.api
local M = {}

_G.Nurl = M

---@param opts? nurl.Config
function M.setup(opts)
    require("nurl.config").setup(opts)
    require("nurl.highlights").setup_highlights()
    require("nurl.environments").load()
    require("nurl.environments").setup_reload_autocmd()
    require("nurl.commands").setup()
end

-- Lazy-load nurl.nurl on first access to any key.
-- Caches the key on M so subsequent accesses are direct.
setmetatable(M, {
    __index = function(t, key)
        local nurl = require("nurl.nurl")
        if nurl[key] ~= nil then
            t[key] = nurl[key]
            return t[key]
        end
    end,
})

return M

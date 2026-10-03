-- Neovim config of the demo, started by demo.tape from demo/project.

local demo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

vim.opt.rtp:prepend(demo .. "/.deps/rose-pine")
vim.opt.rtp:prepend(demo .. "/.deps/snacks.nvim")
vim.opt.rtp:prepend(vim.fs.dirname(demo))
-- Tree-sitter parsers installed for the user's Neovim, if any, such as json
-- and http, to highlight responses.
if vim.env.NURL_DEMO_SITE then
    vim.opt.rtp:append(vim.env.NURL_DEMO_SITE)
end

vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = "no"
vim.o.laststatus = 0
-- Splits still draw a statusline between them: keep it blank.
vim.o.statusline = " "
vim.o.showtabline = 0
vim.o.wrap = false
vim.o.showmode = false
vim.o.ruler = false
vim.o.swapfile = false
vim.o.splitright = true
vim.opt.shortmess:append("I")
vim.opt.fillchars = { eob = " " }

require("rose-pine").setup({ styles = { italic = false } })
vim.cmd.colorscheme("rose-pine")

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "json", "http", "lua" },
    callback = function()
        pcall(vim.treesitter.start)
    end,
})

require("snacks").setup({
    picker = { enabled = true, ui_select = true },
    notifier = { enabled = true },
})

require("nurl").setup({ trust = { enabled = false } })
Nurl.activate_env("development")

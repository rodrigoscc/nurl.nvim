local M = {}

M.highlights = {
    NurlSpinner = "@constant",
    NurlElapsedTime = "@comment",
    NurlWinbarTitle = "@attribute",
    NurlWinbarTabActive = "@comment.info",
    NurlWinbarTabInactive = "@comment",
    NurlWinbarSuccessStatusCode = "@diff.plus",
    NurlWinbarErrorStatusCode = "@diff.minus",
    NurlWinbarLoading = "@constructor",
    NurlWinbarTime = "@comment",
    NurlWinbarError = "Error",
}

function M.setup_highlights()
    for highlight, opts in pairs(M.highlights) do
        if type(opts) == "string" then
            vim.api.nvim_set_hl(0, highlight, { link = opts, default = true })
        else
            vim.api.nvim_set_hl(0, highlight, opts)
        end
    end
end

return M

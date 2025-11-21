local M = {}

M.highlights = {
    NurlSpinner = "@constant",
    NurlElapsedTime = "@comment",
    NurlWinbarTabActive = "@comment.info",
    NurlWinbarTabInactive = "@comment",
    NurlWinbarSuccessStatusCode = "@diff.plus",
    NurlWinbarErrorStatusCode = "@diff.minus",
    NurlWinbarLoading = "@constructor",
    NurlWinbarTime = "@comment",
}

function M.setup_highlights()
    for highlight, link in pairs(M.highlights) do
        vim.api.nvim_set_hl(0, highlight, { link = link })
    end
end

return M

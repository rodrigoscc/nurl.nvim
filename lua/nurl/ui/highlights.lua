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
    NurlWinbarWarning = "WarningMsg",
    NurlWinbarError = "ErrorMsg",

    NurlInfoTitle = "Title",
    NurlInfoSubtitle = "@markup.heading",
    NurlInfoSectionTitle = "@markup.heading.2",
    NurlInfoSeparator = "NonText",
    NurlInfoIcon = "Special",
    NurlInfoLabel = "Comment",
    NurlInfoValue = "Normal",
    NurlInfoHighlight = "@markup.strong",
    NurlInfoUrl = "@markup.link.url",
    NurlInfoQueryKey = "@property",
    NurlInfoQueryValue = "@string",

    NurlInfoMethod = "@keyword",
    NurlInfoMethodGet = "@diff.plus",
    NurlInfoMethodPost = "@diff.change",
    NurlInfoMethodPut = "@diff.change",
    NurlInfoMethodPatch = "@diff.change",
    NurlInfoMethodDelete = "@diff.minus",
    NurlInfoMethodHead = "@comment",
    NurlInfoMethodOptions = "@comment",

    NurlInfoStatus = "Normal",
    NurlInfoStatusSuccess = "@diff.plus",
    NurlInfoStatusRedirect = "@diff.change",
    NurlInfoStatusClientError = "@diff.minus",
    NurlInfoStatusServerError = "@diff.minus",
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

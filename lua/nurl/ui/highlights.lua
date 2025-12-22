local M = {}

M.highlights = {
    NurlSpinner = "@constant",
    NurlElapsedTime = "@comment",
    NurlWinbarTitle = "@attribute",
    NurlWinbarTabActive = "Special",
    NurlWinbarTabInactive = "@comment",
    NurlWinbarSuccessStatusCode = "DiagnosticOk",
    NurlWinbarErrorStatusCode = "DiagnosticError",
    NurlWinbarLoading = "DiagnosticInfo",
    NurlWinbarTime = "@comment",
    NurlWinbarWarning = "DiagnosticWarn",
    NurlWinbarError = "DiagnosticError",

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

    NurlInfoMethod = "Special",

    NurlInfoStatus = "Normal",
    NurlInfoStatusSuccess = "DiagnosticOk",
    NurlInfoStatusRedirect = "DiagnosticInfo",
    NurlInfoStatusClientError = "DiagnosticError",
    NurlInfoStatusServerError = "DiagnosticError",
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

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
    NurlInfoSeparator = "NonText",
    NurlInfoIcon = "Special",
    NurlInfoSection = "@markup.heading",
    NurlInfoLabel = "NonText",
    NurlInfoValue = "Normal",
    NurlInfoHighlight = "@markup.strong",
    NurlInfoTimingBar = "DiagnosticInfo",
    NurlInfoUrl = "@markup.link.url",
    NurlInfoQueryKey = "@property",
    NurlInfoQueryValue = "@string",

    NurlInfoMethod = "Function",

    NurlInfoStatus = "Normal",
    NurlInfoStatusSuccess = "DiagnosticOk",
    NurlInfoStatusRedirect = "DiagnosticInfo",
    NurlInfoStatusClientError = "DiagnosticError",
    NurlInfoStatusServerError = "DiagnosticError",

    NurlTestPass = "DiagnosticOk",
    NurlTestFail = "DiagnosticError",
    NurlTestError = "Exception",
    NurlTestLabel = "Comment",
    NurlTestValueActual = "DiffDelete",
    NurlTestValueExpected = "DiffAdd",
    NurlTestSuiteName = "@markup.strong",
    NurlTestSeparator = "NonText",
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

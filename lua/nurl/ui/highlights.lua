local config = require("nurl.config")

local M = {}

M.highlights = {
    NurlSpinner = "@constant",
    NurlElapsedTime = "@comment",
    NurlWinbarTitle = "@attribute",
    NurlWinbarTabActive = "Special",
    NurlWinbarTabInactive = "@comment",
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

    -- Status codes, shared by every view.
    NurlStatus = "Normal",
    NurlStatusSuccess = "DiagnosticOk",
    NurlStatusRedirect = "DiagnosticInfo",
    NurlStatusClientError = "DiagnosticError",
    NurlStatusServerError = "DiagnosticError",

    NurlHistoryTime = "Comment",
    NurlHistoryMethod = "Function",
    NurlHistoryDuration = "Comment",
    NurlHistoryTitle = "Title",
    NurlHistoryUrl = "Normal",
    NurlHistoryMatch = "Search",

    NurlTestPass = "DiagnosticOk",
    NurlTestFail = "DiagnosticError",
    NurlTestError = "Exception",
    NurlTestLabel = "Comment",
    NurlTestValueActual = "DiffDelete",
    NurlTestValueExpected = "DiffAdd",
    NurlTestSuiteName = "@markup.strong",
    NurlTestSeparator = "NonText",
}

---Highlight group for a status code, used wherever one is shown.
---@param status_code integer
---@return string
function M.status_group(status_code)
    local groups = config.highlight.groups
    if status_code >= 200 and status_code < 300 then
        return groups.status_success
    elseif status_code >= 300 and status_code < 400 then
        return groups.status_redirect
    elseif status_code >= 400 and status_code < 500 then
        return groups.status_client_error
    elseif status_code >= 500 then
        return groups.status_server_error
    end
    return groups.status
end

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

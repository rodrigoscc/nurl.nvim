local RequestHandle = require("nurl.app.handle")
local info_tab = require("nurl.ui.response_view.tabs.info")

describe("certificate in the info buffer", function()
    before_each(function()
        require("nurl").setup({})
    end)

    ---Seconds since the epoch, an hour past the given number of days from now,
    ---so that rendering a moment later still counts the same days.
    ---@param days integer negative for the past
    ---@return integer
    local function in_days(days)
        return os.time() + days * 86400 + (days < 0 and -3600 or 3600)
    end

    ---@param tls? nurl.ResponseTls
    ---@return string text, integer bufnr
    local function render(tls)
        local bufnr = vim.api.nvim_create_buf(false, true)
        info_tab.render(
            bufnr,
            RequestHandle:rebuild(
                "2026-09-26T10:00:00",
                { method = "GET", url = "https://example.com", headers = {} },
                {
                    status_code = 200,
                    reason_phrase = "OK",
                    protocol = "HTTP/2",
                    headers = {},
                    body = "",
                    time = {},
                    size = {},
                    speed = {},
                    tls = tls,
                }
            )
        )

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        return table.concat(lines, "\n"), bufnr
    end

    ---@param bufnr integer
    ---@param text string
    ---@return string? hl_group of the text
    local function hl_group_of(bufnr, text)
        local ns = vim.api.nvim_get_namespaces()["nurl.info"]
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        for row, line in ipairs(lines) do
            local col = line:find(text, 1, true)
            if col then
                local marks = vim.api.nvim_buf_get_extmarks(
                    bufnr,
                    ns,
                    { row - 1, col - 1 },
                    { row - 1, col - 1 },
                    { details = true, overlap = true }
                )
                for _, mark in ipairs(marks) do
                    -- The label's mark ends where the value starts.
                    if mark[3] == col - 1 then
                        return mark[4].hl_group
                    end
                end
            end
        end
    end

    local chain = {
        {
            subject = "CN = example.com",
            common_name = "example.com",
            issuer = "C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
            san = "DNS:example.com, DNS:*.example.com",
            start_date = "Sep 26 22:49:11 2026 GMT",
            expire_date = "Dec 25 22:56:35 2026 GMT",
            expires_at = in_days(80),
        },
        {
            subject = "C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
            common_name = "Cloudflare TLS Issuing ECC CA 3",
        },
    }

    it("shows the server certificate", function()
        local text = render({ verify_result = 0, certs = chain })

        assert.matches("Certificate", text)
        assert.matches("verify%s+ok", text)
        assert.matches("subject%s+CN = example.com", text)
        assert.matches("names%s+example.com, %*.example.com", text)
        assert.matches("issuer%s+C = US, O = SSL Corporation", text)
        assert.matches("valid from%s+Sep 26 22:49:11 2026 GMT", text)
        assert.matches("expires%s+Dec 25 22:56:35 2026 GMT%s+in 80 days", text)
    end)

    it("lists the chain by common name", function()
        local text = render({ verify_result = 0, certs = chain })

        assert.matches(
            "chain%s+example.com\n%s+Cloudflare TLS Issuing ECC CA 3",
            text
        )
    end)

    it("shows why an insecure request was not verified", function()
        local text, bufnr = render({
            verify_result = 18,
            verify_reason = "self-signed certificate",
            certs = chain,
        })

        assert.matches("verify%s+not verified: self%-signed certificate", text)
        assert.are.equal("NurlInfoError", hl_group_of(bufnr, "not verified"))
    end)

    it("warns about a certificate expiring soon", function()
        local text, bufnr = render({
            verify_result = 0,
            certs = {
                { expire_date = "Oct 4 2026", expires_at = in_days(5) },
            },
        })

        assert.matches("in 5 days", text)
        assert.are.equal("NurlInfoWarning", hl_group_of(bufnr, "Oct 4 2026"))
    end)

    it("marks an expired certificate", function()
        local text, bufnr = render({
            verify_result = 10,
            verify_reason = "certificate has expired",
            certs = {
                { expire_date = "Sep 26 2026", expires_at = in_days(-3) },
            },
        })

        assert.matches("expired 3 days ago", text)
        assert.are.equal("NurlInfoError", hl_group_of(bufnr, "Sep 26 2026"))
    end)

    it("shows a date in an unknown format as it is", function()
        local text = render({
            verify_result = 0,
            certs = { { expire_date = "someday" } },
        })

        assert.matches("expires%s+someday\n", text .. "\n")
        assert.is_nil(text:find(" in ", 1, true))
    end)

    it("has no certificate section without TLS", function()
        local text = render(nil)

        assert.is_nil(text:find("Certificate", 1, true))
    end)
end)

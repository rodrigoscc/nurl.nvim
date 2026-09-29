local certificate = require("nurl.core.certificate")

-- Trimmed from curl's %{certs} output with OpenSSL.
local CERTS = table.concat({
    "Subject:CN = example.com",
    "Issuer:C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
    "Version:2",
    "Authority Information Access:CA Issuers - URI:http://i.cf-i.ssl.com/c.cer",
    "OCSP - URI:http://o.cf-i.ssl.com",
    "X509v3 Subject Alternative Name:DNS:example.com, DNS:*.example.com",
    "Start date:Sep 26 22:49:11 2026 GMT",
    "Expire date:Dec 25 22:56:35 2026 GMT",
    "Cert:-----BEGIN CERTIFICATE-----",
    "MIIDmzCCA0GgAwIBAgIQAe7mqrtSHV4U/DFf2ZhWkDAKBggqhkjOPQQDAjBfMQsw",
    "-----END CERTIFICATE-----",
    "Subject:C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
    "Issuer:C = US, O = SSL Corporation, CN = SSL.com TLS Transit ECC CA R2",
    "Start date:May 29 19:49:45 2025 GMT",
    "Expire date:May 27 19:49:44 2035 GMT",
    "",
}, "\n")

local METRICS = "0.1,0.2,0.3"

---Curl's stderr with a warning, the chain and the metrics.
---@return string
local function stderr()
    return "Warning: some curl warning\n"
        .. certificate.START
        .. "\n"
        .. CERTS
        .. certificate.END
        .. "\n"
        .. METRICS
end

describe("certificate", function()
    describe("write_out", function()
        it("prints the chain between markers, on one line", function()
            local write_out = certificate.write_out()

            assert.are.equal(
                certificate.START .. "\\n%{certs}" .. certificate.END .. "\\n",
                write_out
            )
            assert.is_nil(write_out:find("\n", 1, true))
        end)
    end)

    describe("parse", function()
        it("parses each certificate of the chain", function()
            local tls = certificate.parse(stderr(), 0, 2)

            assert.are.same({
                verify_result = 0,
                certs = {
                    {
                        subject = "CN = example.com",
                        common_name = "example.com",
                        issuer = "C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
                        san = "DNS:example.com, DNS:*.example.com",
                        start_date = "Sep 26 22:49:11 2026 GMT",
                        expire_date = "Dec 25 22:56:35 2026 GMT",
                        expires_at = 1798239395 --[[ 2026-12-25 22:56:35 UTC ]],
                    },
                    {
                        subject = "C = US, O = SSL Corporation, CN = Cloudflare TLS Issuing ECC CA 3",
                        common_name = "Cloudflare TLS Issuing ECC CA 3",
                        issuer = "C = US, O = SSL Corporation, CN = SSL.com TLS Transit ECC CA R2",
                        start_date = "May 29 19:49:45 2025 GMT",
                        expire_date = "May 27 19:49:44 2035 GMT",
                        expires_at = 2063908184 --[[ 2035-05-27 19:49:44 UTC ]],
                    },
                },
            }, tls)
        end)

        it("gives the reason an insecure request was not verified", function()
            local tls = certificate.parse(stderr(), 18, 2)

            assert.are.equal(18, tls.verify_result)
            assert.are.equal("self-signed certificate", tls.verify_reason)
        end)

        it("gives the code of an unknown verify result", function()
            local tls = certificate.parse(stderr(), 99, 2)

            assert.are.equal("error 99", tls.verify_reason)
        end)

        it("is nil without certificates", function()
            assert.is_nil(certificate.parse(METRICS, 0, 0))
            assert.is_nil(certificate.parse(METRICS, nil, nil))
        end)

        it("uses the whole subject without a common name", function()
            local tls = certificate.parse(
                certificate.START .. "\nSubject:O = Example\n" .. certificate.END,
                0,
                1
            )

            assert.are.equal("O = Example", tls.certs[1].common_name)
        end)
    end)

    describe("parse_date", function()
        it("reads OpenSSL's format", function()
            assert.are.equal(
                1788662951 --[[ 2026-09-06 02:49:11 UTC ]],
                certificate.parse_date("Sep  6 02:49:11 2026 GMT")
            )
        end)

        it("reads the format of other TLS backends", function()
            assert.are.equal(
                1790462951 --[[ 2026-09-26 22:49:11 UTC ]],
                certificate.parse_date("2026-09-26 22:49:11 GMT")
            )
        end)

        it("is nil for an unknown format", function()
            assert.is_nil(certificate.parse_date("tomorrow"))
        end)
    end)

    describe("replace_chain", function()
        it("replaces the chain with a line saying it was there", function()
            assert.are.equal(
                "Warning: some curl warning\n"
                    .. "[nurl removed the certificate chain (2 certificates) when saving to history]\n"
                    .. METRICS,
                certificate.replace_chain(stderr())
            )
        end)

        it("counts a single certificate", function()
            local chain = certificate.START
                .. "\nSubject:CN = example.com\n"
                .. certificate.END
                .. "\n"
                .. METRICS

            assert.are.equal(
                "[nurl removed the certificate chain (1 certificate) when saving to history]\n"
                    .. METRICS,
                certificate.replace_chain(chain)
            )
        end)

        it("leaves stderr without a chain as it is", function()
            assert.are.equal(METRICS, certificate.replace_chain(METRICS))
        end)
    end)
end)

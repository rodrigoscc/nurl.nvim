local responses = require("nurl.responses")

describe("responses", function()
    describe("parse", function()
        it("parses status line correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "Content-Type: application/json",
                "",
                '{"key": "value"}',
            }
            local stderr = { "0.1,0.2,0.3,0.4,0.5,0.6,0.7,100,50,25,10,1000,500" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal("HTTP/1.1", result.protocol)
            assert.are.equal(200, result.status_code)
            assert.are.equal("OK", result.reason_phrase)
        end)

        it("parses headers correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "Content-Type: application/json",
                "X-Custom-Header: custom-value",
                "",
                "body",
            }
            local stderr = { "0,0,0,0,0,0,0,0,0,0,0,0,0" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal("application/json", result.headers["Content-Type"])
            assert.are.equal("custom-value", result.headers["X-Custom-Header"])
        end)

        it("parses headers with colons in value", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "Link: <https://example.com>; rel=\"next\"",
                "",
                "",
            }
            local stderr = { "0,0,0,0,0,0,0,0,0,0,0,0,0" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal('<https://example.com>; rel="next"', result.headers["Link"])
        end)

        it("parses body correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "Content-Type: text/plain",
                "",
                "line1",
                "line2",
                "line3",
            }
            local stderr = { "0,0,0,0,0,0,0,0,0,0,0,0,0" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal("line1\nline2\nline3", result.body)
        end)

        it("parses timing metrics correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "",
                "",
            }
            local stderr = { "0.1,0.2,0.3,0.4,0.5,0.6,0.7,100,50,25,10,1000,500" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal(0.1, result.time.time_appconnect)
            assert.are.equal(0.2, result.time.time_connect)
            assert.are.equal(0.3, result.time.time_namelookup)
            assert.are.equal(0.4, result.time.time_pretransfer)
            assert.are.equal(0.5, result.time.time_redirect)
            assert.are.equal(0.6, result.time.time_starttransfer)
            assert.are.equal(0.7, result.time.time_total)
        end)

        it("parses size metrics correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "",
                "",
            }
            local stderr = { "0,0,0,0,0,0,0,100,50,25,10,1000,500" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal(100, result.size.size_download)
            assert.are.equal(50, result.size.size_header)
            assert.are.equal(25, result.size.size_request)
            assert.are.equal(10, result.size.size_upload)
        end)

        it("parses speed metrics correctly", function()
            local stdout = {
                "HTTP/1.1 200 OK",
                "",
                "",
            }
            local stderr = { "0,0,0,0,0,0,0,0,0,0,0,1000,500" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal(1000, result.speed.speed_download)
            assert.are.equal(500, result.speed.speed_upload)
        end)

        it("handles empty body", function()
            local stdout = {
                "HTTP/1.1 204 No Content",
                "",
                "",
            }
            local stderr = { "0,0,0,0,0,0,0,0,0,0,0,0,0" }

            local result = responses.parse(stdout, stderr)

            assert.are.equal("", result.body)
        end)
    end)
end)

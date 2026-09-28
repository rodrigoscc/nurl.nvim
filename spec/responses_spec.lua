local responses = require("nurl.responses")
local Curl = require("nurl.curl")

-- The --write-out values in the order requests.build_curl asks for them.
local METRICS = {
    "time_appconnect",
    "time_connect",
    "time_namelookup",
    "time_pretransfer",
    "time_redirect",
    "time_starttransfer",
    "time_total",
    "size_download",
    "size_header",
    "size_request",
    "size_upload",
    "speed_download",
    "speed_upload",
}

---Build curl's stdout and stderr for a request run with --include: every
---header block followed by the body, and the --write-out metrics. As in
---curl, size_header counts the bytes of all the header blocks.
---@param blocks string[][] header blocks, each a status line and headers
---@param body string
---@param metrics? table<string, number> values for the other metrics
---@return string stdout, string stderr
local function curl_output(blocks, body, metrics)
    local headers = {}
    for _, block in ipairs(blocks) do
        table.insert(headers, table.concat(block, "\r\n") .. "\r\n\r\n")
    end
    headers = table.concat(headers)

    metrics = vim.tbl_extend("keep", metrics or {}, { size_header = #headers })
    local values = vim.tbl_map(function(name)
        return tostring(metrics[name] or 0)
    end, METRICS)

    return headers .. body, table.concat(values, ",")
end

describe("responses", function()
    describe("parse", function()
        it("parses status line correctly", function()
            local result = responses.parse(curl_output({
                { "HTTP/1.1 200 OK", "Content-Type: application/json" },
            }, '{"key": "value"}'))

            assert.are.equal("HTTP/1.1", result.protocol)
            assert.are.equal(200, result.status_code)
            assert.are.equal("OK", result.reason_phrase)
        end)

        it("parses status line without status phrase", function()
            local result = responses.parse(curl_output({
                { "HTTP/1.1 200", "Content-Type: application/json" },
            }, '{"key": "value"}'))

            assert.are.equal("HTTP/1.1", result.protocol)
            assert.are.equal(200, result.status_code)
            assert.are.equal("", result.reason_phrase)
        end)

        it("parses status line with long status phrase", function()
            local result = responses.parse(curl_output({
                {
                    "HTTP/1.1 503 Service Unavailable",
                    "Content-Type: application/json",
                },
            }, '{"key": "value"}'))

            assert.are.equal("HTTP/1.1", result.protocol)
            assert.are.equal(503, result.status_code)
            assert.are.equal("Service Unavailable", result.reason_phrase)
        end)

        it("keeps headers in the order the server sent them", function()
            local result = responses.parse(curl_output({
                {
                    "HTTP/1.1 200 OK",
                    "Vary: Accept",
                    "Set-Cookie: a=1",
                    "Content-Type: application/json",
                    "Set-Cookie: b=2",
                },
            }, "{}"))

            assert.are.same({
                "Vary: Accept",
                "Set-Cookie: a=1",
                "Content-Type: application/json",
                "Set-Cookie: b=2",
            }, responses.header_lines(result))
            assert.are.same({ "a=1", "b=2" }, result.headers["Set-Cookie"])
        end)

        it("lists headers without a recorded order alphabetically", function()
            assert.are.same(
                { "a: 1", "b: 2", "b: 3", "c: 4" },
                responses.header_lines({
                    headers = { c = "4", a = "1", b = { "2", "3" } },
                })
            )
        end)

        it("parses headers correctly", function()
            local result = responses.parse(curl_output({
                {
                    "HTTP/1.1 200 OK",
                    "Content-Type: application/json",
                    "X-Custom-Header: custom-value",
                },
            }, "body"))

            assert.are.equal("application/json", result.headers["Content-Type"])
            assert.are.equal("custom-value", result.headers["X-Custom-Header"])
        end)

        it("collects repeated headers into list", function()
            local result = responses.parse(curl_output({
                { "HTTP/1.1 200 OK", "Set-Cookie: a=1", "Set-Cookie: b=2" },
            }, "body"))

            assert.are.same({ "a=1", "b=2" }, result.headers["Set-Cookie"])
        end)

        it("parses headers with colons in value", function()
            local result = responses.parse(curl_output({
                {
                    "HTTP/1.1 200 OK",
                    'Link: <https://example.com>; rel="next"',
                },
            }, ""))

            assert.are.equal(
                '<https://example.com>; rel="next"',
                result.headers["Link"]
            )
        end)

        it("parses body correctly", function()
            local result = responses.parse(curl_output({
                { "HTTP/1.1 200 OK", "Content-Type: text/plain" },
            }, "line1\nline2\nline3"))

            assert.are.equal("line1\nline2\nline3", result.body)
        end)

        it("keeps the body byte for byte", function()
            local body = "\0\255 crlf\r\n\r\nHTTP/1.1 200 OK\r\n\r\ntail\n"

            local result = responses.parse(curl_output({
                {
                    "HTTP/1.1 200 OK",
                    "Content-Type: application/octet-stream",
                },
            }, body))

            assert.are.equal(body, result.body)
            assert.are.equal(200, result.status_code)
        end)

        it("parses timing metrics correctly", function()
            local result =
                responses.parse(curl_output({ { "HTTP/1.1 200 OK" } }, "", {
                    time_appconnect = 0.1,
                    time_connect = 0.2,
                    time_namelookup = 0.3,
                    time_pretransfer = 0.4,
                    time_redirect = 0.5,
                    time_starttransfer = 0.6,
                    time_total = 0.7,
                }))

            assert.are.equal(0.1, result.time.time_appconnect)
            assert.are.equal(0.2, result.time.time_connect)
            assert.are.equal(0.3, result.time.time_namelookup)
            assert.are.equal(0.4, result.time.time_pretransfer)
            assert.are.equal(0.5, result.time.time_redirect)
            assert.are.equal(0.6, result.time.time_starttransfer)
            assert.are.equal(0.7, result.time.time_total)
        end)

        it("parses size metrics correctly", function()
            local result = responses.parse(
                curl_output(
                    { { "HTTP/1.1 200 OK" } },
                    "",
                    { size_download = 100, size_request = 25, size_upload = 10 }
                )
            )

            assert.are.equal(100, result.size.size_download)
            assert.are.equal(
                #"HTTP/1.1 200 OK\r\n\r\n",
                result.size.size_header
            )
            assert.are.equal(25, result.size.size_request)
            assert.are.equal(10, result.size.size_upload)
        end)

        it("parses speed metrics correctly", function()
            local result = responses.parse(
                curl_output(
                    { { "HTTP/1.1 200 OK" } },
                    "",
                    { speed_download = 1000, speed_upload = 500 }
                )
            )

            assert.are.equal(1000, result.speed.speed_download)
            assert.are.equal(500, result.speed.speed_upload)
        end)

        it("reads the metrics after other messages on stderr", function()
            local stdout, stderr = curl_output(
                { { "HTTP/1.1 200 OK" } },
                "",
                { time_total = 0.7 }
            )

            local result = responses.parse(
                stdout,
                "Warning: some curl warning\n" .. stderr
            )

            assert.are.equal(0.7, result.time.time_total)
            assert.are.equal(200, result.status_code)
        end)

        it("errors when the metrics are missing from stderr", function()
            local stdout = curl_output({ { "HTTP/1.1 200 OK" } }, "hello")

            assert.has_error(function()
                responses.parse(stdout, "")
            end, 'Could not find the curl metrics in stderr: ""')
        end)

        it("errors when size_header is larger than the output", function()
            assert.has_error(function()
                responses.parse("HTTP/1.1 200 OK\r\n", "0,0,0,0,0,0,0,0,99,0,0,0,0")
            end, "Curl reported 99 bytes of headers but printed 17 bytes")
        end)

        it("errors when there are no response headers", function()
            assert.has_error(function()
                responses.parse(curl_output({}, "hello"))
            end, "Curl printed no response headers")
        end)

        it("handles empty body", function()
            local result = responses.parse(
                curl_output({ { "HTTP/1.1 204 No Content" } }, "")
            )

            assert.are.equal("", result.body)
        end)

        describe("with several header blocks", function()
            it("uses the final response after a redirect", function()
                local result = responses.parse(curl_output({
                    {
                        "HTTP/1.1 301 Moved",
                        "Location: /final",
                        "Content-Length: 0",
                    },
                    {
                        "HTTP/1.1 200 OK",
                        "Content-Type: text/plain",
                        "Content-Length: 5",
                    },
                }, "hello"))

                assert.are.equal(200, result.status_code)
                assert.are.equal("OK", result.reason_phrase)
                assert.are.same({
                    "Content-Type: text/plain",
                    "Content-Length: 5",
                }, responses.header_lines(result))
                assert.is_nil(result.headers["Location"])
                assert.are.equal("hello", result.body)
            end)

            it("skips 100 Continue", function()
                local result = responses.parse(curl_output({
                    { "HTTP/1.1 100 Continue" },
                    { "HTTP/1.1 201 Created", "Content-Type: text/plain" },
                }, "created"))

                assert.are.equal(201, result.status_code)
                assert.are.same(
                    { "Content-Type: text/plain" },
                    responses.header_lines(result)
                )
                assert.are.equal("created", result.body)
            end)

            it("skips 103 Early Hints", function()
                local result = responses.parse(curl_output({
                    { "HTTP/1.1 103 Early Hints", "Link: </a.css>" },
                    { "HTTP/1.1 200 OK", "Content-Type: text/plain" },
                }, "hello"))

                assert.are.equal(200, result.status_code)
                assert.is_nil(result.headers["Link"])
                assert.are.equal("hello", result.body)
            end)

            it("skips the reply to a proxy CONNECT", function()
                -- Output of curl 8.22 through a tunneling proxy. size_header
                -- counts the CONNECT reply too.
                local stdout = "HTTP/1.1 200 Connection established\r\n"
                    .. "Proxy-Agent: test\r\n"
                    .. "\r\n"
                    .. "HTTP/1.1 200 OK\r\n"
                    .. "Content-Type: text/plain\r\n"
                    .. "Content-Length: 5\r\n"
                    .. "\r\n"
                    .. "hello"
                local stderr = "0,0,0,0,0,0,0,5,122,0,0,0,0"

                local result = responses.parse(stdout, stderr)

                assert.are.equal(200, result.status_code)
                assert.are.equal("OK", result.reason_phrase)
                assert.is_nil(result.headers["Proxy-Agent"])
                assert.are.equal("hello", result.body)
            end)
        end)
    end)
end)

describe("Curl:replace_body", function()
    it("keeps every header block", function()
        local stdout = curl_output({
            { "HTTP/1.1 302 Found", "Location: /image" },
            { "HTTP/1.1 200 OK", "Content-Type: image/png" },
        }, "\137PNG\r\n\26\n")
        local headers = stdout:sub(1, #stdout - #"\137PNG\r\n\26\n")
        local curl = Curl:new({ args = {}, result = { stdout = stdout } })

        curl:replace_body("@/tmp/response.png", #headers)

        assert.are.equal(headers .. "@/tmp/response.png", curl.result.stdout)
    end)
end)

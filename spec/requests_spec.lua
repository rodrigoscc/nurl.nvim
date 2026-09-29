local requests = require("nurl.core.request")
local Curl = require("nurl.core.curl")

describe("requests", function()
    describe("expand", function()
        it("expands simple string url", function()
            local request = { url = "https://example.com" }
            local result = requests.expand(request)

            assert.are.equal("https://example.com", result.url)
            assert.are.equal("GET", result.method)
        end)

        it("expands url function", function()
            local request = {
                url = function()
                    return "https://dynamic.com"
                end,
            }
            local result = requests.expand(request)

            assert.are.equal("https://dynamic.com", result.url)
        end)

        it("expands method to uppercase", function()
            local request = { url = "https://example.com", method = "post" }
            local result = requests.expand(request)

            assert.are.equal("POST", result.method)
        end)

        it("defaults method to GET", function()
            local request = { url = "https://example.com" }
            local result = requests.expand(request)

            assert.are.equal("GET", result.method)
        end)

        it("expands headers function", function()
            local request = {
                url = "https://example.com",
                headers = function()
                    return { Authorization = "Bearer token" }
                end,
            }
            local result = requests.expand(request)

            assert.are.equal("Bearer token", result.headers.Authorization)
        end)

        it("expands data function", function()
            local request = {
                url = "https://example.com",
                data = function()
                    return { key = "value" }
                end,
            }
            local result = requests.expand(request)

            assert.are.same({ key = "value" }, result.data)
        end)

        it("preserves hooks", function()
            local pre_hook = function() end
            local post_hook = function() end
            local request = {
                url = "https://example.com",
                pre_hook = pre_hook,
                post_hook = post_hook,
            }
            local result = requests.expand(request)

            assert.are.equal(pre_hook, result.pre_hook)
            assert.are.equal(post_hook, result.post_hook)
        end)

        it("expands save_history", function()
            local request = {
                url = "https://example.com",
                save_history = function()
                    return false
                end,
            }
            local result = requests.expand(request)

            assert.is_false(result.save_history)
        end)

        it("errors when multiple body types provided", function()
            local request = {
                url = "https://example.com",
                data = "body",
                form = { key = "value" },
            }

            assert.has_error(function()
                requests.expand(request)
            end)
        end)

        it("errors when url is nil", function()
            local request = { method = "GET" }

            assert.has_error(function()
                requests.expand(request)
            end)
        end)

        it("expands query table", function()
            local request = {
                url = "https://example.com",
                query = { page = 1, limit = 10 },
            }
            local result = requests.expand(request)

            assert.are.same({ page = 1, limit = 10 }, result.query)
        end)

        it("expands query function", function()
            local request = {
                url = "https://example.com",
                query = function()
                    return { token = "abc123" }
                end,
            }
            local result = requests.expand(request)

            assert.are.same({ token = "abc123" }, result.query)
        end)

        it("expands query with function values", function()
            local request = {
                url = "https://example.com",
                query = {
                    static = "value",
                    dynamic = function()
                        return "computed"
                    end,
                },
            }
            local result = requests.expand(request)

            assert.are.equal("value", result.query.static)
            assert.are.equal("computed", result.query.dynamic)
        end)

        it("keeps the query of a shorthand url as written", function()
            local url = "https://example.com?q=a%20b&x=1+2&a=b=c&flag"
            local result = requests.expand({ url })

            assert.are.equal(url, result.url)
            assert.is_nil(result.query)
        end)

        it("keeps the query field apart from a shorthand url", function()
            local result = requests.expand({
                "https://example.com?existing=value",
                query = { added = "param" },
            })

            assert.are.equal("https://example.com?existing=value", result.url)
            assert.are.same({ added = "param" }, result.query)
        end)
    end)

    describe("build_curl", function()
        it("sends the query of a shorthand url as written", function()
            local url = "https://example.com?q=a%20b&x=1+2"
            local curl = Curl.build(requests.expand({ url }))

            assert.are.equal(url, curl.args[3])
            assert.is_false(vim.tbl_contains(curl.args, "--url-query"))
        end)

        it("encodes query names, leaving values to curl", function()
            local curl = Curl.build(requests.expand({
                url = "https://example.com",
                query = { ["my key"] = "a b" },
            }))

            local i = assert(vim.iter(ipairs(curl.args)):find(function(_, arg)
                return arg == "--url-query"
            end))
            assert.are.equal("my%20key=a b", curl.args[i + 1])
        end)

        it("builds basic curl command", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = {},
            }
            local curl = Curl.build(request)

            assert.is_not_nil(curl)
            assert.is_not_nil(curl.args)
        end)

        it("includes method and url in args", function()
            local request = {
                url = "https://example.com/api",
                method = "POST",
                headers = {},
            }
            local curl = Curl.build(request)

            local has_method = false
            local has_url = false
            for i, arg in ipairs(curl.args) do
                if arg == "--request" and curl.args[i + 1] == "POST" then
                    has_method = true
                end
                if arg == "https://example.com/api" then
                    has_url = true
                end
            end

            assert.is_true(has_method)
            assert.is_true(has_url)
        end)

        it("includes headers in args", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = { ["Content-Type"] = "application/json" },
            }
            local curl = Curl.build(request)

            local has_header = false
            for i, arg in ipairs(curl.args) do
                if
                    arg == "--header"
                    and curl.args[i + 1] == "Content-Type: application/json"
                then
                    has_header = true
                end
            end

            assert.is_true(has_header)
        end)

        it("expands list headers into multiple args", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = { ["Set-Cookie"] = { "a=1", "b=2" } },
            }
            local curl = Curl.build(request)

            local headers = {}
            for i, arg in ipairs(curl.args) do
                if arg == "--header" then
                    table.insert(headers, curl.args[i + 1])
                end
            end

            assert.is_true(vim.tbl_contains(headers, "Set-Cookie: a=1"))
            assert.is_true(vim.tbl_contains(headers, "Set-Cookie: b=2"))
        end)

        it("includes data in args for string data", function()
            local request = {
                url = "https://example.com",
                method = "POST",
                headers = {},
                data = '{"key":"value"}',
            }
            local curl = Curl.build(request)

            local has_data = false
            for i, arg in ipairs(curl.args) do
                if
                    arg == "--data"
                    and curl.args[i + 1] == '{"key":"value"}'
                then
                    has_data = true
                end
            end

            assert.is_true(has_data)
        end)

        it("includes form data in args", function()
            local request = {
                url = "https://example.com",
                method = "POST",
                headers = {},
                form = { name = "test" },
            }
            local curl = Curl.build(request)

            local has_form = false
            for i, arg in ipairs(curl.args) do
                if arg == "--form" and curl.args[i + 1] == "name=test" then
                    has_form = true
                end
            end

            assert.is_true(has_form)
        end)

        it("includes standard flags", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = {},
            }
            local curl = Curl.build(request)

            local has_include = false
            local has_no_progress = false
            local has_write_out = false
            for _, arg in ipairs(curl.args) do
                if arg == "--include" then
                    has_include = true
                end
                if arg == "--no-progress-meter" then
                    has_no_progress = true
                end
                if arg == "--write-out" then
                    has_write_out = true
                end
            end

            assert.is_true(has_include)
            assert.is_true(has_no_progress)
            assert.is_true(has_write_out)
        end)

        it("includes query params with --url-query flag", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = {},
                query = { page = "1", limit = "10" },
            }
            local curl = Curl.build(request)

            local query_flags = {}
            for i, arg in ipairs(curl.args) do
                if arg == "--url-query" then
                    table.insert(query_flags, curl.args[i + 1])
                end
            end

            assert.are.equal(2, #query_flags)
            assert.is_true(vim.tbl_contains(query_flags, "page=1"))
            assert.is_true(vim.tbl_contains(query_flags, "limit=10"))
        end)

        it(
            "expands repeated query params to multiple --url-query flags",
            function()
                local request = {
                    url = "https://example.com",
                    method = "GET",
                    headers = {},
                    query = { id = { "1", "2", "3" } },
                }
                local curl = Curl.build(request)

                local query_flags = {}
                for i, arg in ipairs(curl.args) do
                    if arg == "--url-query" then
                        table.insert(query_flags, curl.args[i + 1])
                    end
                end

                assert.are.equal(3, #query_flags)
                assert.is_true(vim.tbl_contains(query_flags, "id=1"))
                assert.is_true(vim.tbl_contains(query_flags, "id=2"))
                assert.is_true(vim.tbl_contains(query_flags, "id=3"))
            end
        )

        it("handles nil query", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = {},
                query = nil,
            }
            local curl = Curl.build(request)

            for _, arg in ipairs(curl.args) do
                assert.is_not.equal("--url-query", arg)
            end
        end)
    end)

end)

local requests = require("nurl.requests")

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
    end)

    describe("build_curl", function()
        it("builds basic curl command", function()
            local request = {
                url = "https://example.com",
                method = "GET",
                headers = {},
            }
            local curl = requests.build_curl(request)

            assert.is_not_nil(curl)
            assert.is_not_nil(curl.args)
        end)

        it("includes method and url in args", function()
            local request = {
                url = "https://example.com/api",
                method = "POST",
                headers = {},
            }
            local curl = requests.build_curl(request)

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
            local curl = requests.build_curl(request)

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

        it("includes data in args for string data", function()
            local request = {
                url = "https://example.com",
                method = "POST",
                headers = {},
                data = '{"key":"value"}',
            }
            local curl = requests.build_curl(request)

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
            local curl = requests.build_curl(request)

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
            local curl = requests.build_curl(request)

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
    end)
end)

local http = require("nurl.http")

local function lines_to_string(lines)
    return table.concat(lines, "\n")
end

local function parse_json_body(lines)
    local result = lines_to_string(lines)
    local body_start = result:find("\n\n")

    if not body_start then
        return nil
    end

    local body = result:sub(body_start + 2)
    local ok, parsed = pcall(vim.json.decode, body)
    if ok then
        return parsed
    end

    return nil
end

describe("http", function()
    describe("request_to_http_message", function()
        it("formats simple GET request", function()
            local request = {
                method = "GET",
                url = "https://api.example.com/users",
                headers = {},
            }

            local result = http.request_to_http_message(request)

            assert.are.same({ "GET https://api.example.com/users" }, result)
        end)

        it("formats GET request with query params", function()
            local request = {
                method = "GET",
                url = "https://api.example.com/users",
                query = { page = "1" },
                headers = {},
            }

            local result = http.request_to_http_message(request)

            assert.are.same(
                { "GET https://api.example.com/users?page=1" },
                result
            )
        end)

        it("formats request with headers", function()
            local request = {
                method = "GET",
                url = "https://api.example.com/users",
                headers = {
                    ["Authorization"] = "Bearer token123",
                },
            }

            local result = http.request_to_http_message(request)
            local result_str = lines_to_string(result)

            assert.is_true(
                result_str:find("GET https://api.example.com/users") == 1
            )
            assert.is_true(
                result_str:find("Authorization: Bearer token123") ~= nil
            )
        end)

        it("formats POST with JSON data table", function()
            local request = {
                method = "POST",
                url = "https://api.example.com/users",
                headers = {},
                data = { name = "John" },
            }

            local result = http.request_to_http_message(request)
            local result_str = lines_to_string(result)

            assert.is_true(
                result_str:find("POST https://api.example.com/users") == 1
            )
            assert.is_true(
                result_str:find("Content%-Type: application/json") ~= nil
            )

            local parsed_body = parse_json_body(result)
            assert.are.same({ name = "John" }, parsed_body)
        end)

        it("formats POST with JSON data string", function()
            local request = {
                method = "POST",
                url = "https://api.example.com/users",
                headers = {},
                data = '{"custom":"json"}',
            }

            local result = http.request_to_http_message(request)

            assert.are.same({
                "POST https://api.example.com/users",
                "",
                '{"custom":"json"}',
            }, result)
        end)

        it(
            "formats POST with JSON data string with content-type header",
            function()
                local request = {
                    method = "POST",
                    url = "https://api.example.com/users",
                    headers = {
                        ["Content-Type"] = "application/json",
                    },
                    data = '{"custom":"json"}',
                }

                local result = http.request_to_http_message(request)
                local result_str = lines_to_string(result)

                assert.is_true(
                    result_str:find("POST https://api.example.com/users") == 1
                )
                assert.is_true(
                    result_str:find("Content%-Type: application/json") ~= nil
                )

                local parsed_body = parse_json_body(result)
                assert.are.same({ custom = "json" }, parsed_body)
            end
        )

        it("formats POST with form data", function()
            local request = {
                method = "POST",
                url = "https://api.example.com/upload",
                headers = {},
                form = { name = "document" },
            }

            local result = http.request_to_http_message(request)
            local result_str = lines_to_string(result)

            assert.is_true(
                result_str:find("POST https://api.example.com/upload") == 1
            )
            assert.is_true(
                result_str:find("Content%-Type: multipart/form%-data") ~= nil
            )
            assert.is_true(result_str:find("name=document") ~= nil)
        end)

        it("formats POST with urlencoded data", function()
            local request = {
                method = "POST",
                url = "https://api.example.com/login",
                headers = {},
                data_urlencode = {
                    username = "user",
                },
            }

            local result = http.request_to_http_message(request)
            local result_str = lines_to_string(result)

            assert.is_true(
                result_str:find("POST https://api.example.com/login") == 1
            )
            assert.is_true(
                result_str:find(
                    "Content%-Type: application/x%-www%-form%-urlencoded"
                ) ~= nil
            )
            assert.is_true(result_str:find("username=user") ~= nil)
        end)

        it("does not override existing Content-Type header", function()
            local request = {
                method = "POST",
                url = "https://api.example.com/users",
                headers = {
                    ["Content-Type"] = "application/json; charset=utf-8",
                },
                data = { name = "John" },
            }

            local result = http.request_to_http_message(request)
            local result_str = lines_to_string(result)

            assert.is_true(
                result_str:find("POST https://api.example.com/users") == 1
            )
            assert.is_true(
                result_str:find(
                    "Content%-Type: application/json; charset=utf%-8"
                ) ~= nil
            )

            local parsed_body = parse_json_body(result)
            assert.are.same({ name = "John" }, parsed_body)
        end)

        it(
            "does not override existing content-type header (lowercase)",
            function()
                local request = {
                    method = "POST",
                    url = "https://api.example.com/users",
                    headers = {
                        ["content-type"] = "text/plain",
                    },
                    data = { name = "John" },
                }

                local result = http.request_to_http_message(request)
                local result_str = lines_to_string(result)

                assert.is_true(
                    result_str:find("POST https://api.example.com/users") == 1
                )
                assert.is_true(
                    result_str:find("content%-type: text/plain") ~= nil
                )
                assert.is_nil(
                    result_str:find("Content%-Type: application/json")
                )
            end
        )

        it("handles empty headers table", function()
            local request = {
                method = "DELETE",
                url = "https://api.example.com/users/1",
            }

            local result = http.request_to_http_message(request)

            assert.are.same(
                { "DELETE https://api.example.com/users/1" },
                result
            )
        end)
    end)

    describe("response_to_http_message", function()
        it("formats simple response", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 200,
                reason_phrase = "OK",
                headers = {},
            }

            local result = http.response_to_http_message(response)

            assert.are.same({ "HTTP/1.1 200 OK" }, result)
        end)

        it("formats response without reason phrase", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 204,
                reason_phrase = "",
                headers = {},
            }

            local result = http.response_to_http_message(response)

            assert.are.same({ "HTTP/1.1 204" }, result)
        end)

        it("formats response with headers", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 200,
                reason_phrase = "OK",
                headers = {
                    ["Content-Type"] = "text/plain",
                },
            }

            local result = http.response_to_http_message(response)
            local result_str = lines_to_string(result)

            assert.is_true(result_str:find("HTTP/1.1 200 OK") == 1)
            assert.is_true(result_str:find("Content%-Type: text/plain") ~= nil)
        end)

        it("formats response with JSON body", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 200,
                reason_phrase = "OK",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                body = '{"id":1,"name":"John"}',
            }

            local result = http.response_to_http_message(response)
            local result_str = lines_to_string(result)

            assert.is_true(result_str:find("HTTP/1.1 200 OK") == 1)
            assert.is_true(
                result_str:find("Content%-Type: application/json") ~= nil
            )

            local body_start = result_str:find("\n\n")
            assert.is_not_nil(body_start)

            local body = result_str:sub(body_start + 2)
            local parsed = vim.json.decode(body)
            assert.are.same({ id = 1, name = "John" }, parsed)
        end)

        it("formats response with plain text body", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 200,
                reason_phrase = "OK",
                headers = {
                    ["Content-Type"] = "text/plain",
                },
                body = "Hello, World!",
            }

            local result = http.response_to_http_message(response)

            assert.are.same({
                "HTTP/1.1 200 OK",
                "Content-Type: text/plain",
                "",
                "Hello, World!",
            }, result)
        end)

        it("formats response with body_file", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 200,
                reason_phrase = "OK",
                headers = {
                    ["Content-Type"] = "image/png",
                },
                body_file = "/tmp/nurl/response.png",
            }

            local result = http.response_to_http_message(response)

            assert.are.same({
                "HTTP/1.1 200 OK",
                "Content-Type: image/png",
                "",
                "[Body saved to file: /tmp/nurl/response.png]",
            }, result)
        end)

        it("formats error response", function()
            local response = {
                protocol = "HTTP/1.1",
                status_code = 404,
                reason_phrase = "Not Found",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                body = '{"error":"Resource not found"}',
            }

            local result = http.response_to_http_message(response)
            local result_str = lines_to_string(result)

            assert.is_true(result_str:find("HTTP/1.1 404 Not Found") == 1)

            local body_start = result_str:find("\n\n")
            assert.is_not_nil(body_start)

            local body = result_str:sub(body_start + 2)
            local parsed = vim.json.decode(body)
            assert.are.same({ error = "Resource not found" }, parsed)
        end)
    end)
end)

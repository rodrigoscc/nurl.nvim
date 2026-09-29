local request_format = require("nurl.core.request_format")

describe("request format", function()
    describe("full_url", function()
        it("joins URL parts", function()
            assert.are.equal(
                "https://example.org/v1/users",
                request_format.full_url({
                    url = { "https://example.org/", "/v1", "users" },
                })
            )
        end)

        it("adds the query, repeating list values", function()
            assert.are.equal(
                "https://example.org?tag=a&tag=b",
                request_format.full_url({
                    url = "https://example.org",
                    query = { tag = { "a", "b" } },
                })
            )
        end)

        it("appends to a query already in the URL", function()
            assert.are.equal(
                "https://example.org?a=1&page=2",
                request_format.full_url({
                    url = "https://example.org?a=1",
                    query = { page = 2 },
                })
            )
        end)

        it("sorts the query by name", function()
            local query, expected = {}, {}
            for byte = string.byte("a"), string.byte("z") do
                local letter = string.char(byte)
                query[letter] = byte
                table.insert(expected, letter .. "=" .. byte)
            end

            assert.are.equal(
                "https://example.org?" .. table.concat(expected, "&"),
                request_format.full_url({
                    url = "https://example.org",
                    query = query,
                })
            )
        end)

        it("leaves a URL without query alone", function()
            assert.are.equal(
                "https://example.org",
                request_format.full_url({ url = "https://example.org" })
            )
        end)
    end)

    describe("text", function()
        local request = {
            method = "GET",
            url = "https://example.org",
            query = { q = "x" },
        }

        it("shows the method and full URL", function()
            assert.are.equal(
                "GET https://example.org?q=x",
                request_format.text(request)
            )
        end)

        it("shows the title instead", function()
            assert.are.equal(
                "Search",
                request_format.text(vim.tbl_extend("force", request, {
                    title = "Search",
                }))
            )
        end)

        it("adds a prefix and a suffix", function()
            assert.are.equal(
                "> GET https://example.org?q=x requests.lua",
                request_format.text(request, {
                    prefix = ">",
                    suffix = "requests.lua",
                })
            )
        end)
    end)
end)

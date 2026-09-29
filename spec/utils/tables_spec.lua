local tables = require("nurl.utils.tables")

describe("utils.tables", function()
    describe("sorted_pairs", function()
        it("iterates in the order of the keys", function()
            local seen = {}
            for key, value in tables.sorted_pairs({ c = 3, a = 1, b = 2 }) do
                table.insert(seen, key .. "=" .. value)
            end

            assert.are.same({ "a=1", "b=2", "c=3" }, seen)
        end)

        it("orders numbers and strings together", function()
            local keys = {}
            for key in tables.sorted_pairs({ b = true, [2] = true, [10] = true, a = true }) do
                table.insert(keys, key)
            end

            assert.are.same({ 10, 2, "a", "b" }, keys)
        end)

        it("iterates nothing for an empty table", function()
            for _ in tables.sorted_pairs({}) do
                error("should not iterate")
            end
        end)
    end)
end)

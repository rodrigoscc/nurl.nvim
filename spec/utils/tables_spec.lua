local tables = require("nurl.utils.tables")

describe("utils.tables", function()
    describe("extend", function()
        it("extends list1 with items from list2", function()
            local list1 = { 1, 2, 3 }
            local list2 = { 4, 5, 6 }
            local result = tables.extend(list1, list2)
            assert.are.same({ 1, 2, 3, 4, 5, 6 }, result)
        end)

        it("returns modified list1", function()
            local list1 = { "a" }
            local list2 = { "b" }
            local result = tables.extend(list1, list2)
            assert.are.equal(list1, result)
        end)

        it("handles empty list1", function()
            local list1 = {}
            local list2 = { 1, 2 }
            local result = tables.extend(list1, list2)
            assert.are.same({ 1, 2 }, result)
        end)

        it("handles empty list2", function()
            local list1 = { 1, 2 }
            local list2 = {}
            local result = tables.extend(list1, list2)
            assert.are.same({ 1, 2 }, result)
        end)

        it("handles both empty lists", function()
            local list1 = {}
            local list2 = {}
            local result = tables.extend(list1, list2)
            assert.are.same({}, result)
        end)

        it("works with mixed types", function()
            local list1 = { 1, "a" }
            local list2 = { true, nil, "b" }
            local result = tables.extend(list1, list2)
            assert.are.same({ 1, "a", true }, result)
        end)
    end)
end)

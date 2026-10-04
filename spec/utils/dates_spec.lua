local dates = require("nurl.utils.dates")

describe("utils.dates", function()
    it("names days relative to today", function()
        local now = os.time({ year = 2026, month = 9, day = 26, hour = 10 })
        local function format(time)
            return dates.format_day(time, now)
        end

        assert.are.equal("Today", format("2026-09-26T09:05:59"))
        assert.are.equal("Yesterday", format("2026-09-25T23:59:00"))
        assert.are.equal("Thursday", format("2026-09-24T14:32:10"))
        assert.are.equal("Sunday", format("2026-09-20T08:00:00"))
        assert.are.equal("Sep 19", format("2026-09-19T18:20:00"))
        assert.are.equal("Jan 3", format("2026-01-03T07:15:00"))
        assert.are.equal("Dec 31, 2025", format("2025-12-31T23:00:00"))
        assert.are.equal("Oct 1", format("2026-10-01T12:00:00"))
        assert.are.equal("not a date", format("not a date"))
    end)

    it("formats the full date of a saved time", function()
        assert.are.equal(
            "Sunday, Oct 4, 2026",
            dates.format_date("2026-10-04T01:15:32")
        )
        assert.are.equal(
            "Wednesday, Dec 31, 2025",
            dates.format_date("2025-12-31T23:00:00")
        )
        assert.are.equal("not a date", dates.format_date("not a date"))
    end)
end)

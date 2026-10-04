local M = {}

local weekdays = {
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
}
local months = {
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
}

---The day of a saved local ISO time, at noon so that comparing days is not
---affected by daylight saving changes.
---@param time string
---@return integer? date, integer? year, integer? month, integer? day
local function parse_day(time)
    local year, month, day = time:match("^(%d+)-(%d+)-(%d+)T")
    if not year then
        return nil
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)

    local date = os.time({ year = year, month = month, day = day, hour = 12 })
    return date, year, month, day
end

---Name the day of a saved local ISO time relative to today: "Today",
---"Yesterday", "Thursday", "Sep 3", or "Sep 3, 2025".
---@param time string
---@param now? integer
---@return string
function M.format_day(time, now)
    local date, year, month, day = parse_day(time)
    if not date then
        return time
    end

    local today = os.date("*t", now or os.time())
    local days = math.floor((os.time({
        year = today.year,
        month = today.month,
        day = today.day,
        hour = 12,
    }) - date) / 86400 + 0.5)

    if days == 0 then
        return "Today"
    elseif days == 1 then
        return "Yesterday"
    elseif days > 1 and days < 7 then
        return weekdays[os.date("*t", date).wday]
    elseif year == today.year then
        return ("%s %d"):format(months[month], day)
    end
    return ("%s %d, %d"):format(months[month], day, year)
end

---Format the day of a saved local ISO time in full: "Sunday, Oct 4, 2026".
---@param time string
---@return string
function M.format_date(time)
    local date, year, month, day = parse_day(time)
    if not date then
        return time
    end

    return ("%s, %s %d, %d"):format(
        weekdays[os.date("*t", date).wday],
        months[month],
        day,
        year
    )
end

return M

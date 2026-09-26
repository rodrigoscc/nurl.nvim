local config = require("nurl.config")
local history = require("nurl.data.history")
local preview = require("nurl.preview")

local M = {}
local list_namespace = vim.api.nvim_create_namespace("nurl.history_explorer")
local page_prefetch = 5

local filter_fields = {
    { label = "URL / title", key = "search" },
    { label = "Method (e.g. POST)", key = "method" },
    { label = "Status (e.g. 404 or 4xx)", key = "status" },
    { label = "From (YYYY-MM-DD or ISO datetime)", key = "from" },
    { label = "To (YYYY-MM-DD or ISO datetime)", key = "to" },
    { label = "Request body", key = "request_body" },
    { label = "Response body", key = "response_body" },
    {
        label = "Response body saved to file",
        key = "response_file",
        choices = { "yes", "no" },
    },
}

local function buffer(name)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name .. "/" .. bufnr)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    return bufnr
end

local function set_lines(bufnr, lines, append)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.bo[bufnr].modifiable = true

    if append then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
    else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end

    vim.bo[bufnr].modifiable = false
end

local weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
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

---Format a saved local ISO time relative to today: "today 14:32",
---"yesterday 09:05", "Thu 18:20", "Sep 3 14:32", or "Sep 3, 2025".
---@param time string
---@param now? integer
---@return string
function M.format_time(time, now)
    local year, month, day, hour, min =
        time:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if not year then
        return time
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)

    -- Compare calendar days at noon so daylight saving changes do not matter.
    local today = os.date("*t", now or os.time())
    local date = os.time({ year = year, month = month, day = day, hour = 12 })
    local days = math.floor(
        (
            os.time({
                year = today.year,
                month = today.month,
                day = today.day,
                hour = 12,
            }) - date
        ) / 86400
            + 0.5
    )
    local clock = hour .. ":" .. min

    if days == 0 then
        return "today " .. clock
    elseif days == 1 then
        return "yesterday " .. clock
    elseif days > 1 and days < 7 then
        return weekdays[os.date("*t", date).wday] .. " " .. clock
    elseif year == today.year then
        return ("%s %d %s"):format(months[month], day, clock)
    end
    return ("%s %d, %d"):format(months[month], day, year)
end

local function format_row(row, search)
    local parts = {}
    local spans = {}
    local length = 0

    local function add(text, group)
        if group then
            table.insert(spans, {
                start_col = length,
                end_col = length + #text,
                group = group,
            })
        end
        table.insert(parts, text)
        length = length + #text
    end

    local status_group = "NurlHistoryStatus"
    if row.status >= 200 and row.status < 300 then
        status_group = "NurlHistoryStatusSuccess"
    elseif row.status >= 300 and row.status < 400 then
        status_group = "NurlHistoryStatusRedirect"
    elseif row.status >= 400 then
        status_group = "NurlHistoryStatusError"
    end

    -- "yesterday 14:32" is the widest format.
    add(("%-15s"):format(M.format_time(row.time)), "NurlHistoryTime")
    add("  ")
    add(string.format("%-7s", row.method), "NurlHistoryMethod")
    add("  ")
    add(string.format("%-3d", row.status), status_group)
    add("  ")
    add(
        string.format("%7.0f ms", (row.duration or 0) * 1000),
        "NurlHistoryDuration"
    )
    add("  ")
    local label_start = length

    if row.title and row.title ~= "" then
        add(row.title:gsub("%c", " "), "NurlHistoryTitle")
        add("  ")
    end

    add(row.url:gsub("%c", " "), "NurlHistoryUrl")

    local line = table.concat(parts)

    if search and search ~= "" then
        local text = line:lower()
        local needle = search:lower()
        local from = label_start + 1

        while true do
            local first, last = text:find(needle, from, true)
            if not first then
                break
            end
            table.insert(spans, {
                start_col = first - 1,
                end_col = last,
                group = "NurlHistoryMatch",
            })
            from = last + 1
        end
    end

    return line, spans
end

local Explorer = {}
Explorer.__index = Explorer

function Explorer:alive()
    return not self.closed
        and vim.api.nvim_buf_is_valid(self.list_buf)
        and vim.api.nvim_win_is_valid(self.list_win)
end

function Explorer:selected()
    if not self:alive() then
        return nil
    end

    local row = vim.api.nvim_win_get_cursor(self.list_win)[1]

    return self.entries[row]
end

function Explorer:update_preview()
    if
        not self:alive()
        or not vim.api.nvim_buf_is_valid(self.preview_buf)
        or not vim.api.nvim_win_is_valid(self.preview_win)
    then
        return
    end

    local entry = self:selected()
    if not entry or entry.id == self.preview_id then
        return
    end

    self.preview_id = entry.id
    local ok, request = pcall(history.get_request, entry.id)
    if ok and request then
        ok, request = pcall(preview.render, request)
    end

    if ok and request then
        set_lines(self.preview_buf, request)
    else
        set_lines(self.preview_buf, { "Unable to preview this request." })
        if not ok then
            vim.notify(
                "Failed to preview request: " .. request,
                vim.log.levels.ERROR
            )
        end
    end
end

function Explorer:schedule_preview()
    self.preview_generation = self.preview_generation + 1
    local generation = self.preview_generation
    vim.defer_fn(function()
        if generation == self.preview_generation then
            self:update_preview()
        end
    end, 50)
end

function Explorer:response_target()
    local win = self.response_win

    if not win or not vim.api.nvim_win_is_valid(win) then
        return nil
    end

    local current_buf = vim.api.nvim_win_get_buf(win)

    for _, bufnr in pairs(self.response_buffers or {}) do
        if bufnr == current_buf then
            return win
        end
    end
end

local function delete_hidden_buffers(buffers)
    -- Reusing a response window hides its old buffers. Keep any that are still
    -- displayed elsewhere or have unsaved edits.
    for _, bufnr in pairs(buffers or {}) do
        if
            vim.api.nvim_buf_is_valid(bufnr)
            and not vim.bo[bufnr].modified
            and #vim.fn.win_findbuf(bufnr) == 0
        then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end
end

function Explorer:finish_page(generation, rows, more, err)
    if not self:alive() or generation ~= self.search_generation then
        return
    end

    self.loading = false
    vim.wo[self.list_win].winbar = self.list_winbar

    if err then
        vim.notify("Failed to load history: " .. err, vim.log.levels.ERROR)
        self.has_more = false
        if #self.entries == 0 then
            set_lines(
                self.list_buf,
                { "History search failed. Press F to change filters." }
            )
            set_lines(self.preview_buf, { "Unable to load request preview." })
        end
        return
    end

    local was_empty = #self.entries == 0

    self.has_more = more

    vim.list_extend(self.entries, rows)

    if #rows > 0 then
        self:render_rows(rows, not was_empty)
    elseif was_empty then
        self:show_empty()
    end

    if was_empty and #rows > 0 then
        self:schedule_preview()
    end

    self:fill_window()
end

---Render rows after the listed entries, or replace the whole list.
function Explorer:render_rows(rows, append)
    local start_row = append and vim.api.nvim_buf_line_count(self.list_buf)
        or 0
    local lines = {}
    local highlights = {}

    for _, row in ipairs(rows) do
        local line, spans = format_row(row, self.filters.search)
        table.insert(lines, line)
        table.insert(highlights, spans)
    end

    if not append then
        vim.api.nvim_buf_clear_namespace(self.list_buf, list_namespace, 0, -1)
    end
    set_lines(self.list_buf, lines, append)

    for index, spans in ipairs(highlights) do
        for _, span in ipairs(spans) do
            vim.api.nvim_buf_set_extmark(
                self.list_buf,
                list_namespace,
                start_row + index - 1,
                span.start_col,
                {
                    end_col = span.end_col,
                    hl_group = span.group,
                    hl_mode = "combine",
                    priority = span.group == "NurlHistoryMatch" and 120 or 100,
                }
            )
        end
    end
end

function Explorer:show_empty()
    set_lines(self.list_buf, { "No matching history entries." })
    set_lines(self.preview_buf, { "No matching history entries." })
end

---Delete the selected entry, or [count] entries from the cursor down.
function Explorer:delete_entries()
    local row = vim.api.nvim_win_get_cursor(self.list_win)[1]
    local last = math.min(row + vim.v.count1 - 1, #self.entries)
    if row > last then
        return
    end

    local count = last - row + 1
    local prompt = count == 1 and "Delete this history entry?"
        or ("Delete %d history entries?"):format(count)
    if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
        return
    end

    local ids = {}
    for i = row, last do
        table.insert(ids, self.entries[i].id)
    end

    local ok, err = pcall(history.delete, ids)
    if not ok then
        vim.notify("Failed to delete history: " .. err, vim.log.levels.ERROR)
        -- Some entries may have been deleted; show what history has now.
        self:reload()
        return
    end

    for _ = row, last do
        table.remove(self.entries, row)
    end

    if #self.entries == 0 then
        self:show_empty()
    else
        self:render_rows(self.entries, false)
        vim.api.nvim_win_set_cursor(
            self.list_win,
            { math.min(row, #self.entries), 0 }
        )
        self.preview_id = nil
        self:schedule_preview()
    end

    self:fill_window()
end

function Explorer:visible_page_size()
    return math.max(
        self.opts.page_size,
        vim.api.nvim_win_get_height(self.list_win) + page_prefetch
    )
end

function Explorer:fill_window()
    if
        self:alive()
        and self.has_more
        and not self.loading
        and #self.entries < self:visible_page_size()
    then
        self:load_page()
    end
end

-- Only unfiltered and date range pages are served by the time index. Any
-- other filter scans every entry, so it runs away from the UI.
local function scans_entries(filters)
    for key, value in pairs(filters) do
        if value ~= "" and key ~= "from" and key ~= "to" then
            return true
        end
    end
    return false
end

function Explorer:load_page()
    if not self:alive() or not self.has_more or self.loading then
        return
    end

    self.loading = true
    local generation = self.search_generation
    local cursor = self.entries[#self.entries]
    local page_size = self:visible_page_size()

    if scans_entries(self.filters) then
        vim.wo[self.list_win].winbar = self.list_winbar .. "  (searching…)"

        local ok, err = pcall(
            history.page_async,
            self.filters,
            cursor,
            page_size,
            function(rows, more, failure)
                self:finish_page(generation, rows, more, failure)
            end
        )
        if not ok then
            self:finish_page(generation, nil, nil, err)
        end
    else
        local ok, rows, more =
            pcall(history.page, self.filters, cursor, page_size)
        self:finish_page(generation, ok and rows or nil, more, not ok and rows)
    end
end

function Explorer:reload()
    if not self:alive() then
        return
    end

    self.entries = {}
    self.has_more = true
    self.loading = false
    self.search_generation = self.search_generation + 1
    self.preview_generation = self.preview_generation + 1
    self.preview_id = nil

    vim.api.nvim_buf_clear_namespace(self.list_buf, list_namespace, 0, -1)

    set_lines(self.list_buf, { "Loading history…" })
    set_lines(self.preview_buf, { "Loading request…" })

    vim.api.nvim_win_set_cursor(self.list_win, { 1, 0 })

    local active = {}

    for _, field in ipairs(filter_fields) do
        local value = self.filters[field.key]
        if value and value ~= "" then
            local display = field.key:find("body") and "(set)"
                or (value:sub(1, 40) .. (#value > 40 and "…" or ""))
            table.insert(active, field.key .. "=" .. display)
        end
    end

    self.list_winbar = (
        "Nurl: history"
        .. (#active > 0 and "  [" .. table.concat(active, ", ") .. "]" or "")
    ):gsub("%%", "%%%%")

    vim.wo[self.list_win].winbar = self.list_winbar

    self:load_page()
end

function Explorer:change_filter(field)
    if field.choices then
        vim.ui.select(vim.list_extend(vim.deepcopy(field.choices), { "any" }), {
            prompt = field.label,
        }, function(choice)
            if choice == nil or not self:alive() then
                return
            end
            self.filters[field.key] = choice ~= "any" and choice or nil
            self:reload()
        end)
        return
    end

    vim.ui.input({
        prompt = field.label .. ": ",
        default = self.filters[field.key] or "",
    }, function(value)
        if value == nil or not self:alive() then
            return
        end

        value = vim.trim(value)

        if
            field.key == "status"
            and value ~= ""
            and not value:match("^[1-5][xX][xX]$")
            and not value:match("^%d%d%d$")
        then
            vim.notify(
                "Status must be a code (404) or class (4xx)",
                vim.log.levels.WARN
            )
            return
        end

        self.filters[field.key] = value ~= "" and value or nil
        self:reload()
    end)
end

function Explorer:close()
    if not self:alive() then
        return
    end

    -- The list buffer is wiped once it is no longer displayed, which marks the
    -- explorer as closed. If closing fails, the explorer remains usable.
    if #vim.api.nvim_list_tabpages() > 1 then
        vim.api.nvim_set_current_tabpage(self.tab)
        vim.cmd.tabclose()
        return
    end

    -- The last tab page cannot be closed, so leave an empty window instead.
    if vim.api.nvim_win_is_valid(self.preview_win) then
        vim.api.nvim_win_close(self.preview_win, true)
    end
    vim.api.nvim_set_current_win(self.list_win)
    vim.cmd.enew()
end

function Explorer:open_entry(resend)
    local entry = self:selected()
    if not entry then
        return
    end

    local item = history.get(entry.id)
    if not item then
        return
    end

    if resend then
        require("nurl").send(item[2], { display = true })
        delete_hidden_buffers(self.response_buffers)
        self.response_win = nil
        self.response_buffers = nil
    else
        local previous_buffers = self.response_buffers
        self.response_win, self.response_buffers =
            require("nurl").open_history_item(item, self:response_target())
        delete_hidden_buffers(previous_buffers)
    end
end

function Explorer:action(action)
    if action == "close" then
        self:close()
    elseif action == "open" then
        self:open_entry(false)
    elseif action == "resend" then
        self:open_entry(true)
    elseif action == "delete" then
        self:delete_entries()
    elseif action == "search" then
        self:change_filter(filter_fields[1])
    elseif action == "filter" then
        vim.ui.select(filter_fields, {
            prompt = "Nurl history filter",
            format_item = function(field)
                return field.label
                    .. (
                        self.filters[field.key]
                            and " = " .. self.filters[field.key]
                        or ""
                    )
            end,
        }, function(field)
            if field and self:alive() then
                self:change_filter(field)
            end
        end)
    elseif action == "clear" then
        self.filters = {}
        self:reload()
    elseif action == "help" then
        local mappings = {}

        for lhs, name in pairs(self.opts.keys) do
            if name then
                table.insert(mappings, lhs .. "  " .. name)
            end
        end

        table.sort(mappings)
        vim.notify(
            "Nurl history explorer\n"
                .. table.concat(mappings, "\n")
                .. "\nUse j/k, gg/G to navigate."
        )
    end
end

function M.open()
    local opts = config.history.explorer
    local self = setmetatable({
        opts = opts,
        filters = {},
        entries = {},
        has_more = true,
        search_generation = 0,
    }, Explorer)

    -- Open the tab page on the list itself; :tabnew would leave an empty
    -- buffer behind.
    self.list_buf = buffer("nurl://history/list")
    vim.cmd("tab sbuffer " .. self.list_buf)
    self.tab = vim.api.nvim_get_current_tabpage()
    self.list_win = vim.api.nvim_get_current_win()
    vim.wo[self.list_win].wrap = false
    vim.wo[self.list_win].cursorline = true

    self.preview_buf = buffer("nurl://history/request")
    vim.bo[self.preview_buf].filetype = "http"
    self.preview_win = vim.api.nvim_open_win(self.preview_buf, false, {
        split = "below",
        win = self.list_win,
        height = math.max(4, math.min(12, math.floor(vim.o.lines / 3))),
    })
    vim.wo[self.preview_win].wrap = true
    vim.wo[self.preview_win].winbar = "Nurl: request preview"
    self.preview_generation = 0

    for lhs, action in pairs(opts.keys) do
        if action then
            vim.keymap.set("n", lhs, function()
                self:action(action)
            end, {
                buffer = self.list_buf,
                silent = true,
                desc = "Nurl history: " .. action,
            })
        end
    end

    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = self.list_buf,
        callback = function()
            if self:alive() then
                local row = vim.api.nvim_win_get_cursor(self.list_win)[1]
                self:schedule_preview()
                if row >= #self.entries - page_prefetch then
                    self:load_page()
                end
            end
        end,
    })

    self.resize_autocmd = vim.api.nvim_create_autocmd({
        "WinResized",
        "VimResized",
        "TabEnter",
    }, {
        callback = function()
            if self:alive() and vim.api.nvim_get_current_tabpage() == self.tab then
                self:fill_window()
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = self.list_buf,
        once = true,
        callback = function()
            self.closed = true
            vim.api.nvim_del_autocmd(self.resize_autocmd)
        end,
    })

    self:reload()
end

return M

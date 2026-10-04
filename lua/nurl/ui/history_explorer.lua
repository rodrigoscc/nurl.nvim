local uv = vim.uv or vim.loop

local config = require("nurl.config")
local dates = require("nurl.utils.dates")
local history = require("nurl.history")
local highlights = require("nurl.ui.highlights")
local http_message = require("nurl.ui.http_message")
local numbers = require("nurl.utils.numbers")
local ResponseView = require("nurl.ui.response_view")
local Spinner = require("nurl.ui.spinner")
local strings = require("nurl.utils.strings")

local M = {}
local list_namespace = vim.api.nvim_create_namespace("nurl.history_explorer")
local page_prefetch = 5
-- Requests that took at least this many seconds stand out in the list.
local slow_duration = 1
-- Actions whose keys are shown in the winbar, in this order.
local hint_actions = { "open", "search", "filter", "help" }

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

---Hide line numbers, sign and fold columns, and other window decorations of
---the user. Set locally, so a buffer opened later in the window gets the
---user's options back.
local function minimal_window(win)
    local wo = vim.wo[win][0]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.foldcolumn = "0"
    wo.statuscolumn = ""
    wo.cursorcolumn = false
    wo.colorcolumn = ""
    wo.list = false
    wo.spell = false
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

    -- The day is shown in a header above the first entry of each day.
    add(
        ("%-5s"):format(row.time:match("T(%d%d:%d%d)") or row.time),
        "NurlHistoryTime"
    )
    add("  ")
    add(string.format("%-7s", row.method), "NurlHistoryMethod")
    add("  ")
    add(
        string.format("%s %-3d", highlights.status_icon(row.status), row.status),
        highlights.status_group(row.status)
    )
    add("  ")
    -- "123.45s" is the widest duration worth aligning.
    add(
        ("%7s"):format(numbers.format_duration(row.duration)),
        (row.duration or 0) >= slow_duration and "NurlHistoryDurationSlow"
            or "NurlHistoryDuration"
    )
    add("  ")
    local label_start = length
    local has_title = row.title and row.title ~= ""

    if has_title then
        add(row.title:gsub("%c", " "), "NurlHistoryTitle")
        add("  ")
    end

    add(
        row.url:gsub("^%w+://", ""):gsub("%c", " "),
        has_title and "NurlHistoryUrlDim" or "NurlHistoryUrl"
    )

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

---A winbar segment showing text with a highlight group.
local function hl(group, text)
    return ("%%#%s#%s%%*"):format(group, strings.escape_percentage(text))
end

---Winbar hints for the main actions, with the keys they are mapped to.
local function key_hints(mappings)
    local keys = {}
    for lhs, action in pairs(mappings) do
        if action and (not keys[action] or lhs < keys[action]) then
            keys[action] = lhs
        end
    end

    local hints = {}
    for _, action in ipairs(hint_actions) do
        if keys[action] then
            table.insert(
                hints,
                hl("NurlHistoryKey", keys[action])
                    .. " "
                    .. hl("NurlHistoryKeyDesc", action)
            )
        end
    end

    return table.concat(hints, "  ")
end

local Explorer = {}
Explorer.__index = Explorer

---Open explorers by list buffer, for the winbar expression of the spinner.
---@type table<integer, table>
local explorers = {}

---The spinner frame of the explorer whose winbar is drawn. Evaluated by the
---winbar on each redraw, so that spinner ticks do not rebuild the winbar.
---@return string
function M.spinner()
    local self = explorers[vim.api.nvim_get_current_buf()]
    if not self or not self.searching then
        return ""
    end
    return hl(config.highlight.groups.spinner, self.spinner_frame)
end

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
    self:update_preview_winbar(entry)
    local ok, request = pcall(history.get_request, entry.id)
    if ok and request then
        ok, request = pcall(http_message.render, request)
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

---Show when the previewed request was sent in the winbar of the preview.
---@param entry? nurl.HistorySummary
function Explorer:update_preview_winbar(entry)
    -- The user may have opened another buffer in the preview window.
    if
        not vim.api.nvim_win_is_valid(self.preview_win)
        or vim.api.nvim_win_get_buf(self.preview_win) ~= self.preview_buf
    then
        return
    end

    local sent = ""
    if entry then
        sent = hl("NurlHistoryDay", dates.format_date(entry.time))
            .. "  "
            .. hl(
                "NurlHistoryTime",
                entry.time:match("T(%d%d:%d%d:%d%d)") or ""
            )
    end

    -- Local to the preview buffer, so another buffer opened in the window
    -- does not show it.
    vim.wo[self.preview_win][0].winbar = sent
        .. "%="
        .. hl(config.highlight.groups.winbar_title, "󰈈 Preview")
        .. " "
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

---The window of the last response opened from the explorer, while it still
---shows that response. Opening another one reuses it.
---@return integer?
function Explorer:response_target()
    local view = self.response_view
    if not view or ResponseView.for_win(view.win) ~= view then
        return nil
    end

    if view:type_of(vim.api.nvim_win_get_buf(view.win)) then
        return view.win
    end
end

function Explorer:start_spinner()
    self.searching = true
    self.spinner_frame = self.spinner:frame()
    -- Created on the first search, so opening the explorer cannot leak it.
    self.spinner_timer = self.spinner_timer or assert(uv.new_timer())
    self.spinner_timer:start(
        50,
        50,
        vim.schedule_wrap(function()
            if not self:alive() then
                self:stop_spinner()
                return
            end
            -- A tick queued before the spinner stopped.
            if not self.searching then
                return
            end
            self.spinner_frame = self.spinner:frame()
            vim.api.nvim_win_call(self.list_win, function()
                vim.cmd.redrawstatus()
            end)
        end)
    )
end

function Explorer:stop_spinner()
    self.searching = false
    if self.spinner_timer then
        self.spinner_timer:stop()
    end
end

function Explorer:finish_page(generation, rows, more, err)
    if not self:alive() then
        self:stop_spinner()
        return
    end
    if generation ~= self.search_generation then
        return
    end

    self.loading = false
    self:stop_spinner()

    if err then
        vim.notify("Failed to load history: " .. err, vim.log.levels.ERROR)
        self.has_more = false
        self.failed = true
        self:update_winbar()
        if #self.entries == 0 then
            set_lines(
                self.list_buf,
                { "History search failed. Press F to change filters." }
            )
            set_lines(self.preview_buf, { "Unable to load request preview." })
            self:update_preview_winbar()
        end
        return
    end

    local was_empty = #self.entries == 0

    self.has_more = more

    vim.list_extend(self.entries, rows)
    self:update_winbar()

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
    local start_row = append and vim.api.nvim_buf_line_count(self.list_buf) or 0
    local lines = {}
    local line_spans = {}

    for _, row in ipairs(rows) do
        local line, spans = format_row(row, self.filters.search)
        table.insert(lines, line)
        table.insert(line_spans, spans)
    end

    if not append then
        vim.api.nvim_buf_clear_namespace(self.list_buf, list_namespace, 0, -1)
    end
    set_lines(self.list_buf, lines, append)

    for index, spans in ipairs(line_spans) do
        local line = start_row + index - 1
        local previous = self.entries[line]
        local entry = self.entries[line + 1]

        -- The winbar names the day of the top row, so the first entry needs
        -- no header. One above it would also be hidden at the top of the
        -- window.
        if previous and previous.time:sub(1, 10) ~= entry.time:sub(1, 10) then
            vim.api.nvim_buf_set_extmark(
                self.list_buf,
                list_namespace,
                line,
                0,
                {
                    virt_lines = {
                        {
                            {
                                dates.format_day(entry.time, self.now),
                                "NurlHistoryDay",
                            },
                        },
                    },
                    virt_lines_above = true,
                }
            )
        end

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

---The day of the entry at the top of the list window.
---@return string
function Explorer:top_day()
    local entry = self.entries[vim.fn.line("w0", self.list_win)]
    return entry and dates.format_day(entry.time, self.now) or ""
end

function Explorer:show_empty()
    set_lines(self.list_buf, { "No matching history entries." })
    set_lines(self.preview_buf, { "No matching history entries." })
    self:update_preview_winbar()
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

    self:update_winbar()
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
        self:start_spinner()
        self:update_winbar()

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
    self.failed = false
    self:stop_spinner()
    -- Days are named relative to when the list was loaded.
    self.now = os.time()
    self.search_generation = self.search_generation + 1
    self.preview_generation = self.preview_generation + 1
    self.preview_id = nil

    vim.api.nvim_buf_clear_namespace(self.list_buf, list_namespace, 0, -1)

    set_lines(self.list_buf, { "Loading history…" })
    set_lines(self.preview_buf, { "Loading request…" })
    self:update_preview_winbar()

    vim.api.nvim_win_set_cursor(self.list_win, { 1, 0 })

    self:update_winbar()
    self:load_page()
end

---Show the day of the top row, active filters with their match count, a
---spinner while searching and the main keys in the winbar of the list.
function Explorer:update_winbar()
    if not self:alive() then
        return
    end

    self.day = self:top_day()
    local parts = {}

    for _, field in ipairs(filter_fields) do
        local value = self.filters[field.key]
        if value and value ~= "" then
            local display = field.key:find("body") and "(set)"
                or (
                    vim.fn.strcharpart(value, 0, 40)
                    .. (vim.fn.strchars(value) > 40 and "…" or "")
                )
            table.insert(
                parts,
                hl(
                    "NurlHistoryFilter",
                    " " .. field.key .. "=" .. display .. " "
                )
            )
        end
    end

    -- Unfiltered, the count only tells how many entries are loaded so far.
    local count = #self.entries
    if #parts > 0 and (count > 0 or not (self.loading or self.failed)) then
        table.insert(
            parts,
            hl(
                "NurlHistoryCount",
                ("%d%s %s"):format(
                    count,
                    -- A failed page leaves older entries unlisted.
                    (self.has_more or self.failed) and "+" or "",
                    count == 1 and "match" or "matches"
                )
            )
        )
    end

    if self.searching then
        table.insert(
            parts,
            "%{%v:lua.require'nurl.ui.history_explorer'.spinner()%} "
                .. hl("NurlHistoryCount", "searching")
        )
    end

    if self.failed then
        table.insert(
            parts,
            hl(config.highlight.groups.winbar_error, "󰅚 failed to load")
        )
    end

    if self.hints ~= "" then
        table.insert(parts, self.hints)
    end
    table.insert(
        parts,
        hl(config.highlight.groups.winbar_title, "󰋚 History")
    )

    -- The day lines up with the times of the rows, like the day headers.
    -- Filters are cut first when the window is too narrow.
    vim.wo[self.list_win].winbar = hl("NurlHistoryDay", self.day)
        .. "%=%<"
        .. table.concat(parts, "  ")
        .. " "
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
        self.client.send(item[2], { display = true })
        self.response_view = nil
    else
        self.response_view =
            self.client.open_history_item(item, self:response_target())
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

---What the explorer needs to send requests and show saved ones.
---@class nurl.HistoryExplorerClient
---@field send fun(request: nurl.Request, opts: nurl.SendOpts): nurl.RequestHandle
---@field open_history_item fun(item: nurl.HistoryItem, win?: integer): nurl.ResponseView

---@param client nurl.HistoryExplorerClient
function M.open(client)
    local opts = config.history.explorer
    local self = setmetatable({
        client = client,
        opts = opts,
        filters = {},
        entries = {},
        has_more = true,
        search_generation = 0,
        spinner = Spinner:new(),
        hints = key_hints(opts.keys),
    }, Explorer)

    -- Open the tab page on the list itself; :tabnew would leave an empty
    -- buffer behind.
    self.list_buf = buffer("nurl://history/list")
    vim.cmd("tab sbuffer " .. self.list_buf)
    self.tab = vim.api.nvim_get_current_tabpage()
    self.list_win = vim.api.nvim_get_current_win()
    minimal_window(self.list_win)
    vim.wo[self.list_win].wrap = false
    vim.wo[self.list_win].cursorline = true

    self.preview_buf = buffer("nurl://history/request")
    vim.bo[self.preview_buf].filetype = "http"
    self.preview_win = vim.api.nvim_open_win(self.preview_buf, false, {
        split = "below",
        win = self.list_win,
        height = math.max(4, math.min(12, math.floor(vim.o.lines / 3))),
    })
    minimal_window(self.preview_win)
    vim.wo[self.preview_win][0].cursorline = false
    vim.wo[self.preview_win].wrap = true
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
            if
                self:alive()
                and vim.api.nvim_get_current_tabpage() == self.tab
            then
                self:fill_window()
            end
        end,
    })

    self.scroll_autocmd = vim.api.nvim_create_autocmd("WinScrolled", {
        pattern = tostring(self.list_win),
        callback = function()
            if self:alive() and self:top_day() ~= self.day then
                self:update_winbar()
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = self.list_buf,
        once = true,
        callback = function()
            self.closed = true
            explorers[self.list_buf] = nil
            vim.api.nvim_del_autocmd(self.resize_autocmd)
            vim.api.nvim_del_autocmd(self.scroll_autocmd)
            if self.spinner_timer then
                self.spinner_timer:stop()
                self.spinner_timer:close()
                self.spinner_timer = nil
            end
        end,
    })

    explorers[self.list_buf] = self

    -- Set once the list is in its window and mapped, so FileType autocmds of
    -- the user can change its window options and keymaps.
    vim.bo[self.list_buf].filetype = "nurl-history"

    self:reload()
end

return M

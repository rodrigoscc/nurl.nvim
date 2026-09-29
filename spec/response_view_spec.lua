local ResponseView = require("nurl.ui.response_view")
local RequestHandle = require("nurl.app.handle")
local Curl = require("nurl.curl")

---A completed request, like one opened from history.
---@param status_code? integer
---@return nurl.RequestHandle
local function completed_handle(status_code)
    return RequestHandle:rebuild(
        "2026-09-26T10:00:00",
        { method = "GET", url = "https://example.org", headers = {} },
        {
            status_code = status_code or 200,
            reason_phrase = "OK",
            protocol = "HTTP/1.1",
            headers = {},
            body = "",
            time = {},
            size = {},
            speed = {},
        },
        Curl:new({
            args = {},
            result = { code = 0, signal = 0, stdout = "", stderr = "" },
        })
    )
end

---@param bufnrs table<nurl.BufferType, integer>
---@return integer
local function valid_count(bufnrs)
    local count = 0
    for _, bufnr in pairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            count = count + 1
        end
    end
    return count
end

---Close a view's window and wait for the view to clean up after it.
---@param view nurl.ResponseView
local function close_window(view)
    vim.api.nvim_win_close(view.win, true)
    assert(vim.wait(1000, function()
        return ResponseView.for_win(view.win) == nil
    end))
end

describe("response view", function()
    before_each(function()
        require("nurl").setup({ formatters = {} })
    end)

    after_each(function()
        vim.cmd("silent! only")
        vim.cmd.enew()
    end)

    it("creates unlisted buffers, one per part", function()
        local listed = #vim.fn.getbufinfo({ buflisted = 1 })

        local view = ResponseView.open(completed_handle())

        assert.are.equal(6, valid_count(view.buffers))
        assert.are.equal(listed, #vim.fn.getbufinfo({ buflisted = 1 }))
        for type, bufnr in pairs(view.buffers) do
            assert.are.equal(view, ResponseView.for_buf(bufnr))
            assert.are.same({ buffer_type = type }, vim.b[bufnr].nurl_data)
        end
    end)

    it("replaces its buffers when showing another request", function()
        local view = ResponseView.open(completed_handle(200))
        local first = view.buffers

        local second = completed_handle(404)
        local reused = ResponseView.open(second, { win = view.win })

        assert.are.equal(view, reused)
        assert.are.equal(second, view.handle)
        assert.are.equal(0, valid_count(first))
        assert.are.equal(6, valid_count(view.buffers))
        assert.are.equal(view.buffers.body, vim.api.nvim_win_get_buf(view.win))
    end)

    it("keeps the focused part when showing another request", function()
        local view = ResponseView.open(completed_handle())

        view:show(completed_handle(), "headers")

        assert.are.equal(
            "headers",
            view:type_of(vim.api.nvim_win_get_buf(view.win))
        )
    end)

    it("deletes its buffers when its window closes", function()
        local view = ResponseView.open(completed_handle())
        local bufnrs = view.buffers

        close_window(view)

        assert.are.equal(0, valid_count(bufnrs))
        for _, bufnr in pairs(bufnrs) do
            assert.is_nil(ResponseView.for_buf(bufnr))
        end
    end)

    it("leaves a buffer shown in another window until it is hidden", function()
        local view = ResponseView.open(completed_handle())
        local body = view.buffers.body
        vim.cmd("sbuffer " .. body)
        local other = vim.api.nvim_get_current_win()

        close_window(view)

        assert.is_true(vim.api.nvim_buf_is_valid(body))
        vim.api.nvim_win_close(other, true)
        assert.is_false(vim.api.nvim_buf_is_valid(body))
    end)

    it("cycles through the parts in the configured order", function()
        local view = ResponseView.open(completed_handle())
        local function shown()
            return view:type_of(vim.api.nvim_win_get_buf(view.win))
        end

        view:cycle(view.win, 1)
        assert.are.equal("headers", shown())
        view:cycle(view.win, -1)
        assert.are.equal("body", shown())
        view:cycle(view.win, -1)
        assert.are.equal("test", shown())
    end)

    it("shows the new info in an open secondary split", function()
        local view = ResponseView.open(completed_handle(), { enter = true })
        view:toggle_secondary("info", { split = "below", height = 5 })
        local split = vim.fn.win_findbuf(view.buffers.info)[1]

        view:show(completed_handle())

        assert.are.equal(view.buffers.info, vim.api.nvim_win_get_buf(split))
    end)

    it("renders the winbar only in response windows", function()
        local view = ResponseView.open(completed_handle(404))
        vim.cmd.new()
        local plain = vim.api.nvim_get_current_win()

        local function eval(win)
            return vim.api.nvim_eval_statusline(
                "%{%v:lua.Nurl.winbar.status_code()%}%{%v:lua.Nurl.winbar.tabs()%}",
                { winid = win, use_winbar = true }
            ).str
        end

        assert.matches("404", eval(view.win))
        assert.are.equal("", eval(plain))
    end)
end)

describe("response view with a body saved to a file", function()
    local file

    ---A completed request whose body was saved to the file.
    ---@return nurl.RequestHandle
    local function file_handle()
        return RequestHandle:rebuild(
            "2026-09-26T10:00:00",
            { method = "GET", url = "https://example.org", headers = {} },
            {
                status_code = 200,
                reason_phrase = "OK",
                protocol = "HTTP/1.1",
                headers = { ["Content-Type"] = "image/png" },
                body = "",
                body_file = file,
                time = {},
                size = {},
                speed = {},
            },
            Curl:new({
                args = {},
                result = { code = 0, signal = 0, stdout = "", stderr = "" },
            })
        )
    end

    ---Open a view and wait for its body, which is rendered on the next loop.
    ---@param opts? nurl.ResponseViewOpts
    ---@return nurl.ResponseView
    local function open(opts)
        local view = ResponseView.open(file_handle(), opts)
        vim.wait(50)
        return view
    end

    ---@param bufnr integer
    ---@return string[]
    local function lines(bufnr)
        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end

    before_each(function()
        require("nurl").setup({ formatters = {} })
        file = vim.fn.tempname() .. ".png"
        vim.fn.writefile({ "png" }, file)
    end)

    after_each(function()
        vim.cmd("silent! only")
        vim.cmd.enew()
        vim.cmd("silent! %bwipeout!")
        vim.fn.delete(file)
    end)

    it("names the body buffer after the file", function()
        local view = open()

        -- Image previews such as Snacks.image find the file by this name.
        assert.are.equal(file, vim.api.nvim_buf_get_name(view.buffers.body))
    end)

    it("keeps the body buffer when rendering it again", function()
        local view = open()

        view:update()
        vim.wait(50)

        assert.is_true(vim.api.nvim_buf_is_valid(view.buffers.body))
        assert.is_true(vim.api.nvim_win_is_valid(view.win))
        assert.are.equal(file, vim.api.nvim_buf_get_name(view.buffers.body))
    end)

    it("shows the path when another view already shows the file", function()
        local first = open()
        local second = open()

        assert.is_true(vim.api.nvim_win_is_valid(first.win))
        assert.are.equal(first.buffers.body, vim.api.nvim_win_get_buf(first.win))
        assert.are.equal(file, vim.api.nvim_buf_get_name(first.buffers.body))
        assert.are.same(
            { "[Body saved to file: " .. file .. "]" },
            lines(second.buffers.body)
        )
    end)

    it("leaves a buffer the user opened on the file alone", function()
        vim.cmd.edit(file)
        local user_buf = vim.api.nvim_get_current_buf()

        local view = open()

        assert.is_true(vim.api.nvim_buf_is_valid(user_buf))
        assert.are.equal(file, vim.api.nvim_buf_get_name(user_buf))
        assert.are.same(
            { "[Body saved to file: " .. file .. "]" },
            lines(view.buffers.body)
        )
    end)
end)

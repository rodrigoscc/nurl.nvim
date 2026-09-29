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

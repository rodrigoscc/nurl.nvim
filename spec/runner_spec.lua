local runner = require("nurl.app.runner")
local env_project = require("nurl.env.project")
local process = require("nurl.infra.process")

local uv = vim.uv or vim.loop

---Serve one canned response to every connection, once the request headers
---arrive. Without a response, connections stay open until closed.
---@param response? string
---@return string url, fun() close
local function serve(response)
    local server = assert(uv.new_tcp())
    server:bind("127.0.0.1", 0)
    server:listen(16, function()
        local client = assert(uv.new_tcp())
        server:accept(client)

        local received = ""
        client:read_start(function(_, data)
            received = received .. (data or "")
            if response and received:find("\r\n\r\n", 1, true) then
                client:read_stop()
                client:write(response, function()
                    client:close()
                end)
            end
        end)
    end)

    local url = ("http://127.0.0.1:%d/"):format(server:getsockname().port)
    return url,
        function()
            if not server:is_closing() then
                server:close()
            end
        end
end

local OK = "HTTP/1.1 201 Created\r\n"
    .. "Content-Type: text/plain\r\n"
    .. "Content-Length: 5\r\n"
    .. "\r\n"
    .. "hello"

describe("runner", function()
    local url, close
    local notifications
    local notify = vim.notify

    before_each(function()
        url, close = serve(OK)
        notifications = {}
        vim.notify = function(msg)
            table.insert(notifications, msg)
        end
    end)

    after_each(function()
        close()
        vim.notify = notify
        env_project.reload(env_project.current().path)
    end)

    it("sends the request and parses the response", function()
        local out = runner.run({ url }):wait(5000)

        assert.are.equal(201, out.response.status_code)
        assert.are.equal("hello", out.response.body)
    end)

    it("sends the query of a shorthand url as written", function()
        local request_line
        local server = assert(uv.new_tcp())
        server:bind("127.0.0.1", 0)
        server:listen(16, function()
            local client = assert(uv.new_tcp())
            server:accept(client)
            client:read_start(function(_, data)
                if data then
                    client:read_stop()
                    request_line = data:match("^[^\r\n]+")
                    client:write(OK, function()
                        client:close()
                    end)
                end
            end)
        end)
        local base = ("http://127.0.0.1:%d/p"):format(server:getsockname().port)

        runner
            .run({
                base .. "?q=a%20b&x=1+2&a=b=c&flag",
                query = { ["my key"] = "c d" },
            })
            :wait(5000)
        server:close()

        assert.are.equal(
            "GET /p?q=a%20b&x=1+2&a=b=c&flag&my%20key=c+d HTTP/1.1",
            request_line
        )
    end)

    it("runs the hooks, the tests and the callbacks in order", function()
        local calls = {}
        local function record(name)
            return function(...)
                table.insert(calls, name)
                return ...
            end
        end

        local project = env_project.current()
        project.envs = {
            test = {
                pre_hook = function(next)
                    table.insert(calls, "env pre_hook")
                    next()
                end,
                post_hook = record("env post_hook"),
            },
        }
        project.active_name = "test"

        runner
            .run({
                url,
                pre_hook = function(next)
                    table.insert(calls, "request pre_hook")
                    next()
                end,
                test = record("test"),
                post_hook = record("request post_hook"),
            }, {
                on_start = record("on_start"),
                callback = record("callback"),
                on_complete = record("on_complete"),
            })
            :wait(5000)

        assert.are.same({
            "env pre_hook",
            "request pre_hook",
            "on_start",
            "test",
            "request post_hook",
            "env post_hook",
            "callback",
            "on_complete",
        }, calls)
    end)

    it("marks the request done after the post hooks and callback", function()
        local handle
        local done = {}

        runner
            .run({
                url,
                post_hook = function()
                    done.post_hook = handle:is_done()
                end,
            }, {
                on_start = function(h)
                    handle = h
                end,
                callback = function()
                    done.callback = handle:is_done()
                end,
                on_complete = function()
                    done.on_complete = handle:is_done()
                end,
            })
            :wait(5000)

        assert.are.same(
            { post_hook = false, callback = false, on_complete = true },
            done
        )
    end)

    it("keeps going when a hook or the callback fails", function()
        local completed = false

        local handle = runner.run({
            url,
            post_hook = function()
                error("post hook error")
            end,
        }, {
            callback = function()
                error("callback error")
            end,
            on_complete = function()
                completed = true
            end,
        })
        handle:wait(5000)

        assert.are.equal("completed", handle.status)
        assert.is_true(completed)
        assert.are.equal(2, #notifications)
        assert.matches(
            "Request post hook failed: .*post hook error",
            notifications[1]
        )
        assert.matches("Callback failed: .*callback error", notifications[2])
    end)

    it("returns the window from on_start in the output", function()
        local out = runner
            .run({ url }, {
                on_start = function()
                    return 1000
                end,
            })
            :wait(5000)

        assert.are.equal(1000, out.win)
    end)

    it("raises an invalid request before starting it", function()
        local started = false

        assert.has_error(function()
            runner.run({ url, curl_args = { "--output", "file" } }, {
                on_start = function()
                    started = true
                end,
            })
        end)
        assert.is_false(started)
    end)

    it("fails without running the tests when curl fails", function()
        close()
        local tested = false

        local handle = runner.run({
            url,
            test = function()
                tested = true
            end,
        })
        local out = handle:wait(5000)

        assert.are.equal("failed", handle.status)
        assert.is_nil(out.response)
        assert.are_not.equal(0, out.curl.result.code)
        assert.is_false(tested)
    end)

    it("cancels a running request", function()
        local hanging_url, close_hanging = serve(nil)

        local handle = runner.run({ hanging_url })
        vim.wait(5000, function()
            return handle.status == "started"
        end)
        handle:cancel()
        handle:wait(5000)
        close_hanging()

        assert.are.equal("cancelled", handle.status)
    end)

    it("fails when curl's output cannot be parsed", function()
        local run = process.run
        process.run = function(_, on_exit)
            on_exit({ code = 0, signal = 0, stdout = "hello", stderr = "" })
            return { pid = 1 }
        end

        local ok, handle = pcall(runner.run, { url })
        process.run = run
        assert(ok, handle)
        handle:wait(5000)

        assert.are.equal("failed", handle.status)
        assert.matches("Could not parse the response", notifications[1])
    end)
end)

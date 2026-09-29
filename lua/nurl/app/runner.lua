local environments = require("nurl.environments")
local requests = require("nurl.core.request")
local Curl = require("nurl.core.curl")
local config = require("nurl.config")
local responses = require("nurl.core.response")
local body_store = require("nurl.infra.body_store")
local process = require("nurl.infra.process")
local RequestHandle = require("nurl.app.handle")
local TestReport = require("nurl.test.report")
local ctx = require("nurl.test.ctx")

local M = {}

---@class nurl.RunOpts
---@field on_start? fun(handle: nurl.RequestHandle): integer? Called after the pre hooks, right before curl starts. Returns the window showing the request, if any.
---@field callback? fun(out: nurl.RequestOut) The caller's callback, run after the post hooks
---@field on_complete? fun(handle: nurl.RequestHandle, out: nurl.RequestOut) Called last, once the request is done

---Call fn, reporting an error instead of raising it, so that one failing hook
---does not stop the ones after it.
---@param name string
---@param fn? function
local function call_safely(name, fn, ...)
    if not fn then
        return
    end

    local ok, err = pcall(fn, ...)
    if not ok then
        vim.notify(name .. " failed: " .. err, vim.log.levels.ERROR)
    end
end

---@param hook? fun(next: fun(), input: nurl.RequestInput)
---@param input nurl.RequestInput
---@param next fun()
local function run_pre_hook(hook, input, next)
    if hook then
        hook(next, input)
    else
        next()
    end
end

---Parse curl's output, saving a body that cannot be displayed to a file.
---@param curl nurl.Curl with its result
---@return nurl.Response
local function parse_response(curl)
    local response = responses.parse(curl.result.stdout, curl.result.stderr)

    if not responses.is_displayable(response) then
        body_store.save(response, curl, config.responses_files_dir)
    end

    return response
end

---@param request nurl.Request
---@param response nurl.Response
---@return nurl.TestReport
local function run_tests(request, response)
    local report = TestReport:new()

    local ok, err = pcall(request.test, ctx.build_ctx(report), response)
    if not ok then
        report:error(err)
    end

    return report
end

---Send a request: run the pre hooks, curl, the tests and the post hooks.
---@param request nurl.SuperRequest | nurl.Request
---@param opts? nurl.RunOpts
---@return nurl.RequestHandle
function M.run(request, opts)
    opts = opts or {}

    local expanded = requests.expand(request)
    -- Request is already fully expanded here.
    ---@cast expanded nurl.Request

    local handle = RequestHandle:new(expanded)

    ---@param curl nurl.Curl
    ---@param win? integer
    local function complete(curl, win)
        local result = curl.result
        ---@cast result vim.SystemCompleted

        local response, test_report
        local finish = handle._resolve

        local curl_interrupted = result.signal ~= 0
        local curl_error = result.signal == 0 and result.code ~= 0

        if curl_interrupted then
            finish = handle._cancelled
        elseif curl_error then
            finish = handle._failed
        else
            local ok, parsed = pcall(parse_response, curl)
            if ok then
                response = parsed

                if expanded.test then
                    test_report = run_tests(expanded, response)
                end
            else
                vim.notify(
                    "Could not parse the response: " .. parsed,
                    vim.log.levels.ERROR
                )
                finish = handle._failed
            end
        end

        ---@type nurl.RequestOut
        local out = {
            request = expanded,
            response = response,
            curl = curl,
            win = win,
            test_report = test_report,
        }

        call_safely("Request post hook", expanded.post_hook, out)
        call_safely("Environment post hook", environments.get_post_hook(), out)
        call_safely("Callback", opts.callback, out)

        -- The request is done once everything above ran. The hooks and the
        -- callback cannot raise, so it always gets here.
        finish(handle, response, curl, test_report)

        call_safely("Completing the request", opts.on_complete, handle, out)
    end

    local function send()
        -- Build the command first, so that an invalid request fails before
        -- anything is shown.
        local curl = Curl.build(expanded)

        local win = opts.on_start and opts.on_start(handle) or nil

        local system = process.run(curl:cmd(), function(result)
            curl.result = result

            vim.schedule(function()
                complete(curl, win)
            end)
        end)

        handle:_started(system.pid, win)
    end

    ---@type nurl.RequestInput
    local input = { request = expanded }

    run_pre_hook(environments.get_pre_hook(), input, function()
        run_pre_hook(expanded.pre_hook, input, send)
    end)

    return handle
end

return M

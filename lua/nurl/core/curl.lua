local request_model = require("nurl.core.request")
local tables = require("nurl.utils.tables")

---@class nurl.Curl
---@field args string[]
---@field result? vim.SystemCompleted
local Curl = {}

function Curl:new(o)
    o = o or {}
    o = setmetatable(o, self)
    self.__index = self
    return o
end

---@return string[]
function Curl:cmd()
    return vim.list_extend({ "curl" }, self.args)
end

function Curl:string()
    local args = vim.iter(self.args)
        :map(function(arg)
            return vim.fn.shellescape(arg)
        end)
        :totable()
    return "curl " .. table.concat(args, " ")
end

local OUTPUT_FLAGS = {
    -- Redirect output
    "-o",
    "--output",
    "-O",
    "--remote-name",
    "-J",
    "--remote-header-name",

    -- Add extra output
    "-v",
    "--verbose",
    "--trace",
    "--trace-ascii",
    "-D",
    "--dump-header",

    -- Conflict with internal flags
    "-w",
    "--write-out",
    "--no-include",
    "--progress-meter",
    -- size_header still counts the hidden headers, which splits the body wrong
    "--suppress-connect-headers",
}

local function contains_output_flags(extra_args)
    return vim.tbl_contains(OUTPUT_FLAGS, function(output_flag)
        return vim.tbl_contains(extra_args, function(arg)
            -- consider either --flag or --flag=something
            return arg == output_flag or string.find(arg, output_flag .. "=")
        end, { predicate = true })
    end, { predicate = true })
end

---The curl command sending a request.
---@param request nurl.Request
---@return nurl.Curl
function Curl.build(request)
    local url = request_model.build_url(request.url)
    local args = { "--request", request.method, url }

    if request.auth then
        if request.auth.type == "basic" then
            table.insert(args, "--user")
            table.insert(
                args,
                ("%s:%s"):format(
                    request.auth.username or "",
                    request.auth.password or ""
                )
            )
        else
            error("Only basic auth is supported.")
        end
    end

    if request.query then
        local query_items = {}
        for k, v in tables.sorted_pairs(request.query) do
            -- curl encodes the value after "=", but expects the name to be
            -- encoded already.
            local name = vim.uri_encode(tostring(k))
            if type(v) == "table" then
                for _, value_item in ipairs(v) do
                    table.insert(query_items, name .. "=" .. value_item)
                end
            else
                table.insert(query_items, name .. "=" .. v)
            end
        end

        for _, item in ipairs(query_items) do
            table.insert(args, "--url-query")
            table.insert(args, item)
        end
    end

    if request.data then
        local data

        if type(request.data) == "table" then
            data = vim.json.encode(request.data)

            -- If data is table we will be sending a json in data.
            -- We won't use --json as it requires a relatively new version of curl.
            table.insert(args, "--header")
            table.insert(args, "Content-Type: application/json")
        else
            data = request.data
        end

        table.insert(args, "--data")
        table.insert(args, data)
    elseif request.form then
        local form_items = {}

        for k, v in tables.sorted_pairs(request.form) do
            table.insert(form_items, k .. "=" .. v)
        end

        for _, item in ipairs(form_items) do
            table.insert(args, "--form")
            table.insert(args, item)
        end
    elseif request.data_urlencode then
        local data_items = {}

        for k, v in tables.sorted_pairs(request.data_urlencode) do
            table.insert(data_items, k .. "=" .. v)
        end

        for _, item in ipairs(data_items) do
            table.insert(args, "--data-urlencode")
            table.insert(args, item)
        end
    end

    for k, v in tables.sorted_pairs(request.headers) do
        if type(v) == "table" then
            for _, item in ipairs(v) do
                local header = k .. ": " .. item
                table.insert(args, "--header")
                table.insert(args, header)
            end
        else
            local header = k .. ": " .. v
            table.insert(args, "--header")
            table.insert(args, header)
        end
    end

    table.insert(args, "--include")
    table.insert(args, "--no-progress-meter")

    table.insert(args, "--write-out")
    table.insert(
        args,
        "%{stderr}%{time_appconnect},%{time_connect},%{time_namelookup},%{time_pretransfer},%{time_redirect},%{time_starttransfer},%{time_total},%{size_download},%{size_header},%{size_request},%{size_upload},%{speed_download},%{speed_upload}"
    )

    if request.curl_args ~= nil then
        if contains_output_flags(request.curl_args) then
            error(
                "Blocked curl flags detected: these flags interfere with response parsing"
            )
        end

        vim.list_extend(args, request.curl_args)
    end

    return Curl:new({ args = args })
end

return Curl

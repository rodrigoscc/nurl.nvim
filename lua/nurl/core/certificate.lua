---The TLS certificate chain of a response, which curl prints with %{certs}.
local M = {}

---@class nurl.Certificate
---@field subject? string
---@field common_name? string the subject's CN, or the whole subject without one
---@field issuer? string
---@field san? string subject alternative names
---@field start_date? string as the TLS backend formats it
---@field expire_date? string as the TLS backend formats it
---@field expires_at? integer seconds since the epoch, nil if expire_date is in an unknown format

---@class nurl.ResponseTls
---@field verify_result integer 0 when the certificate was verified
---@field verify_reason? string why it was not verified, nil when it was
---@field certs nurl.Certificate[] the chain, starting with the server's

-- The chain spans many lines, so curl prints it between markers.
M.START = "<<nurl-certs"
M.END = "nurl-certs>>"

---The --write-out text printing the chain, ending with a newline. Curl turns
---"\n" into a newline, which keeps the command on one line to copy.
---@return string
function M.write_out()
    return M.START .. "\\n%{certs}" .. M.END .. "\\n"
end

-- Fields of %{certs} kept for each certificate. Others, like the extensions
-- and the PEM, are left out.
local fields = {
    ["Subject"] = "subject",
    ["Issuer"] = "issuer",
    ["X509v3 Subject Alternative Name"] = "san",
    ["Start date"] = "start_date",
    ["Expire date"] = "expire_date",
}

local months = {
    Jan = 1,
    Feb = 2,
    Mar = 3,
    Apr = 4,
    May = 5,
    Jun = 6,
    Jul = 7,
    Aug = 8,
    Sep = 9,
    Oct = 10,
    Nov = 11,
    Dec = 12,
}

-- OpenSSL's reasons for the verify results seen with --insecure. Other
-- backends use other codes.
local verify_errors = {
    [10] = "certificate has expired",
    [18] = "self-signed certificate",
    [19] = "self-signed certificate in chain",
    [20] = "unable to get local issuer certificate",
    [21] = "unable to verify the first certificate",
    [62] = "hostname mismatch",
}

---Seconds since the epoch of a certificate date, which is in UTC. TLS backends
---format it differently: OpenSSL as "Sep 26 22:49:11 2026 GMT", others as
---"2026-09-26 22:49:11 GMT".
---@param date string
---@return integer?
function M.parse_date(date)
    local year, month, day, hour, min, sec
    local month_name
    month_name, day, hour, min, sec, year =
        date:match("^(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+(%d+)")
    if month_name then
        month = months[month_name]
    else
        year, month, day, hour, min, sec =
            date:match("^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
    end

    if not (year and month) then
        return nil
    end

    local local_time = os.time({
        year = tonumber(year) --[[@as integer]],
        month = tonumber(month) --[[@as integer]],
        day = tonumber(day) --[[@as integer]],
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
    -- os.time reads the table as local time.
    local now = os.time()
    local utc_offset = now - os.time(os.date("!*t", now) --[[@as osdateparam]])

    return local_time + utc_offset
end

---@param name string distinguished name, such as "C = US, CN = example.com"
---@return string
local function common_name(name)
    return name:match("CN%s*=%s*([^,/]+)") or name
end

---The start and end of the chain in stderr.
---@param stderr string
---@return integer? start, integer? finish
local function find(stderr)
    local start = stderr:find(M.START, 1, true)
    if start == nil then
        return nil, nil
    end

    local _, finish = stderr:find(M.END, start, true)
    return start, finish
end

---The certificates in the chain, where each one starts with its subject.
---@param stderr string
---@return nurl.Certificate[]
local function parse_certs(stderr)
    local start, finish = find(stderr)
    if start == nil or finish == nil then
        return {}
    end

    local certs = {}
    local block = stderr:sub(start + #M.START, finish - #M.END)

    for line in vim.gsplit(block, "\r?\n") do
        local name, value = line:match("^([^:]+):(.*)$")
        local field = fields[name]

        if name == "Subject" then
            table.insert(certs, {})
        end

        if field and #certs > 0 then
            certs[#certs][field] = vim.trim(value)
        end
    end

    for _, cert in ipairs(certs) do
        cert.common_name = common_name(cert.subject)
        cert.expires_at = cert.expire_date and M.parse_date(cert.expire_date)
    end

    return certs
end

---The TLS details of a response, from the chain in stderr and the
---%{ssl_verify_result} and %{num_certs} metrics.
---@param stderr string
---@param verify_result? integer
---@param num_certs? integer
---@return nurl.ResponseTls? tls nil for connections without TLS
function M.parse(stderr, verify_result, num_certs)
    if not num_certs or num_certs == 0 then
        return nil
    end

    local verify_reason = nil
    if verify_result ~= 0 then
        verify_reason = verify_errors[verify_result]
            or ("error %s"):format(verify_result)
    end

    return {
        verify_result = verify_result,
        verify_reason = verify_reason,
        certs = parse_certs(stderr),
    }
end

---Stderr with the chain, which is long and already parsed into the response,
---replaced by a line saying it was there.
---@param stderr string
---@return string
function M.replace_chain(stderr)
    local start, finish = find(stderr)
    if start == nil or finish == nil then
        return stderr
    end

    local count = #parse_certs(stderr)
    local placeholder = ("[nurl removed the certificate chain (%d certificate%s) when saving to history]"):format(
        count,
        count == 1 and "" or "s"
    )

    return stderr:sub(1, start - 1) .. placeholder .. stderr:sub(finish + 1)
end

return M

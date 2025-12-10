local M = {}

local lpeg = vim.lpeg
local P, R, S, C, Ct, Cc, V =
    lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cc, lpeg.V

local function infer_type(str)
    if str == "true" then
        return true
    end

    if str == "false" then
        return false
    end

    if str == "nil" then
        return nil
    end

    local num = tonumber(str)
    if num then
        return num
    end

    return str
end

local ws = S(" \t") ^ 1

local grammar = P({
    "command",

    command = Ct(V("subcommand_part") * V("arg_part") * V("overrides_part")),

    subcommand_part = (C(
        P("env_file")
            + P("history")
            + P("jump")
            + P("yank")
            + P("env")
            + P("resend")
    ) * (ws + -1) + Cc(nil)),

    arg_part = (C((1 - S(" \t=")) ^ 1) * (ws + -1) + Cc(nil)),

    overrides_part = Ct(V("override") * (ws * V("override")) ^ 0) + Cc({}),
    override = Ct(Ct(V("path")) * P("=") * V("value")),
    path = (V("key") + V("bracket")) * (P(".") * V("key") + V("bracket")) ^ 0,
    bracket = P("[") * V("key") * P("]"),
    key = V("quoted_key") + V("number_key") + V("ident_key"),
    ident_key = C(R("az", "AZ", "__") * R("az", "AZ", "09", "__", "--") ^ 0),
    number_key = C(R("09") ^ 1) / tonumber,
    quoted_key = P('"') * C((1 - P('"')) ^ 0) * P('"')
        + P("'") * C((1 - P("'")) ^ 0) * P("'"),
    value = V("quoted_value") + V("raw_value"),
    quoted_value = P('"') * C((1 - P('"')) ^ 0) * P('"')
        + P("'") * C((1 - P("'")) ^ 0) * P("'"),
    raw_value = C((1 - S(" \t")) ^ 1) / infer_type,
})

---@class nurl.Command
---@field subcommand? string
---@field arg? string
---@field overrides nurl.Override[]

---@param str string
---@return nurl.Command?
function M.parse_command(str)
    local result = grammar:match(str)
    if not result then
        return nil
    end

    return {
        subcommand = result[1],
        arg = result[2],
        overrides = result[3],
    }
end

return M

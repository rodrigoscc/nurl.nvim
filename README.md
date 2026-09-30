<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-wordmark-dark.svg">
    <img src="assets/logo-wordmark.svg" alt="nurl.nvim" width="400">
  </picture>
</p>

# nurl.nvim

HTTP client for Neovim. Requests in pure Lua. Programmable, composable, extensible.

<!-- panvimdoc-ignore-start -->

https://github.com/user-attachments/assets/7a96353a-066c-4b14-aaa7-be6d37ffb558

<!-- panvimdoc-ignore-end -->

nurl keeps your requests in Lua files inside your project, next to the code
they call. A request is a Lua table, so any value can be computed when it is
sent, secrets can come from your password manager, and requests can share
helpers. The files live in your repository, so they are versioned and reviewed
like the rest of your code.

This request uses the active environment, asks for a name when it is sent, and
checks the response:

```lua
-- .nurl/users.lua
return {
    {
        title = "Create user",
        url = { Nurl.env.var("base_url"), "users" },
        method = "POST",
        auth = { type = "bearer", token = Nurl.env.var("token") },
        data = {
            name = Nurl.lazy(function()
                return vim.fn.input("Name: ")
            end),
            role = "admin",
        },
        test = function(ctx, response)
            ctx.are.equal(201, response.status_code)
            ctx.is_not_nil(vim.json.decode(response.body).id)
        end,
    },
}
```

Send it with `:Nurl .` with the cursor on it. To change a field for one send,
add an override:

```vim
:Nurl . data.role=viewer
```

<!-- panvimdoc-ignore-start -->

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Request Format](#request-format)
- [Environments](#environments)
- [Trust](#trust)
- [Tests](#tests)
- [Hooks and Callbacks](#hooks-and-callbacks)
- [Recipes](#recipes)
- [API](#api)
- [Type Reference](#type-reference)
- [Configuration](#configuration)
- [Winbar](#winbar)
- [Highlight Groups](#highlight-groups)

<!-- panvimdoc-ignore-end -->

## Features

- Requests in Lua: each request is a Lua table, so values can be functions,
  secrets can come from any command, and requests can share code.
- Environments: variables per environment (dev, staging, prod), switched with
  `:Nurl env`.
- Tests: assertions on the response, with the results in a tab of the response
  window.
- Hooks: code that runs before and after a request, for one request or for
  every request of an environment. Use them to refresh tokens, sign requests or
  confirm before sending to production.
- Overrides: change any field for one send, as in `:Nurl . data.id=42`.
- Response viewer: the body, request, headers, info (timings and TLS
  certificate), raw curl output and test results, in tabs.
- History: every request and response saved in SQLite, with an explorer to
  filter, open and resend them.
- curl export: copy any request to the clipboard as a curl command with
  `:Nurl yank`.
- JSON conversion: turn pasted JSON into a Lua table and back with
  `:Nurl json_to_lua` and `:Nurl lua_to_json`.
- Trust: nurl asks before running the Lua files of a project you just cloned.
- Scripting: send requests from Lua with `Nurl.send()`, then wait for or cancel
  them.
- Pickers: browse your requests with
  [snacks.nvim](https://github.com/folke/snacks.nvim),
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or
  [mini.pick](https://github.com/nvim-mini/mini.pick).

## Requirements

- Neovim >= 0.11.0. On 0.11, `:Nurl lua_to_json` writes the JSON on one line
  with unsorted keys; 0.12 indents and sorts it.
- `curl` >= 7.88.0 in PATH
- SQLite for the request history: nurl loads `libsqlite3.so`
  (`libsqlite3.dylib` on macOS, `sqlite3.dll` on Windows). On Debian and
  Ubuntu, it comes with `libsqlite3-dev`. Not needed with
  `history = { enabled = false }`.
- [snacks.nvim](https://github.com/folke/snacks.nvim),
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or
  [mini.pick](https://github.com/nvim-mini/mini.pick) for the pickers. nurl
  uses the first one installed, unless the `picker` option names one.
- Optional: `jq` to format JSON responses, `stylua` to format the environments
  file

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "rodrigoscc/nurl.nvim",
    version = "*",
    dependencies = { "folke/snacks.nvim" }, -- or telescope.nvim, mini.pick
    opts = {},
}
```

## Quick Start

### 1. Create a request file

Create `.nurl/requests.lua` in your project:

```lua
return {
    {
        "https://jsonplaceholder.typicode.com/posts/1",
    },
    {
        "https://jsonplaceholder.typicode.com/posts",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        data = {
            title = "Hello",
            body = "World",
            userId = 1,
        },
    },
}
```

### 2. Run a request

Position cursor on a request and run `:Nurl .`, or use the picker with `:Nurl`.

### 3. Read the response

The response opens in a window on the right, with tabs for the body, the
request, the headers, info (timings and TLS certificate) and the raw curl
output, plus the test results when the request has a test. Press `<Tab>` and
`<S-Tab>` to switch tabs, `<C-r>` to send the request again, `<C-x>` to cancel
it and `q` to close the window. In the body tab, `gi` shows the info tab beside
it.

### 4. Go further

Add [environments](#environments) for base URLs and tokens, and
[tests](#tests) to check responses. The [recipes](#recipes) show how to read
secrets from 1Password, refresh OAuth2 tokens and sign requests.

## Commands

| Command | Description |
|---------|-------------|
| `:Nurl` | Project picker -> send request |
| `:Nurl .` | Send request at cursor |
| `:Nurl %` | Current buffer picker -> send request |
| `:Nurl <filepath>` | File picker -> send request |
| `:Nurl jump` | Project picker -> jump to definition |
| `:Nurl jump %` | Current buffer picker -> jump |
| `:Nurl jump <filepath>` | File picker -> jump |
| `:Nurl history` | Browse and filter history in a full-width list |
| `:Nurl resend` | Recent requests picker -> resend |
| `:Nurl resend <-n>` | Resend nth last request (-1 = last) |
| `:Nurl env` | Environment picker -> activate |
| `:Nurl env <name>` | Activate environment directly |
| `:Nurl env_file` | Open environments file |
| `:Nurl yank` | Project picker -> yank curl command |
| `:Nurl yank .` | Yank curl at cursor |
| `:Nurl yank %` | Current buffer picker -> yank |
| `:Nurl yank <filepath>` | File picker -> yank |
| `:'<,'>Nurl json_to_lua` | Replace the selected JSON with a Lua table |
| `:'<,'>Nurl lua_to_json` | Replace the selected Lua table with JSON |
| `:Nurl trust [dir]` | Trust the Lua files in a directory (default: the project's `.nurl`) |
| `:Nurl untrust [dir]` | Ask again before running the Lua files in a directory |

When using `%` or `<filepath>`, if the file contains only one request, the action runs immediately without opening a picker.

### History explorer

`:Nurl history` opens a paged history list in a new tab. Navigate with normal
motions (`j`, `k`, `gg`, `G`); scrolling near the end loads more entries.
A lower pane previews the selected request, including its full body. The
preview loads only the selected request, not the saved response body. Opening
a response creates a response window beside the list. Close that window with
`q` to return to the explorer at the same position and filters.

| Key | Action |
|-----|--------|
| `<CR>` | Open the selected response |
| `/` | Filter by URL or title |
| `F` | Filter by method, status, time, request body, text response body, or whether the response body was saved to a file |
| `C` | Clear filters |
| `<C-r>` | Resend the selected request |
| `dd` | Delete the selected entry (`3dd` deletes three) and its saved response file |
| `q` | Close the explorer |
| `?` | Show keymaps |

Filters can be combined. Status accepts codes (`404`) and classes (`4xx`);
dates accept `YYYY-MM-DD` or an ISO date/time prefix. Body searches are
case-insensitive substring searches of saved request data/form fields or text
responses; file-backed response bodies are excluded. Filters other than dates
run in a background worker so the explorer remains responsive, and changing
filters discards older results. Configure the explorer through `history.explorer`
(`page_size` and buffer-local `keys`; set a mapping to `false` to disable it).
`page_size` is a minimum: larger windows load enough entries to fill the list,
including after a resize.

### History retention

History keeps at most `history.max_history_items` entries (1,000,000 by
default). When a saved request goes over the limit, the oldest entries are
deleted along with their saved response files, down to 10% below the limit
(at most 1,000 entries below). A single save deletes at most 1,000 entries, so
lowering the limit shrinks history gradually.

### Converting JSON

To use JSON from elsewhere as a request body, paste it, select it and run
`:'<,'>Nurl json_to_lua`:

```lua
data = {"title": "Hello", "tags": ["a"], "author": null},
```

becomes

```lua
data = {
    author = vim.NIL,
    tags = {
        "a",
    },
    title = "Hello",
},
```

Select just the JSON (character-wise, e.g. `v%` on the opening brace) or whole
lines; without a selection the whole buffer is converted. `null` becomes
`vim.NIL` and `{}` becomes `vim.empty_dict()`, so the request sends the same
JSON. `:'<,'>Nurl lua_to_json` converts a Lua table back to JSON. Keys are
sorted both ways, since Lua tables do not keep their order. Both are also
available as `Nurl.json_to_lua(text)` and `Nurl.lua_to_json(text)`.

### Overrides

Override request fields directly from the command-line for quick one-off changes.

```vim
:Nurl . data.id=42
:Nurl . data.name="John Doe" data.active=true
:Nurl % headers["X-Debug"]=true
:Nurl requests/login.lua data.user=admin
```

The syntax mirrors Lua table access:
- `data.user.name=value`
- `headers["Content-Type"]="application/json"`
- `headers["Accept"]={"application/json","text/plain"}`
- `url[2]=users`

Types are inferred: `42` (number), `true`/`false` (boolean), `"quoted"` (string with spaces).

Overrides are useful for quickly replacing IDs in REST URLs:

```lua
return {
    { url = { "https://api.example.com/users", "1" } },
}
```

```vim
:Nurl . url[2]=42
```

Or adding a curl flag on the fly:

```vim
:Nurl . curl_args[1]="--insecure"
```

## Request Format

A request file returns a list of request tables:

```lua
return {
    {
        -- URL (required): string, table of parts, or function
        "https://api.example.com/users?active=true", -- shorthand (supports query params)
        url = "https://api.example.com/users", -- explicit
        url = { "https://api.example.com", "v1" }, -- parts joined with /
        url = function()
            return "https://..."
        end, -- dynamic

        -- Query parameters (optional): table or function
        -- Names and values are URI-encoded automatically. Use functions for dynamic values.
        query = {
            page = 1,
            limit = 10,
            search = "hello world", -- becomes search=hello%20world
            token = Nurl.env.var("api_token"),
        },

        -- Method (optional, defaults to GET)
        method = "POST",

        -- Title (optional): display name in pickers
        title = "Create user",

        -- Headers (optional): table or function
        headers = {
            ["Authorization"] = "Bearer token",
            ["Content-Type"] = "application/json",
            ["Accept"] = { "application/json", "text/plain" },
        },

        -- Auth (optional): basic or bearer
        auth = {
            type = "basic",
            username = "user",
            password = "pass",
        },
        auth = { type = "bearer", token = "token" },

        -- Body (optional, use only one)
        data = { key = "value" }, -- table: JSON encoded
        data = '{"raw": "json"}', -- string: sent as-is
        form = { field = "value" }, -- multipart/form-data
        data_urlencode = { q = "search" }, -- URL encoded

        -- Additional curl flags (optional)
        curl_args = { "--insecure", "--compressed" },

        -- Save request to history (optional, defaults to true)
        save_history = false,

        -- Hooks (optional)
        pre_hook = function(next, input)
            next()
        end,
        post_hook = function(out) end,

        -- Test function (optional)
        test = function(ctx, response)
            ctx.are.equal(200, response.status_code)
        end,
    },
}
```

### URL Field Differences

The shorthand `[1]` field and `url` field handle query parameters differently:

- Shorthand `[1]`: supports inline query parameters (e.g.,
  `"https://api.example.com?foo=bar"`). They are sent as written, so write them
  encoded, as in a URL copied from elsewhere. Parameters in the `query` field
  are added after them.
- `url` as table: parts are joined with `/`, so query params should go in the
  `query` field instead.

### Dynamic Values

Use functions for values computed at request time:

```lua
return {
    {
        url = "https://api.example.com/users/",
        headers = function()
            return { ["X-Timestamp"] = tostring(os.time()) }
        end,
    },
}
```

### Lazy Values

Use `Nurl.lazy()` to defer evaluation until send time (skipped during picker preview):

```lua
return {
    {
        url = "https://api.example.com/login",
        method = "POST",
        data = {
            username = "user",
            password = Nurl.lazy(function()
                return vim.fn.inputsecret("Password: ")
            end),
        },
    },
}
```

## Environments

Create `.nurl/environments.lua`:

```lua
return {
    staging = {
        base_url = "https://staging.example.com",
        token = "staging-token",
    },
    production = {
        base_url = "https://prod.example.com",
        token = "prod-token",
    },
}
```

Access variables in requests:

```lua
return {
    {
        url = { Nurl.env.var("base_url"), "users" },
        headers = {
            ["Authorization"] = function()
                return "Bearer " .. Nurl.env.get("token")
            end,
        },
    },
}
```

| Function | Description |
|----------|-------------|
| `Nurl.env.var("name", env?)` | Returns a function that resolves the variable (for use in tables) |
| `Nurl.env.get("name", env?)` | Returns the value immediately (for use inside functions) |
| `Nurl.env.set("name", value, env?)` | Updates the variable |
| `Nurl.env.unset("name", env?)` | Removes the variable |

By default, all functions operate on the active environment. Pass an optional `env` argument to target a specific environment instead.

Switch the active environment with `:Nurl env`.

## Trust

Request files and environments are Lua code, which runs with the same access as
any plugin. So that opening a project you just cloned does not run its code,
nurl asks the first time it would run the Lua files in a directory:

- Trust runs them, now and in later sessions.
- Later skips them until the next session.
- Never skips them without asking again.

One answer covers every file in the directory, such as a project's `.nurl`.
Use `:Nurl trust` and `:Nurl untrust` to change it later. A trusted directory
stays trusted when its files change. Set `trust = false` to never ask.

## Tests

Define assertions to validate responses. Results are displayed in the Test buffer tab.

```lua
return {
    {
        url = "https://api.example.com/users/1",
        test = function(ctx, response)
            ctx.are.equal(200, response.status_code)

            local body = vim.json.decode(response.body)

            ctx.test("user data", function()
                ctx.is_not_nil(body.id)
                ctx.are.equal("John", body.name, "name should be John")
                ctx.are.same({ city = "New York" }, body.address)
            end)
        end,
    },
}
```

### Available Assertions

| Assertion | Description |
|-----------|-------------|
| `ctx.are.equal(expected, actual, msg?)` | Strict equality (`==`) |
| `ctx.are.same(expected, actual, msg?)` | Deep equality for tables |
| `ctx.are_not.equal(expected, actual, msg?)` | Not equal |
| `ctx.are_not.same(expected, actual, msg?)` | Not deeply equal |
| `ctx.is_true(value, msg?)` | Value is `true` |
| `ctx.is_false(value, msg?)` | Value is `false` |
| `ctx.truthy(value, msg?)` | Value is truthy (not `nil` and not `false`) |
| `ctx.falsy(value, msg?)` | Value is falsy (`nil` or `false`) |
| `ctx.is_nil(value, msg?)` | Value is `nil` |
| `ctx.is_not_nil(value, msg?)` | Value is not `nil` |

All assertions accept an optional message as the last argument.

### Test Output

The test buffer displays results in busted-style format:

```text
3 successes / 1 failure / 0 errors

Failure
user data address
city should match
Passed in: "Los Angeles"
Expected: "New York"
```

- Successes: passing assertions (not shown individually)
- Failures: assertion mismatches with expected vs actual values
- Errors: exceptions thrown during test execution

The test tab indicator in the winbar turns red when any test fails.

## Hooks and Callbacks

Hooks let you run code before/after requests. They can be defined per-request or per-environment.

### Execution Order

```text
                    +-----------------------+
                    |   User calls :Nurl    |
                    +-----------------------+
                              |
                              v
                    +-----------------------+
                    |  Request is expanded  |
                    | (functions evaluated) |
                    +-----------------------+
                              |
                              v
                    +-----------------------+
                    |  Environment pre_hook |
                    +-----------------------+
                              |
                              | calls next()
                              v
                    +-----------------------+
                    |   Request pre_hook    |
                    +-----------------------+
                              |
                              | calls next()
                              v
                    +-----------------------+
                    |   curl executes       |
                    +-----------------------+
                              |
                              v
                    +-----------------------+
                    |   Request post_hook   |
                    +-----------------------+
                              |
                              v
                    +-----------------------+
                    | Environment post_hook |
                    +-----------------------+
                              |
                              v
                    +-----------------------+
                    |   Callback executes   |
                    +-----------------------+
```

### pre_hook

Called before sending. Call `next()` to send the request, or `cancel()` to
decline it. A cancelled request runs the callback, but not the post hooks.

```lua
---@param next fun() Call to continue the request
---@param input nurl.RequestInput
---@param cancel fun() Call to decline the request
pre_hook = function(next, input, cancel)
    -- input.request contains the expanded request
    -- Modify input.request fields if needed
    input.request.headers["X-Custom"] = "value"
    next()
end
```

### post_hook

Called after curl completes.

```lua
---@param out nurl.RequestOut
post_hook = function(out)
    -- out.request: the request that was sent
    -- out.response: the parsed response (nil if curl failed)
    -- out.curl: curl execution details
    -- out.win: the response window id
    if out.response then
        print("Status: " .. out.response.status_code)
    end
end
```

### Environment Hooks

Apply to all requests when an environment is active:

```lua
-- .nurl/environments.lua
return {
    production = {
        base_url = "https://prod.example.com",
        pre_hook = function(next, input, cancel)
            vim.ui.select({ "Yes", "No" }, {
                prompt = "Send to production?",
            }, function(choice)
                if choice == "Yes" then
                    next()
                else
                    cancel()
                end
            end)
        end,
        post_hook = function(out)
            print("Prod request completed")
        end,
    },
}
```

### Callback

Used with `Nurl.send()` for programmatic requests. The callback can be passed as the second or third argument:

```lua
-- Callback as second argument
Nurl.send(request, function(out)
    if out.response then
        local body = vim.json.decode(out.response.body)
        Nurl.env.set("token", body.access_token)
    end
end)

-- Callback as third argument (with opts)
Nurl.send(request, { display = true }, function(out)
    print("Status: " .. out.response.status_code)
end)
```

The response window is only opened if `display` is set in opts.

### display Option

Control the response window display. Can be `true` (show with defaults), `false` (don't show), or an options table:

```lua
-- Show response window with defaults
Nurl.send(request, { display = true })

-- Show response window with options
Nurl.send(request, {
    display = {
        win = existing_win_id, -- Reuse existing window
        focus_buffer = "test", -- Open specific tab (body, request, headers, info, raw, test)
    },
})
```

Useful for updating a response in place, like when resending a request.

## Recipes

### 1Password CLI for Secrets

```lua
local function op_get(item_id, field)
    return Nurl.lazy(function()
        local result = vim.system({
            "op",
            "item",
            "get",
            item_id,
            "--fields",
            field,
            "--format",
            "json",
        }, { text = true }):wait()

        if result.code ~= 0 then
            error("Failed getting op item")
        end

        local data = vim.json.decode(result.stdout)
        return data.value
    end)
end

return {
    {
        url = "https://api.example.com/login",
        method = "POST",
        data = {
            username = op_get("item-id", "username"),
            password = op_get("item-id", "password"),
        },
    },
}
```

### OAuth2 Token Refresh

```lua
-- .nurl/environments.lua
local env = require("nurl.environments")

return {
    default = {
        access_token = nil,
        refresh_token = "initial-refresh-token",
        expires_at = nil,
        pre_hook = function(next, input)
            local expires = env.get("expires_at")
            if expires and tonumber(expires) > os.time() then
                next()
                return
            end

            Nurl.send({
                url = "https://auth.example.com/token",
                method = "POST",
                data = {
                    grant_type = "refresh_token",
                    refresh_token = env.get("refresh_token"),
                },
            }, function(out)
                if out.response and out.response.status_code == 200 then
                    local body = vim.json.decode(out.response.body)
                    env.set("access_token", body.access_token)
                    env.set("expires_at", os.time() + body.expires_in)

                    -- This request has already been expanded before the pre_hook,
                    -- so we need to update the header here so that it reflects the
                    -- above changes.
                    input.request.headers["Authorization"] = "Bearer "
                        .. body.access_token
                    next()
                end
            end)
        end,
    },
}
```

### HMAC Signature

```lua
local function hmac_sha256(key, message)
    local result = vim.fn.system({
        "openssl",
        "dgst",
        "-sha256",
        "-hmac",
        key,
    }, message)
    return result:match("=%s*(%x+)") or ""
end

local body = '{"action":"test"}'

return {
    {
        url = "https://api.example.com/secure",
        method = "POST",
        headers = function()
            local timestamp = tostring(os.time())
            return {
                ["X-Timestamp"] = timestamp,
                ["X-Signature"] = hmac_sha256("secret", timestamp .. body),
            }
        end,
        data = body,
    },
}
```

### File Upload with Picker

```lua
return {
    {
        url = "https://api.example.com/upload",
        method = "POST",
        pre_hook = function(next, input)
            vim.ui.input({
                prompt = "File: ",
                completion = "file",
            }, function(path)
                if path then
                    input.request.form = { file = "@" .. vim.fn.expand(path) }
                    next()
                end
            end)
        end,
    },
}
```

### GraphQL Helper

```lua
local function graphql(query, variables)
    return {
        url = { Nurl.env.var("base_url"), "graphql" },
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        data = { query = query, variables = variables },
    }
end

return {
    graphql(
        [[
        query GetUser($id: ID!) {
            user(id: $id) { id name }
        }
    ]],
        { id = "123" }
    ),
}
```

### Send request to URL at cursor

Follow URLs directly from response bodies, especially useful for paginated APIs where the response includes `next` links. Map `gx` to send a request to the URL under the cursor:

```lua
local function super_gx()
    local cursor_url = vim.fn.expand("<cfile>")
    local request = Nurl.get_request()
    if not request then
        -- Default gx implementation if cursor isn't in a Nurl response buffer.
        vim.ui.open(cursor_url)
        return
    end

    -- Will send the same headers, since they may include authentication.
    local orig_headers = request.headers

    if vim.v.count == 0 then
        -- Display response in the current window
        Nurl.send(
            { cursor_url, headers = orig_headers },
            { display = { win = vim.api.nvim_get_current_win() } }
        )
    else
        -- Create new window if a count is given before pressing `gx`.
        Nurl.send({ cursor_url, headers = orig_headers }, { display = true })
    end
end

-- Make <cfile> include query params
vim.opt.isfname:append("?")
vim.opt.isfname:append("&")

vim.keymap.set("n", "gx", super_gx, { desc = "Super gx" })
```

## API

```lua
local Nurl = require("nurl")

-- Send a request programmatically (returns a handle)
local handle = Nurl.send(request, opts?, callback?)
local handle = Nurl.send(request, callback?) -- opts can be omitted

-- Wait for request to complete (blocks)
local out = handle:wait()
local out = handle:wait(5000) -- with timeout in ms

-- Cancel a running request
handle:cancel()

-- Resend from history
Nurl.resend_last_request() -- resend last
Nurl.resend_last_request(-2) -- resend second to last

-- Request shown in a response buffer (nil elsewhere)
Nurl.get_request() -- current buffer
Nurl.get_request(bufnr)

-- Environment
Nurl.get_active_env() -- returns active env name or nil
Nurl.activate_env("production")
Nurl.env.get("variable") -- get variable value
Nurl.env.set("variable", val) -- set variable value
Nurl.env.var("variable") -- get resolver function

-- Convert between JSON text and Lua table source
Nurl.json_to_lua('{"id": 1}') -- "{\n    id = 1,\n}"
Nurl.lua_to_json("{ id = 1 }") -- '{\n    "id": 1\n}'
Nurl.json_to_lua(json, { indent = "  " }) -- custom indentation

-- Winbar components
Nurl.winbar.status_code()
Nurl.winbar.time()
Nurl.winbar.tabs()
Nurl.winbar.request_title()
```

## Type Reference

### nurl.Request

The expanded request object (all functions resolved):

```lua
---@class nurl.Request
---@field method string              HTTP method (GET, POST, etc.)
---@field url string                 Full URL
---@field query? table<string,any>   Query parameters (URI-encoded)
---@field title? string              Display name
---@field headers table<string,string|string[]>  Headers
---@field auth? nurl.Auth            Auth configuration
---@field data? string|table         Request body
---@field form? table<string,string> Form data
---@field data_urlencode? table      URL-encoded data
---@field curl_args? string[]        Extra curl flags
---@field save_history? boolean      Save request to history
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput, cancel: fun())
---@field post_hook? fun(out: nurl.RequestOut)
---@field test? fun(ctx: nurl.TestContext, response: nurl.Response)
```

### nurl.RequestInput

Passed to `pre_hook`:

```lua
---@class nurl.RequestInput
---@field request nurl.Request   The request about to be sent
```

### nurl.RequestOut

Passed to `post_hook` and `callback`:

```lua
---@class nurl.RequestOut
---@field status string "completed", "failed" or "cancelled" ("pending" or "started" from a wait that timed out)
---@field request nurl.Request The request that was sent
---@field response? nurl.Response Parsed response (nil if curl failed or a pre hook cancelled it)
---@field curl? nurl.Curl Curl execution details (nil if a pre hook cancelled it)
---@field win? integer Response window id
```

### nurl.Auth

```lua
---@alias nurl.Auth nurl.BasicAuth | nurl.BearerAuth

---@class nurl.BasicAuth
---@field type "basic"
---@field username string
---@field password string

---@class nurl.BearerAuth
---@field type "bearer"
---@field token string
```

### nurl.Response

Parsed HTTP response:

```lua
---@class nurl.Response
---@field status_code integer HTTP status code
---@field reason_phrase string Status text (e.g., "OK")
---@field protocol string Protocol (e.g., "HTTP/2")
---@field headers table<string,string|string[]> Response headers
---@field body string Response body
---@field body_file? string Path if body saved to file
---@field time nurl.ResponseTime Timing breakdown
---@field size nurl.ResponseSize Size breakdown
---@field speed nurl.ResponseSpeed Speed metrics
---@field tls? nurl.ResponseTls TLS certificates (nil without TLS)
```

### nurl.ResponseTls

The certificate chain, shown in the info tab. Curl fills it with the OpenSSL, GnuTLS, Schannel and Secure Transport backends.

```lua
---@class nurl.ResponseTls
---@field verify_result integer 0 when verified, otherwise the TLS backend's error code (seen with --insecure)
---@field verify_reason? string Why it was not verified, nil when it was
---@field certs nurl.Certificate[] The chain, starting with the server's certificate

---@class nurl.Certificate
---@field subject? string
---@field common_name? string The subject's CN, or the whole subject without one
---@field issuer? string
---@field san? string Subject alternative names
---@field start_date? string As the TLS backend formats it
---@field expire_date? string As the TLS backend formats it
---@field expires_at? integer Seconds since the epoch, nil if expire_date is in an unknown format
```

### nurl.ResponseTime

```lua
---@class nurl.ResponseTime
---@field time_total number Total time in seconds
---@field time_namelookup number DNS lookup time
---@field time_connect number TCP connect time
---@field time_appconnect number TLS handshake time
---@field time_pretransfer number Pre-transfer time
---@field time_starttransfer number Time to first byte
---@field time_redirect number Redirect time
```

### nurl.Curl

Curl execution details:

```lua
---@class nurl.Curl
---@field args string[] Curl arguments
---@field result? vim.SystemCompleted Execution result
---@field exec_datetime string Execution timestamp
---@field pid? integer Process ID
```

### nurl.RequestHandle

Returned by `Nurl.send()` to control a running request:

```lua
---@class nurl.RequestHandle
---@field id integer                Unique handle identifier
---@field request nurl.Request      The request being sent
---@field response? nurl.Response   Response (available after completion)
---@field curl? nurl.Curl           Curl details (available after completion)
---@field status string             "pending"|"started"|"completed"|"cancelled"|"failed"
```

Methods:

| Method | Description |
|--------|-------------|
| `handle:wait(time?, interval?)` | Block until complete. Returns `nurl.RequestOut`. Optional timeout in ms. |
| `handle:cancel(signame?)` | Cancel the request. Optional signal name (default: `"sigterm"`). |
| `handle:is_done()` | Returns `true` if completed, cancelled, or failed. |
| `handle:is_cancelled()` | Returns `true` if cancelled. |
| `handle:is_failed()` | Returns `true` if failed. |

## Configuration

```lua
require("nurl").setup({
    -- Project directory for request files
    dir = ".nurl",

    -- Environments file name (in dir)
    environments_file = "environments.lua",

    -- Active environments per working directory file name (in dir)
    active_environments_file = vim.fn.stdpath("data") .. "/nurl/envs.json",

    -- Ask before running the Lua files of a directory (see Trust)
    trust = true,
    trust_file = vim.fn.stdpath("data") .. "/nurl/trust.json",

    -- Picker: "snacks", "telescope" or "mini". Without one, the first
    -- installed picker is used, in this order.
    picker = nil,

    -- History settings
    history = {
        enabled = true,
        db_file = vim.fn.stdpath("data") .. "/nurl/history.sqlite3",
        -- Older entries and their saved response files are deleted
        max_history_items = 1000000,
    },

    -- Directory for non-displayable response bodies (images, etc.)
    responses_files_dir = vim.fn.stdpath("data") .. "/nurl/responses",

    -- Response window config (see :help nvim_open_win)
    win_config = { split = "right" },

    -- Response formatters by filetype
    formatters = {
        json = {
            cmd = { "jq", "--sort-keys", "--indent", "2" },
            available = function()
                return vim.fn.executable("jq") == 1
            end,
        },
        lua = {
            cmd = { "stylua", "-" },
            available = function()
                return vim.fn.executable("stylua") == 1
            end,
        },
    },

    -- Buffer keymaps
    buffers = {
        {
            "body",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                gi = { "toggle_secondary", opts = { buffer = "info" } },
                q = "close",
            },
        },
        {
            "request",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                q = "close",
            },
        },
        {
            "headers",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                q = "close",
            },
        },
        {
            "info",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                q = "close",
            },
        },
        {
            "raw",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                q = "close",
            },
        },
        {
            "test",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                ["<C-x>"] = "cancel",
                q = "close",
            },
        },
    },

    highlight = {
        groups = {
            spinner = "NurlSpinner",
            elapsed_time = "NurlElapsedTime",
            winbar_title = "NurlWinbarTitle",
            winbar_tab_active = "NurlWinbarTabActive",
            winbar_tab_inactive = "NurlWinbarTabInactive",
            winbar_loading = "NurlWinbarLoading",
            winbar_time = "NurlWinbarTime",
            winbar_warning = "NurlWinbarWarning",
            winbar_error = "NurlWinbarError",
            status = "NurlStatus",
            status_success = "NurlStatusSuccess",
            status_redirect = "NurlStatusRedirect",
            status_client_error = "NurlStatusClientError",
            status_server_error = "NurlStatusServerError",
        },
    },
})
```

## Winbar

The response window includes a winbar. Use it in your own winbar:

```lua
vim.o.winbar = "%{%v:lua.Nurl.winbar.status_code()%}"
    .. "%<%{%v:lua.Nurl.winbar.request_title()%}"
    .. "%{%v:lua.Nurl.winbar.time()%}"
    .. " %=%{%v:lua.Nurl.winbar.tabs()%}"
```

## Highlight Groups

| Group | Description |
|-------|-------------|
| `NurlStatus` | 1xx status codes, everywhere status codes are shown |
| `NurlStatusSuccess` | 2xx status codes |
| `NurlStatusRedirect` | 3xx status codes |
| `NurlStatusClientError` | 4xx status codes |
| `NurlStatusServerError` | 5xx status codes |
| `NurlSpinner` | Loading spinner |
| `NurlElapsedTime` | Elapsed time display |
| `NurlWinbarTitle` | Request title in winbar |
| `NurlWinbarTabActive` | Active tab |
| `NurlWinbarTabInactive` | Inactive tab |
| `NurlWinbarLoading` | Loading state |
| `NurlWinbarTime` | Response time |
| `NurlWinbarWarning` | Warning messages |
| `NurlWinbarError` | Error messages |
| `NurlInfoIcon` | Section icons in info buffer |
| `NurlInfoLabel` | Field labels in info buffer |
| `NurlInfoValue` | Field values in info buffer |
| `NurlInfoHighlight` | Highlighted values (e.g., total time) |
| `NurlInfoUrl` | URL values |
| `NurlInfoQueryKey` | Query parameter keys |
| `NurlInfoQueryValue` | Query parameter values |
| `NurlInfoSeparator` | Separators (?, &, =) |
| `NurlInfoMethod` | HTTP method |
| `NurlInfoOk` | Verified certificate |
| `NurlInfoWarning` | Certificate expiring within 30 days |
| `NurlInfoError` | Unverified or expired certificate |
| `NurlHistoryTime` | History timestamp |
| `NurlHistoryMethod` | History request method |
| `NurlHistoryDuration` | History request duration |
| `NurlHistoryTitle` | History request title |
| `NurlHistoryUrl` | History request URL |
| `NurlHistoryMatch` | URL/title filter matches in history |
| `NurlTestPass` | Passing test count |
| `NurlTestFail` | Failing test count, "Failure" header, and the Test tab when tests fail |
| `NurlTestError` | Error count and "Error" header |
| `NurlTestLabel` | "Passed in:" and "Expected:" labels |
| `NurlTestValueActual` | Actual values (diff delete style) |
| `NurlTestValueExpected` | Expected values (diff add style) |
| `NurlTestSuiteName` | Test suite breadcrumb |

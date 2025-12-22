# nurl.nvim

HTTP client for Neovim. Requests in pure Lua. Programmable, composable, extensible.

<https://github.com/user-attachments/assets/cfbcde44-0608-4f79-9327-15b4bf072a70>

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Request Format](#request-format)
- [Environments](#environments)
- [Hooks and Callbacks](#hooks-and-callbacks)
- [Type Reference](#type-reference)
- [API](#api)
- [Configuration](#configuration)
- [Winbar](#winbar)
- [Highlight Groups](#highlight-groups)
- [Recipes](#recipes)

## Features

- **Lua-based requests** - Define HTTP requests as Lua tables with full language support
- **Environments** - Manage variables per environment (dev, staging, prod)
- **Request history** - SQLite-backed history with full request/response data
- **Response viewer** - Split window with body, headers, info, and raw curl output tabs
- **Hooks** - Pre/post hooks per request, or per environment (applies to all requests when env is active)
- **Picker integration** - Browse requests and history with [snacks.nvim](https://github.com/folke/snacks.nvim) or [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

## Requirements

- Neovim >= 0.10.0
- `curl` in PATH
- [snacks.nvim](https://github.com/folke/snacks.nvim) or [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for pickers)
- Optional: `jq` for JSON formatting, `stylua` for environments file formatting

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "rodrigoscc/nurl.nvim",
    version = "*",
    dependencies = { "folke/snacks.nvim" }, -- or telescope.nvim
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
| `:Nurl history` | History picker -> view response |
| `:Nurl resend` | Recent requests picker -> resend |
| `:Nurl resend <-n>` | Resend nth last request (-1 = last) |
| `:Nurl env` | Environment picker -> activate |
| `:Nurl env <name>` | Activate environment directly |
| `:Nurl env_file` | Open environments file |
| `:Nurl yank` | Project picker -> yank curl command |
| `:Nurl yank .` | Yank curl at cursor |
| `:Nurl yank %` | Current buffer picker -> yank |
| `:Nurl yank <filepath>` | File picker -> yank |

When using `%` or `<filepath>`, if the file contains only one request, the action runs immediately without opening a picker.

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
        -- Values are URI-encoded automatically. Use functions for dynamic values.
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
        },

        -- Body (optional, use only one)
        data = { key = "value" }, -- table: JSON encoded
        data = '{"raw": "json"}', -- string: sent as-is
        form = { field = "value" }, -- multipart/form-data
        data_urlencode = { q = "search" }, -- URL encoded

        -- Additional curl flags (optional)
        curl_args = { "--insecure", "--compressed" },

        -- Hooks (optional)
        pre_hook = function(next, input)
            next()
        end,
        post_hook = function(out) end,
    },
}
```

### URL Field Differences

The shorthand `[1]` field and `url` field handle query parameters differently:

- **Shorthand `[1]`**: Supports inline query parameters (e.g., `"https://api.example.com?foo=bar"`). Query params are extracted and merged with the `query` field.
- **`url` as table**: Parts are joined with `/`, so query params should go in the `query` field instead.

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
                    | Response is displayed |
                    | or on_complete func   |
                    +-----------------------+
```

### pre_hook

Called before sending. Must call `next()` to proceed.

```lua
---@param next fun() Call to continue the request
---@param input nurl.RequestInput
pre_hook = function(next, input)
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
        pre_hook = function(next, input)
            vim.ui.select({ "Yes", "No" }, {
                prompt = "Send to production?",
            }, function(choice)
                if choice == "Yes" then
                    next()
                end
            end)
        end,
        post_hook = function(out)
            print("Prod request completed")
        end,
    },
}
```

### on_complete Callback

Used with `Nurl.send()` for programmatic requests:

```lua
Nurl.send(request, {
    ---@param out nurl.RequestOut
    on_complete = function(out)
        if out.response then
            local body = vim.json.decode(out.response.body)
            Nurl.env.set("token", body.access_token)
        end
    end,
})
```

The response window won't be opened if `on_complete` is defined.

### win Option

Reuse an existing response window instead of opening a new one:

```lua
Nurl.send(request, {
    win = existing_win_id,
})
```

Useful for updating a response in place, like when resending a request.

## Type Reference

### nurl.Request

The expanded request object (all functions resolved):

```lua
---@class nurl.Request
---@field method string              HTTP method (GET, POST, etc.)
---@field url string                 Full URL
---@field query? table<string,any>   Query parameters (URI-encoded)
---@field title? string              Display name
---@field headers table<string,string>  Headers
---@field data? string|table         Request body
---@field form? table<string,string> Form data
---@field data_urlencode? table      URL-encoded data
---@field curl_args? string[]        Extra curl flags
---@field pre_hook? fun(next: fun(), input: nurl.RequestInput)
---@field post_hook? fun(out: nurl.RequestOut)
```

### nurl.RequestInput

Passed to `pre_hook`:

```lua
---@class nurl.RequestInput
---@field request nurl.Request   The request about to be sent
```

### nurl.RequestOut

Passed to `post_hook` and `on_complete`:

```lua
---@class nurl.RequestOut
---@field request nurl.Request The request that was sent
---@field response? nurl.Response Parsed response (nil if curl failed)
---@field curl nurl.Curl Curl execution details
---@field win? integer Response window id
```

### nurl.Response

Parsed HTTP response:

```lua
---@class nurl.Response
---@field status_code integer HTTP status code
---@field reason_phrase string Status text (e.g., "OK")
---@field protocol string Protocol (e.g., "HTTP/2")
---@field headers table<string,string> Response headers
---@field body string Response body
---@field body_file? string Path if body saved to file
---@field time nurl.ResponseTime Timing breakdown
---@field size nurl.ResponseSize Size breakdown
---@field speed nurl.ResponseSpeed Speed metrics
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

## API

```lua
local Nurl = require("nurl")

-- Send a request programmatically
Nurl.send(request, {
    on_complete = function(out) end, -- optional callback
})

-- Resend from history
Nurl.resend_last_request() -- resend last
Nurl.resend_last_request(-2) -- resend second to last

-- Environment
Nurl.get_active_env() -- returns active env name or nil
Nurl.activate_env("production")
Nurl.env.get("variable") -- get variable value
Nurl.env.set("variable", val) -- set variable value
Nurl.env.var("variable") -- get resolver function

-- Winbar components
Nurl.winbar.status_code()
Nurl.winbar.time()
Nurl.winbar.tabs()
Nurl.winbar.request_title()
```

## Configuration

```lua
require("nurl").setup({
    -- Project directory for request files
    dir = ".nurl",

    -- Environments file name (in dir)
    environments_file = "environments.lua",

    -- Active environments per working directory file name (in dir)
    active_environments_file = vim.fn.stdpath("data") .. "/nurl/envs.json",

    -- History settings
    history = {
        enabled = true,
        db_file = vim.fn.stdpath("data") .. "/nurl/history.sqlite3",
        max_history_items = 5000,
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
                ["<C-m>"] = { "toggle_secondary", opts = { buffer = "info" } },
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
    },

    highlight = {
        groups = {
            spinner = "NurlSpinner",
            elapsed_time = "NurlElapsedTime",
            winbar_title = "NurlWinbarTitle",
            winbar_tab_active = "NurlWinbarTabActive",
            winbar_tab_inactive = "NurlWinbarTabInactive",
            winbar_success_status_code = "NurlWinbarSuccessStatusCode",
            winbar_error_status_code = "NurlWinbarErrorStatusCode",
            winbar_loading = "NurlWinbarLoading",
            winbar_time = "NurlWinbarTime",
            winbar_warning = "NurlWinbarWarning",
            winbar_error = "NurlWinbarError",
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
| `NurlSpinner` | Loading spinner |
| `NurlElapsedTime` | Elapsed time display |
| `NurlWinbarTitle` | Request title in winbar |
| `NurlWinbarTabActive` | Active tab |
| `NurlWinbarTabInactive` | Inactive tab |
| `NurlWinbarSuccessStatusCode` | 2xx status codes |
| `NurlWinbarErrorStatusCode` | 4xx/5xx status codes |
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
| `NurlInfoStatus` | Status code (fallback) |
| `NurlInfoStatusSuccess` | 2xx status codes |
| `NurlInfoStatusRedirect` | 3xx status codes |
| `NurlInfoStatusClientError` | 4xx status codes |
| `NurlInfoStatusServerError` | 5xx status codes |

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
            }, {
                on_complete = function(out)
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
                end,
            })
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
    if not vim.b.nurl_data then
        -- Default gx implementation if cursor isn't in a Nurl response buffer.
        vim.ui.open(cursor_url)
        return
    end

    local nurl_data = vim.b.nurl_data

    -- Will send the same headers, since they may include authentication.
    local orig_headers = nurl_data.request.headers

    if vim.v.count == 0 then
        -- Display response in the current window
        Nurl.send(
            { cursor_url, headers = orig_headers },
            { win = vim.api.nvim_get_current_win() }
        )
    else
        -- Create new window if a count is given before pressing `gx`.
        Nurl.send({ cursor_url, headers = orig_headers })
    end
end

vim.keymap.set("n", "gx", super_gx, { desc = "Super gx" })
```

# nurl.nvim

A Lua-based HTTP client for Neovim. Define requests in Lua files, manage environments, add hooks, and view responses in beautiful split windows.

<table>
  <tr>
    <th>Body tab</th>
    <th>Headers tab</th>
  </tr>
  <tr>
    <td>
      <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 09 35" src="https://github.com/user-attachments/assets/a2404ab0-ff9a-4bdf-8e0f-29b3e9818a79" />
    </td>
    <td>
      <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 09 41" src="https://github.com/user-attachments/assets/fbe8f2f4-24a0-4aec-af9f-eae946b18c89" />
    </td>
  </tr>
  <tr>
    <th>Info tab</th>
    <th>Raw tab</th>
  </tr>
  <tr>
    <td>
      <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 09 50" src="https://github.com/user-attachments/assets/fa17652b-6556-4f86-a27a-7f1d57537cad" />
    </td>
    <td>
    <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 09 54" src="https://github.com/user-attachments/assets/2d9f0aa8-9b3d-4d1e-aadd-2a1f2c3551af" />
    </td>
  </tr>
  <tr>
    <th>Request picker</th>
    <th>History picker</th>
  </tr>
  <tr>
    <td>
      <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 10 12" src="https://github.com/user-attachments/assets/61bf5e49-7a0a-43fd-b5c8-4b421d5ba114" />
    </td>
    <td>
    <img width="1473" height="962" alt="Screenshot 2025-11-27 at 12 10 18" src="https://github.com/user-attachments/assets/c436684e-8ed4-468b-8f89-51dce7742028" />
    </td>
  </tr>
</table>

## Table of Contents

- [✨ Features](#features)
- [📋 Requirements](#requirements)
- [📦 Installation](#installation)
- [🚀 Quick Start](#quick-start)
- [⚙️ Configuration](#configuration)
- [💻 Commands](#commands)
- [📝 Request Format](#request-format)
  - [Dynamic Values](#dynamic-values)
  - [Lazy Values](#lazy-values)
  - [URL Parts](#url-parts)
- [🌍 Environments](#environments)
  - [Environment Hooks](#environment-hooks)
- [🔌 API](#api)
- [📊 Winbar](#winbar)
- [🎨 Highlight Groups](#highlight-groups)
- [📖 Recipes](#recipes)
  - [1Password CLI for secrets](#1password-cli-for-secrets)
  - [OAuth2 Token Refresh](#oauth2-token-refresh)
  - [Using Response Values](#using-response-values)
  - [HMAC Signature](#hmac-signature)
  - [Environment-Based Confirmation](#environment-based-confirmation)
  - [Response Validation](#response-validation)
  - [GraphQL with Variables](#graphql-with-variables)
  - [File Upload with Picker](#file-upload-with-picker)

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
    dependencies = { "folke/snacks.nvim" }, -- Optional
    dependencies = { -- Optional
        'nvim-telescope/telescope.nvim', tag = 'v0.1.9',
        dependencies = { 'nvim-lua/plenary.nvim' }
    },
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

Position cursor on a request and run:

```vim
:Nurl send_at_cursor
```

Or use the picker:

```vim
:Nurl send
```

## Configuration

```lua
require("nurl").setup({
    -- Project directory for Nurl files
    dir = ".nurl",

    -- Environments file name
    environments_file = "environments.lua",

    -- History settings
    history = {
        enabled = true,
        db_file = vim.fn.stdpath("data") .. "/nurl/history.sqlite3",
        max_history_items = 5000,
    },

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
    },

    -- Buffer keymaps
    buffers = {
        {
            "body",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "headers",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "info",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
        {
            "raw",
            keys = {
                ["<Tab>"] = "next_buffer",
                ["<S-Tab>"] = "previous_buffer",
                ["<C-r>"] = "rerun",
                q = "close",
            },
        },
    },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Nurl send_at_cursor` | Send request under cursor |
| `:Nurl send` | Pick and send a project request |
| `:Nurl send_from_buffer` | Pick and send a request from current buffer |
| `:Nurl jump` | Pick and jump to a request definition |
| `:Nurl history` | Browse request history |
| `:Nurl env` | Switch active environment |
| `:Nurl env_file` | Open environments file |
| `:Nurl yank_at_cursor` | Copy curl command to clipboard |
| `:Nurl resend [n]` | Resend last request (optional index) |
| `:Nurl` | Show command picker |

## Request Format

```lua
---@class nurl.SuperRequest
{
    -- Shorthand: URL as first element
    "https://api.example.com/users",

    -- Required: string, table of parts, or function
    url = "https://api.example.com/users",
    url = { "https://api.example.com", "v1", "users" },
    url = function() return "https://api.example.com/users/id" end,

    -- Optional: display name in pickers
    title = "Get all users",
    title = function() return "Dynamic title" end,

    -- Optional (defaults to GET)
    method = "POST",

    -- Optional headers: table or function
    headers = {
        ["Authorization"] = "Bearer token",
        ["Content-Type"] = "application/json",
    },
    headers = function() return { ["X-Request-Id"] = tostring(os.time()) } end,

    -- Body (use only one): table, string, or function
    data = { key = "value" },           -- Table: JSON encoded
    data = '{"raw": "json"}',           -- String: sent as-is
    data = function() return { ts = os.time() } end,
    form = { field = "value" },         -- multipart/form-data
    data_urlencode = { q = "search" },  -- URL encoded

    -- Hooks
    pre_hook = function(next, request)
        -- Called before request, must call next() to proceed
        next()
    end,
    post_hook = function(request, response)
        -- Called after response received
    end,
}
```

### Dynamic Values

Use functions for dynamic values:

```lua
return {
    {
        url = function()
            return "https://api.example.com/users/" .. vim.fn.input("User ID: ")
        end,
        headers = function()
            return {
                ["X-Request-Id"] = tostring(os.time()),
            }
        end,
    },
}
```

### Lazy Values

Use `Nurl.lazy()` for values that should only be resolved right before sending (not during picker preview):

```lua
return {
    url = "https://api.example.com/login",
    method = "POST",
    data = {
        username = "user",
        password = Nurl.lazy(function()
            return vim.fn.inputsecret("Password: ")
        end),
    },
}
```

### URL Parts

Build URLs from parts:

```lua
return {
    {
        url = {
            env.var("base_url"),
            "v1",
            "users",
            function()
                return vim.fn.input("ID: ")
            end,
        },
        method = "GET",
    },
}
```

## Environments

Create `.nurl/environments.lua`:

```lua
return {
    default = {
        base_url = "https://api.example.com",
        token = "dev-token",
    },
    staging = {
        base_url = "https://staging.example.com",
        token = "staging-token",
    },
    production = {
        base_url = "https://api.example.com",
        token = "prod-token",
    },
}
```

Access variables in requests:

```lua
local env = require("nurl.environments")

return {
    {
        url = { env.var("base_url"), "users" },
        headers = {
            ["Authorization"] = function()
                return "Bearer " .. env.get("token")
            end,
        },
    },
}
```

- `Nurl.env.var("name")` - Returns a function that resolves the variable (for direct use in the request object and lazy contexts)
- `Nurl.env.get("name")` - Returns the variable value immediately (for use inside functions)

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

Switch environments with `:Nurl env`.

### Setting Variables Programmatically

Use `env.set()` to update environment variables from hooks:

```lua
local env = require("nurl.environments")

return {
    {
        url = "https://api.example.com/login",
        method = "POST",
        data = { username = "user", password = "pass" },
        post_hook = function(request, response)
            local body = vim.json.decode(response.body)
            env.set("token", body.access_token)
        end,
    },
}
```

### Environment Hooks

Add hooks inside each environment:

```lua
return {
    default = {
        base_url = "https://api.example.com",
    },
    production = {
        base_url = "https://api.example.com",
        pre_hook = function(next, request)
            -- Confirm before production requests
            if request.method ~= "GET" then
                vim.ui.select(
                    { "Yes", "No" },
                    { prompt = "Send to production?" },
                    function(choice)
                        if choice == "Yes" then
                            next()
                        end
                    end
                )
            else
                next()
            end
        end,
        post_hook = function(request, response)
            -- Log all requests
            print(
                request.method
                    .. " "
                    .. request.url
                    .. " -> "
                    .. response.status_code
            )
        end,
    },
}
```

## API

```lua
local nurl = require("nurl")

-- Send a request programmatically
nurl.send({
    url = "https://api.example.com/users",
    method = "GET",
}, {
    -- Optional: custom response handler (skips UI)
    on_response = function(response, curl)
        print(response.status_code)
    end,
})

-- Resend last request
nurl.resend_last_request()
nurl.resend_last_request(-2) -- second to last

-- Get active environment
local env_name = nurl.get_active_env()

-- Winbar components (for statusline/winbar)
nurl.winbar.status_code()
nurl.winbar.time()
nurl.winbar.tabs()
```

## Winbar

The response window includes a winbar showing status code, response time, and buffer tabs. Use these in your own winbar:

```lua
vim.o.winbar =
    "%{%v:lua.require('nurl').winbar.status_code()%} %{%v:lua.require('nurl').winbar.tabs()%}"
```

## Highlight Groups

| Group | Description |
|-------|-------------|
| `NurlSpinner` | Loading spinner |
| `NurlElapsedTime` | Elapsed time display |
| `NurlWinbarTabActive` | Active tab in winbar |
| `NurlWinbarTabInactive` | Inactive tab in winbar |
| `NurlWinbarSuccessStatusCode` | 2xx status codes |
| `NurlWinbarErrorStatusCode` | 4xx/5xx status codes |
| `NurlWinbarLoading` | Loading state |
| `NurlWinbarTime` | Response time |
| `NurlWinbarError` | Error messages |

## Recipes

### 1Password CLI for secrets

Use the 1Password CLI (`op`) with `nurl.lazy()` to fetch secrets only when sending:

```lua
local env = require("nurl.environments")

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
        url = { env.var("base_url"), "auth", "login" },
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        data = {
            username = op_get("eeljppn94azg8iqq7rrdtd1g4u", "username"),
            password = op_get("eeljppn94azg8iqq7rrdtd1g4u", "password"),
        },
        post_hook = function(request, response)
            local body = vim.json.decode(response.body)
            env.set("token", body.access_token)
        end,
    },
}
```

### OAuth2 Token Refresh

Auto-refresh expired tokens before requests using environment hooks:

```lua
-- .nurl/environments.lua
local var = require("nurl.environments").var
local get = require("nurl.environments").get
local set = require("nurl.environments").set

local function is_token_expired()
    local expires_at = get("expires_at")
    return not expires_at or tonumber(expires_at) < os.time()
end

local function refresh_token(next)
    Nurl.send({
        url = "https://auth.example.com/oauth/token",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        data = {
            grant_type = "refresh_token",
            refresh_token = var("refresh_token"),
        },
    }, {
        on_response = function(response)
            if response and response.status_code == 201 then
                local body = vim.json.decode(response.body)
                set("access_token", body.access_token)
                set("refresh_token", body.refresh_token)
                set("expires_at", os.time() + body.expires_in)
                next()
            else
                vim.notify("Failed to refresh token", vim.log.levels.ERROR)
            end
        end,
    })
end

return {
    default = {
        base_url = "https://api.example.com",
        access_token = nil,
        refresh_token = nil,
        expires_at = nil,
        pre_hook = function(next, request)
            if is_token_expired() then
                refresh_token(next)
            else
                next()
            end
        end,
    },
}
```

### Using Response Values

Store response data for use in subsequent requests:

```lua
local nurl = require("nurl")
local env = require("nurl.environments")

return {
    {
        url = { env.var("base_url"), "users" },
        method = "POST",
        data = { name = "John Doe", email = "john@example.com" },
        post_hook = function(request, response)
            local user = vim.json.decode(response.body)
            env.set("last_user_id", user.id)
        end,
    },
    {
        url = {
            env.var("base_url"),
            "users",
            env.var("last_user_id"),
            "profile",
        },
        method = "PUT",
        data = { bio = "Software Developer" },
    },
}
```

### HMAC Signature

Sign requests with HMAC-SHA256:

```lua
local env = require("nurl.environments")

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
        url = { env.var("base_url"), "api", "secure" },
        method = "POST",
        headers = function()
            local timestamp = tostring(os.time())
            local signature =
                hmac_sha256(env.get("api_secret"), timestamp .. body)
            return {
                ["Content-Type"] = "application/json",
                ["X-Timestamp"] = timestamp,
                ["X-Signature"] = signature,
            }
        end,
        data = body,
    },
}
```

### Environment-Based Confirmation

Require confirmation before dangerous requests in production:

```lua
-- .nurl/environments.lua
return {
    development = {
        base_url = "https://dev.example.com",
    },
    production = {
        base_url = "https://api.example.com",
        pre_hook = function(next, request)
            if request.method == "GET" then
                next()
                return
            end

            vim.ui.select({ "Yes", "No" }, {
                prompt = "Send to PRODUCTION?",
            }, function(choice)
                if choice == "Yes" then
                    next()
                end
            end)
        end,
    },
}
```

### Response Validation

Validate responses and notify on failure:

```lua
local env = require("nurl.environments")

local function expect_status(codes)
    return function(request, response)
        if not vim.tbl_contains(codes, response.status_code) then
            vim.notify(
                string.format(
                    "Unexpected status %d for %s",
                    response.status_code,
                    request.url
                ),
                vim.log.levels.ERROR
            )
        end
    end
end

local function expect_json_field(field)
    return function(request, response)
        local ok, body = pcall(vim.json.decode, response.body)
        if not ok or body[field] == nil then
            vim.notify("Missing field: " .. field, vim.log.levels.ERROR)
        end
    end
end

return {
    {
        url = { env.var("base_url"), "users", "123" },
        post_hook = function(request, response)
            expect_status({ 200, 201 })(request, response)
            expect_json_field("id")(request, response)
        end,
    },
}
```

### GraphQL with Variables

Build GraphQL queries programmatically:

```lua
local env = require("nurl.environments")

local function graphql(query, variables)
    return {
        url = { env.var("base_url"), "graphql" },
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        data = {
            query = query,
            variables = variables,
        },
    }
end

return {
    graphql(
        [[
        query GetUser($id: ID!) {
            user(id: $id) {
                id
                name
                email
            }
        }
    ]],
        {
            id = function()
                return vim.fn.input("User ID: ")
            end,
        }
    ),
    graphql(
        [[
        mutation CreateUser($input: CreateUserInput!) {
            createUser(input: $input) {
                id
                name
            }
        }
    ]],
        {
            input = {
                name = "John Doe",
                email = "john@example.com",
            },
        }
    ),
}
```

### File Upload with Picker

Select a file to upload using Neovim's UI:

```lua
local function choose_file(next, request)
    vim.ui.input(
        { prompt = "File path: ", completion = "file" },
        function(input)
            if input then
                request.form = { file = "@" .. vim.fn.expand(input) }
                next()
            end
        end
    )
end

return {
    {
        url = { "https://api.example.com/files/upload" },
        method = "POST",
        pre_hook = choose_file,
    },
}
```

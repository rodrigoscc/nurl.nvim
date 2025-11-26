# nurl.nvim

A Lua-based HTTP client for Neovim. Define requests in Lua files, manage environments, add hooks, and view responses in beautiful split windows.

## Table of Contents

- [✨ Features](#features)
- [📋 Requirements](#requirements)
- [📦 Installation](#installation)
- [🚀 Quick Start](#quick-start)
- [⚙️ Configuration](#configuration)
- [💻 Commands](#commands)
- [📝 Request Format](#request-format)
  - [Dynamic Values](#dynamic-values)
  - [URL Parts](#url-parts)
- [🌍 Environments](#environments)
  - [Environment Hooks](#environment-hooks)
- [🔌 API](#api)
- [📊 Winbar](#winbar)
- [🎨 Highlight Groups](#highlight-groups)

## Features

- **Lua-based requests** - Define HTTP requests as Lua tables with full language support
- **Environments** - Manage variables per environment (dev, staging, prod)
- **Request history** - SQLite-backed history with full request/response data
- **Response viewer** - Split window with body, headers, info, and raw curl output tabs
- **Hooks** - Pre/post hooks per request, or per environment (applies to all requests when env is active)
- **Picker integration** - Browse requests and history with [snacks.nvim](https://github.com/folke/snacks.nvim) picker

## Requirements

- Neovim >= 0.10.0
- `curl` in PATH
- [snacks.nvim](https://github.com/folke/snacks.nvim) (for pickers)
- Optional: `jq` for JSON formatting, `stylua` for environments file formatting

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "rodrigoscc/nurl.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {},
}
```

## Quick Start

### 1. Create a request file

Create `.nurl/requests.lua` in your project:

```lua
return {
    {
        url = "https://jsonplaceholder.typicode.com/posts/1",
        method = "GET",
    },
    {
        url = "https://jsonplaceholder.typicode.com/posts",
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
    -- Required: string, table of parts, or function
    url = "https://api.example.com/users",
    url = { "https://api.example.com", "v1", "users" },
    url = function() return "https://api.example.com/users/id" end,

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
                return "Bearer " .. env.var("token")
            end,
        },
    },
}
```

Switch environments with `:Nurl env`.

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
    -- Optional: reuse existing window
    win = vim.api.nvim_get_current_win(),
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

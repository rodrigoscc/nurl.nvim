-- Lua modules can be loaded through package.path without being on runtimepath
-- (as in the test runner). Find the root from this loaded module instead.
local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and vim.uv.fs_realpath(source:sub(2))
assert(file, "Could not locate nurl Lua modules for background workers")

return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(file))) .. "/"

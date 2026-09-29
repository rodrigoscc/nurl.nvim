-- Requests are plain Lua tables
local env = Nurl.env

return {
    {
        title = "Get user",
        url = { env.var("base_url"), "users", 1 },
        test = function(ctx, res)
            ctx.are.equal(200, res.status_code)

            local user = Nurl.helpers.json(res)
            ctx.test("profile", function()
                ctx.are.equal("Ada Lovelace", user.name)
                ctx.is_true(user.active, "user should be active")
            end)
        end,
    },
    {
        title = "Search admins",
        url = { env.var("base_url"), "users" },
        query = { role = "admin", limit = 2 },
    },
    {
        title = "Create post",
        method = "POST",
        url = { env.var("base_url"), "posts" },
        headers = {
            Authorization = function()
                return "Bearer " .. env.get("token")
            end,
        },
        data = { title = "Hello from Neovim", userId = 1 },
    },
}

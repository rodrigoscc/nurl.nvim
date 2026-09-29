local env = Nurl.env

return {
    {
        title = "Get order",
        url = { env.var("base_url"), "orders", 42 },
    },
    {
        title = "Monthly report",
        url = { env.var("base_url"), "reports" },
        query = { month = "2026-09" },
    },
}

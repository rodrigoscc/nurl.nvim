return {
    development = {
        base_url = "http://dev.api.example.com",
        token = "dev-7f3a91",
    },
    production = {
        base_url = "http://api.example.com",
        token = "prod-2c84e0",
        pre_hook = function(next, _, cancel)
            vim.ui.select({ "Send", "Cancel" }, {
                prompt = "Send to production?",
            }, function(choice)
                if choice == "Send" then
                    next()
                else
                    cancel()
                end
            end)
        end,
    },
}

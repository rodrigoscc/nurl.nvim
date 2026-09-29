local fs = require("nurl.data.fs")
local responses = require("nurl.responses")

local M = {}

---Save the body of a response to a new file in dir, for bodies that cannot be
---shown as text such as images. The response and curl's output keep the path
---in place of the body.
---@param response nurl.Response
---@param curl nurl.Curl with its result
---@param dir string
function M.save(response, curl, dir)
    local path = fs.unique_path(
        dir,
        "response",
        responses.file_extension(response.headers)
    )
    -- TODO: what about too large files here?
    fs.write(path, response.body)

    response.body_file = path
    response.body = ""

    local stdout = curl.result.stdout
    curl.result.stdout = stdout:sub(1, response.size.size_header)
        .. "@"
        .. path
end

return M

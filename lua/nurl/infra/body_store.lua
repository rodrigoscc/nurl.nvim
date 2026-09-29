local fs = require("nurl.infra.fs")
local responses = require("nurl.core.response")

local uv = vim.uv or vim.loop

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

---Delete a saved body. The directory save created for it is removed too, unless
---another file was put in it.
---@param path string
---@return string? err
function M.delete(path)
    local removed, err, name = uv.fs_unlink(path)
    if not removed and name ~= "ENOENT" then
        return ("Could not remove history response file %s: %s"):format(
            path,
            err
        )
    end

    local dir = path:match("^(.*)[/\\][^/\\]+$")
    if dir then
        local success, dir_err, dir_name = uv.fs_rmdir(dir)
        if
            not success
            and dir_name ~= "ENOENT"
            and dir_name ~= "ENOTEMPTY"
            and dir_name ~= "EEXIST"
        then
            return ("Could not remove history response directory %s: %s"):format(
                dir,
                dir_err
            )
        end
    end
end

return M

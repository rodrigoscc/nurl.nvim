local kill = require("nurl.kill")

local _id = 0

local function next_id()
    _id = _id + 1
    return _id
end

---@class nurl.RequestHandle
---@field id integer
---@field request nurl.Request
---@field response? nurl.Response
---@field curl? nurl.Curl
---@field test_report? nurl.TestReport
---@field status "pending"|"started"|"completed"|"cancelled"|"failed"
---@field pid? integer
---@field exec_datetime? string
local RequestHandle = {}

function RequestHandle:new(request)
    local o = {
        id = next_id(),
        request = request,
        response = nil,
        curl = nil,
        test_report = nil,
        status = "pending",
    }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function RequestHandle:rebuild(exec_datetime, request, response, curl)
    local o = {
        id = next_id(),
        request = request,
        response = response,
        curl = curl,
        test_report = nil,
        status = "completed",
        exec_datetime = exec_datetime,
    }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function RequestHandle:is_cancelled()
    return self.status == "cancelled"
end

function RequestHandle:is_done()
    return self.status == "completed"
        or self.status == "cancelled"
        or self.status == "failed"
end

function RequestHandle:is_failed()
    return self.status == "failed"
end

---@param pid integer
function RequestHandle:_started(pid)
    self.exec_datetime = tostring(os.date("%Y-%m-%dT%H:%M:%S")) -- local time
    self.pid = pid
    self.status = "started"
end

---@param response nurl.Response
---@param curl nurl.Curl
---@param test_report nurl.TestReport
function RequestHandle:_resolve(response, curl, test_report)
    self.status = "completed"
    self.response = response
    self.curl = curl
    self.test_report = test_report
end

---@param response nurl.Response
---@param curl nurl.Curl
---@param test_report nurl.TestReport
function RequestHandle:_failed(response, curl, test_report)
    self.status = "failed"
    self.response = response
    self.curl = curl
    self.test_report = test_report
end

---@param response nurl.Response
---@param curl nurl.Curl
---@param test_report nurl.TestReport
function RequestHandle:_cancelled(response, curl, test_report)
    self.status = "cancelled"
    self.response = response
    self.curl = curl
    self.test_report = test_report
end

---@param time? integer
---@param interval? integer
---@return nurl.RequestOut
function RequestHandle:wait(time, interval)
    if self:is_done() then
        return {
            request = self.request,
            response = self.response,
            curl = self.curl,
            test_report = self.test_report,
            -- TODO: win?
        }
    end

    time = time or math.huge
    interval = interval or 200

    vim.wait(time, function()
        return self:is_done()
    end, interval)

    return {
        request = self.request,
        response = self.response,
        curl = self.curl,
        test_report = self.test_report,
        -- TODO: win?
    }
end

---@param signame? string the signal to send to the curl pid. Default: "sigterm"
function RequestHandle:cancel(signame)
    kill(self.pid, signame)
end

return RequestHandle

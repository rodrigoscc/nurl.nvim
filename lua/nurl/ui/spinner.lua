---@class Spinner
---@field private frames string[]
---@field private current_frame integer
local Spinner = {
    frames = {
        "⠋",
        "⠙",
        "⠹",
        "⠸",
        "⠼",
        "⠴",
        "⠦",
        "⠧",
        "⠇",
        "⠏",
    },
}

function Spinner:new()
    local o = { current_frame = 1 }
    o = setmetatable(o, self)
    self.__index = self
    return o
end

function Spinner:frame()
    local frame = self.frames[self.current_frame]
    self:advance_frame()
    return frame
end

function Spinner:advance_frame()
    self.current_frame = (self.current_frame % #self.frames) + 1
end

return Spinner

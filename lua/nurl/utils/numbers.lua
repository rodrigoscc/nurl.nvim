local M = {}

---@param bytes number
---@return string
function M.format_bytes(bytes)
    if bytes < 1024 then
        return string.format("%d B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    else
        return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
    end
end

---@param bytes_per_sec number
---@return string
function M.format_speed(bytes_per_sec)
    if bytes_per_sec < 1024 then
        return string.format("%d B/s", bytes_per_sec)
    elseif bytes_per_sec < 1024 * 1024 then
        return string.format("%.1f KB/s", bytes_per_sec / 1024)
    elseif bytes_per_sec < 1024 * 1024 * 1024 then
        return string.format("%.1f MB/s", bytes_per_sec / (1024 * 1024))
    else
        return string.format("%.1f GB/s", bytes_per_sec / (1024 * 1024 * 1024))
    end
end

---@param seconds number
---@return string
function M.format_duration(seconds)
    if seconds < 1 then
        return string.format("%.0fms", seconds * 1000)
    else
        return string.format("%.2fs", seconds)
    end
end

return M

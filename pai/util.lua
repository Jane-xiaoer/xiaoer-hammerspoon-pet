local M = {}

function M.trim(value)
  if value == nil then
    return ""
  end

  return tostring(value):match("^%s*(.-)%s*$")
end

function M.shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.timestamp()
  return os.date("%Y%m%d-%H%M%S")
end

function M.preview(value, limit)
  local text = M.trim(value)
  if text == "" then
    return ""
  end

  local maxLength = limit or 24
  if #text <= maxLength then
    return text
  end

  return text:sub(1, maxLength) .. "..."
end

return M

local M = {}

local logFile = "/tmp/pai-workflow.log"

function M.info(message)
  local line = string.format("%s %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(message))
  local file = io.open(logFile, "a")
  if file then
    file:write(line)
    file:close()
  end
  print(line)
end

function M.path()
  return logFile
end

return M

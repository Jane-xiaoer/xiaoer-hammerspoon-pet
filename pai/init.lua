local companion = require("pai.desktop_companion")

local M = {}

function M.start()
  companion.start()
  hs.alert.show("小耳桌宠已启动", 1.8)
end

function M.stop()
  companion.stop()
end

return M

require("hs.ipc")

package.path = table.concat({
  package.path,
  hs.configdir .. "/?.lua",
  hs.configdir .. "/?/init.lua",
  hs.configdir .. "/?/?.lua",
}, ";")

for moduleName, _ in pairs(package.loaded) do
  if moduleName:match("^pai") then
    package.loaded[moduleName] = nil
  end
end

require("pai").start()

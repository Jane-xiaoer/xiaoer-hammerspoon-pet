local config = require("pai.config")
local log = require("pai.log")
local util = require("pai.util")
local http = require("hs.http")
local httpserver = require("hs.httpserver")

local M = {}

local Companion = {}
Companion.__index = Companion

local MOODS = {
  idle = {
    face = "૮ ˶ᵔ ᵕ ᵔ˶ ა",
    bg = {red = 1.00, green = 0.88, blue = 0.93, alpha = 0.96},
    accent = {red = 0.95, green = 0.48, blue = 0.65, alpha = 0.95},
    shadow = {red = 0.83, green = 0.63, blue = 0.71, alpha = 0.35},
  },
  focus = {
    face = "ᕦ(ò_óˇ)ᕤ",
    bg = {red = 0.84, green = 0.93, blue = 1.00, alpha = 0.96},
    accent = {red = 0.26, green = 0.52, blue = 0.84, alpha = 0.95},
    shadow = {red = 0.34, green = 0.49, blue = 0.71, alpha = 0.35},
  },
  ["break"] = {
    face = "ᐠ( ᐢ ᵕ ᐢ )ᐟ",
    bg = {red = 0.88, green = 0.97, blue = 0.88, alpha = 0.96},
    accent = {red = 0.29, green = 0.65, blue = 0.37, alpha = 0.95},
    shadow = {red = 0.38, green = 0.62, blue = 0.40, alpha = 0.30},
  },
  jumping = {
    face = "٩(ˊᗜˋ*)و",
    bg = {red = 1.00, green = 0.95, blue = 0.82, alpha = 0.96},
    accent = {red = 0.91, green = 0.60, blue = 0.20, alpha = 0.95},
    shadow = {red = 0.82, green = 0.62, blue = 0.32, alpha = 0.30},
  },
  failed = {
    face = "(｡•́︿•̀｡)",
    bg = {red = 1.00, green = 0.91, blue = 0.88, alpha = 0.96},
    accent = {red = 0.88, green = 0.38, blue = 0.30, alpha = 0.95},
    shadow = {red = 0.72, green = 0.40, blue = 0.34, alpha = 0.30},
  },
  hungry = {
    face = "ʕ ˶'༥'˶ ʔ",
    bg = {red = 1.00, green = 0.95, blue = 0.82, alpha = 0.96},
    accent = {red = 0.91, green = 0.60, blue = 0.20, alpha = 0.95},
    shadow = {red = 0.82, green = 0.62, blue = 0.32, alpha = 0.30},
  },
  thirsty = {
    face = "ʕ ˶'ᵕ'˶ ʔ",
    bg = {red = 0.86, green = 0.96, blue = 1.00, alpha = 0.96},
    accent = {red = 0.30, green = 0.62, blue = 0.86, alpha = 0.95},
    shadow = {red = 0.36, green = 0.58, blue = 0.72, alpha = 0.30},
  },
  sleepy = {
    face = "(∪｡∪)｡｡｡zzZ",
    bg = {red = 0.88, green = 0.90, blue = 1.00, alpha = 0.96},
    accent = {red = 0.46, green = 0.52, blue = 0.87, alpha = 0.95},
    shadow = {red = 0.48, green = 0.50, blue = 0.72, alpha = 0.32},
  },
}

local function currentTimestamp()
  return os.time()
end

-- ── Beijing time helpers (UTC+8) ─────────────────────────
-- The previous implementations were mis-named "china" but actually returned
-- the host machine's LOCAL time. On a US-timezone Mac this meant everything
-- the panel / head-clock displayed was US time. Fix: shift the Unix ts by
-- +8h and render via `os.date("!...")` so we read UTC fields on a timestamp
-- that has already been advanced into the Beijing wall clock.
local BEIJING_OFFSET_SECONDS = 8 * 3600

-- Host's offset from UTC in seconds. PDT returns -25200, Beijing host +28800.
-- The naive `os.time(os.date("!*t", now))` approach IGNORES DST on macOS Lua
-- (always treats the UTC table as standard time), so during PDT it reports
-- -8h instead of -7h, breaking round-trip validation in dateTimeToTimestamp.
-- Use the %z RFC-2822 offset string as the authoritative source.
local function localOffsetFromUtc()
  local offStr = os.date("%z")  -- e.g. "-0700" during PDT, "+0800" in Beijing
  if type(offStr) ~= "string" or #offStr < 5 then return 0 end
  local sign = (offStr:sub(1, 1) == "-") and -1 or 1
  local hh = tonumber(offStr:sub(2, 3)) or 0
  local mm = tonumber(offStr:sub(4, 5)) or 0
  return sign * (hh * 3600 + mm * 60)
end

local function chinaDateTable(ts)
  ts = ts or os.time()
  return os.date("!*t", ts + BEIJING_OFFSET_SECONDS)
end

local function chinaDateString(fmt, ts)
  ts = ts or os.time()
  local cleanFmt = fmt
  if type(cleanFmt) == "string" and cleanFmt:sub(1, 1) == "!" then
    cleanFmt = cleanFmt:sub(2)
  end
  return os.date("!" .. cleanFmt, ts + BEIJING_OFFSET_SECONDS)
end

-- Given Beijing wall-clock (year, month, day, hour, minute), return the
-- corresponding Unix UTC timestamp — correct regardless of host timezone.
local function chinaTimeToEpoch(year, month, day, hour, minute)
  local t = { year = year, month = month, day = day,
              hour = hour, min = minute, sec = 0 }
  -- os.time interprets the table as LOCAL time; we correct by shifting from
  -- local-offset to Beijing offset.
  local tsLocal = os.time(t)
  return tsLocal + localOffsetFromUtc() - BEIJING_OFFSET_SECONDS
end

local function nextChinaEpoch(hour, minute)
  local now = os.time()
  local today = chinaDateTable(now)
  local candidate = chinaTimeToEpoch(today.year, today.month, today.day, hour, minute)
  if candidate <= now + 30 then
    local tomorrow = chinaDateTable(now + 86400)
    candidate = chinaTimeToEpoch(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute)
  end
  return candidate
end

local function readableNow()
  return chinaDateString("%Y-%m-%d %H:%M:%S")
end

local function readJsonFile(path)
  local attributes = hs.fs.attributes(path)
  if not attributes then
    return nil
  end

  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, decoded = pcall(hs.json.decode, content)
  if ok then
    return decoded
  end

  return nil
end

local function fileModificationTime(path)
  local attributes = hs.fs.attributes(path)
  if not attributes then
    return nil
  end
  return tonumber(attributes.modification) or tonumber(attributes.change)
end

local function writeJsonFile(path, value)
  local file = io.open(path, "w")
  if not file then
    return false
  end

  file:write(hs.json.encode(value, true) or "{}")
  file:close()
  return true
end

local function secondsToClock(seconds)
  local total = math.max(0, math.floor(seconds))
  local minutes = math.floor(total / 60)
  local remainSeconds = total % 60
  return string.format("%02d:%02d", minutes, remainSeconds)
end

local WEEKDAY_LABELS = {
  [1] = "星期日",
  [2] = "星期一",
  [3] = "星期二",
  [4] = "星期三",
  [5] = "星期四",
  [6] = "星期五",
  [7] = "星期六",
}

local function timeLabel(timestamp)
  return chinaDateString("%m-%d %H:%M", timestamp)
end

local function eventDateTimeLabel(timestamp)
  return chinaDateString("%Y-%m-%d %H:%M", timestamp)
end

local function weekdayLabel(dateTable)
  local t = dateTable or chinaDateTable()
  return WEEKDAY_LABELS[t.wday] or ""
end

-- Short weekday — just the final character (日/一/二/...) for compact single-line
-- rows like "4.25 周六 09:00" in the future reminders list.
local WEEKDAY_SHORT = {"日","一","二","三","四","五","六"}
local function weekdayShort(dateTable)
  local t = dateTable or chinaDateTable()
  return WEEKDAY_SHORT[t.wday] or ""
end

local function todayPanelLabel()
  local t = chinaDateTable()
  return string.format("%d月%d日 %s", t.month, t.day, weekdayLabel(t))
end

local function clockToTimestamp(clockText)
  local normalized = tostring(clockText or ""):gsub("：", ":")
  local hour, minute = normalized:match("^(%d%d?)%:(%d%d)$")
  hour = tonumber(hour)
  minute = tonumber(minute)
  if not hour or not minute or hour > 23 or minute > 59 then
    return nil
  end

  local now = currentTimestamp()
  local today = chinaDateTable(now)
  local timestamp = chinaTimeToEpoch(today.year, today.month, today.day, hour, minute)
  if timestamp <= now + 30 then
    local tomorrow = chinaDateTable(now + 86400)
    timestamp = chinaTimeToEpoch(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute)
  end
  return timestamp
end

local function dateTimeToTimestamp(dateText, clockText)
  local normalizedDate = util.trim(tostring(dateText or "")):gsub("%.", "-"):gsub("/", "-")
  local year, month, day = normalizedDate:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  if not year or not month or not day then
    return nil, "日期请写成 YYYY-MM-DD"
  end

  local normalizedTime = tostring(clockText or ""):gsub("：", ":")
  local hour, minute = normalizedTime:match("^(%d%d?)%:(%d%d)$")
  hour = tonumber(hour)
  minute = tonumber(minute)
  if not hour or not minute or hour > 23 or minute > 59 then
    return nil, "时间请写成 HH:MM"
  end

  local timestamp = chinaTimeToEpoch(year, month, day, hour, minute)
  local parts = chinaDateTable(timestamp)
  if parts.year ~= year or parts.month ~= month or parts.day ~= day
      or parts.hour ~= hour or parts.min ~= minute then
    return nil, "日期或时间无效"
  end

  return timestamp
end

local function playNamedSound(name, volume)
  local sound = hs.sound.getByName(name)
  if not sound then
    return false
  end

  sound:stop()
  sound:volume(volume or 0.8)
  sound:play()
  return true
end

local function playReminderSound()
  local playedPrimary = playNamedSound("Hero", 0.95)
  if not playedPrimary then
    playedPrimary = playNamedSound("Glass", 0.95)
  end
  if not playedPrimary then
    playedPrimary = playNamedSound("Funk", 0.95)
  end
  if not playedPrimary then
    playNamedSound("Pop", 0.95)
  end

  hs.timer.doAfter(0.16, function()
    if not playNamedSound("Purr", 0.72) then
      playNamedSound("Glass", 0.72)
    end
  end)

  hs.timer.doAfter(0.36, function()
    playNamedSound("Glass", 0.58)
  end)
end

local function playDismissSound()
  if not playNamedSound("Pop", 0.85) then
    playNamedSound("Bottle", 0.8)
  end
end

local function countDone(todos)
  local done = 0
  for _, todo in ipairs(todos) do
    if todo.done then
      done = done + 1
    end
  end
  return done
end

local function safeImage(path)
  if not path or path == "" then
    return nil
  end

  local attributes = hs.fs.attributes(path)
  if not attributes then
    return nil
  end

  return hs.image.imageFromPath(path)
end

local function pathJoin(...)
  local parts = {...}
  local path = ""
  for _, part in ipairs(parts) do
    local text = tostring(part or "")
    if text ~= "" then
      if path == "" then
        path = text:gsub("/+$", "")
      else
        path = path .. "/" .. text:gsub("^/+", ""):gsub("/+$", "")
      end
    end
  end
  return path
end

local ANIMATION_STATES = {
  "idle",
  "running-right",
  "running-left",
  "waving",
  "jumping",
  "failed",
  "waiting",
  "eureka",
  "running",
  "yoga",
  "tree",
  "fishbowl",
  "review",
  "working",
  "eating",
  "sleeping",
  "drinking",
}

local function loadAnimationFrames(root)
  local animations = {}
  if not root or root == "" or not hs.fs.attributes(root) then
    return animations
  end

  for _, state in ipairs(ANIMATION_STATES) do
    local dir = pathJoin(root, state)
    if hs.fs.attributes(dir) then
      local paths = {}
      for file in hs.fs.dir(dir) do
        if file:match("^%d+%.png$") then
          table.insert(paths, pathJoin(dir, file))
        end
      end
      table.sort(paths)

      local frames = {}
      for _, path in ipairs(paths) do
        local image = safeImage(path)
        if image then
          table.insert(frames, { image = image, path = path })
        end
      end

      if #frames > 0 then
        animations[state] = frames
      end
    end
  end

  return animations
end

local function htmlEscape(value)
  local text = tostring(value or "")
  text = text:gsub("&", "&amp;")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  text = text:gsub('"', "&quot;")
  return text
end

local function fileUrlForPath(path)
  if not path or path == "" then
    return ""
  end

  local encoded = tostring(path):gsub("([^%w%-%._~/])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)

  return "file://" .. encoded
end

local function shiftedCoordinates(points, dx, dy)
  local shifted = {}
  for _, point in ipairs(points) do
    table.insert(shifted, {
      x = point.x + dx,
      y = point.y + dy,
    })
  end
  return shifted
end

local function queryItemsToMap(parts)
  local result = {}
  for _, item in ipairs(parts.queryItems or {}) do
    for key, value in pairs(item) do
      result[key] = value
    end
  end
  return result
end

function Companion.new()
  local self = setmetatable({}, Companion)
  self.statePath = config.companion.state_path
  self.canvas = nil
  self.animationTimer = nil
  self.focusTimer = nil
  self.reminderTimers = {}
  self.screenWatcher = nil
  self.panel = nil
  self.panelVisible = false
  self.bubbleCanvas = nil
  self.bubbleHideTimer = nil
  self.spotlightCanvas = nil
  self.spotlightTimer = nil
  self.spotlightHideTimer = nil
  self.spotlightAnimationTimer = nil
  self.spotlightStepTimers = {}
  self.spotlightCompanionHidden = false
  self.nudgeTimer = nil
  self.initialNudgeTimer = nil
  self.dayRolloverTimer = nil
  self.panelActionTimer = nil
  self.panelActionInFlight = false
  self.panelActionServer = nil
  self.stateSyncTimer = nil
  self.dragTap = nil
  self.dragStartMouse = nil
  self.dragLastMouse = nil
  self.dragStartFrame = nil
  self.dragAnimationState = nil
  self.didDrag = false
  self.phase = 0
  self.anchorFrame = nil
  self.images = {
    idle = safeImage(config.companion.companion_image_path),
    focus = safeImage(config.companion.companion_focus_image_path),
    ["break"] = safeImage(config.companion.companion_break_image_path),
    hungry = safeImage(config.companion.companion_hungry_image_path),
    sleepy = safeImage(config.companion.companion_sleepy_image_path),
  }
  self.imagePaths = {
    idle = config.companion.companion_image_path,
    focus = config.companion.companion_focus_image_path,
    ["break"] = config.companion.companion_break_image_path,
    hungry = config.companion.companion_hungry_image_path,
    sleepy = config.companion.companion_sleepy_image_path,
  }
  -- Idle rotation pool — array of (image, path) pairs. Populated from
  -- config.companion.companion_idle_image_paths if present. When non-empty,
  -- currentImageForMood picks from this pool every 5 minutes.
  self.idlePool = {}
  local poolPaths = config.companion.companion_idle_image_paths
  if type(poolPaths) == "table" then
    for _, p in ipairs(poolPaths) do
      local img = safeImage(p)
      if img then
        table.insert(self.idlePool, { image = img, path = p })
      end
    end
  end
  self.animationFrames = loadAnimationFrames(config.companion.companion_animation_root)
  self.animationFrameInterval = config.companion.animation_frame_interval_seconds or config.companion.animation_interval_seconds or 0.18
  self.image = self.images.idle or self.images.focus or self.images["break"] or self.images.hungry or self.images.sleepy
  self.tempMood = nil
  self.tempMoodUntil = nil
  self.state = {
    todos = {},
    focus_end_at = nil,
    focus_started_at = nil,
    companion_position = nil,
    custom_reminders = {},
  }

  self:loadState()
  return self
end

function Companion:todayKey()
  return chinaDateString("%Y-%m-%d")
end

function Companion:loadState()
  local decoded = readJsonFile(self.statePath)
  if type(decoded) == "table" then
    self.state.todos = decoded.todos or {}
    self.state.focus_end_at = decoded.focus_end_at
    self.state.focus_started_at = decoded.focus_started_at
    self.state.companion_position = decoded.companion_position
    self.state.custom_reminders = decoded.custom_reminders or {}
  end
  self:pruneTodos()
  self.lastStateMtime = fileModificationTime(self.statePath)
end

function Companion:saveState()
  local parent = self.statePath:match("(.+)/[^/]+$")
  if parent then
    hs.fs.mkdir(parent)
  end

  writeJsonFile(self.statePath, self.state)
  self.lastStateMtime = fileModificationTime(self.statePath) or currentTimestamp()
end

function Companion:pruneTodos()
  local today = self:todayKey()
  local kept = {}
  for _, todo in ipairs(self.state.todos or {}) do
    if todo.day == today then
      table.insert(kept, todo)
    end
  end
  self.state.todos = kept
  self:saveState()
end

function Companion:getTodayTodos()
  local today = self:todayKey()
  local todos = {}
  for _, todo in ipairs(self.state.todos or {}) do
    if todo.day == today then
      table.insert(todos, todo)
    end
  end

  table.sort(todos, function(a, b)
    if a.done ~= b.done then
      return not a.done
    end
    return (a.created_at or "") < (b.created_at or "")
  end)
  return todos
end

function Companion:getTodoById(todoId)
  for _, todo in ipairs(self.state.todos or {}) do
    if todo.id == todoId then
      return todo
    end
  end
  return nil
end

function Companion:getCustomReminders()
  local reminders = {}
  for _, reminder in ipairs(self.state.custom_reminders or {}) do
    if tonumber(reminder.at or 0) then
      table.insert(reminders, reminder)
    end
  end

  table.sort(reminders, function(a, b)
    local aPending = not a.triggered_at
    local bPending = not b.triggered_at
    if aPending ~= bPending then
      return aPending
    end
    return (tonumber(a.at or 0) or 0) < (tonumber(b.at or 0) or 0)
  end)
  return reminders
end

function Companion:removeCustomReminder(reminderId, shouldRefreshTimers)
  local kept = {}
  for _, reminder in ipairs(self.state.custom_reminders or {}) do
    if reminder.id ~= reminderId then
      table.insert(kept, reminder)
    end
  end
  self.state.custom_reminders = kept
  self:saveState()
  if shouldRefreshTimers ~= false then
    self:setupReminderTimers()
  end
end

function Companion:addCustomReminder(text, dateText, clockText)
  local trimmedText = util.trim(text)
  if trimmedText == "" then
    return false, "提醒内容还没写"
  end

  local targetTimestamp, err = dateTimeToTimestamp(dateText, clockText)
  if not targetTimestamp then
    return false, err or "日期时间无效"
  end

  table.insert(self.state.custom_reminders, {
    id = util.timestamp() .. "-reminder-" .. tostring(math.random(1000, 9999)),
    text = trimmedText,
    at = targetTimestamp,
    created_at = readableNow(),
    triggered_at = nil,
  })
  self:saveState()
  self:setupReminderTimers()
  self:setTemporaryMood("idle", 10)
  self:updateVisualState()
  return true, string.format("已安排事件提醒：%s", eventDateTimeLabel(targetTimestamp))
end

function Companion:addTodo(text)
  local trimmed = util.trim(text)
  if trimmed == "" then
    return
  end

  table.insert(self.state.todos, {
    id = util.timestamp() .. "-" .. tostring(math.random(1000, 9999)),
    text = trimmed,
    day = self:todayKey(),
    done = false,
    created_at = readableNow(),
  })
  self:saveState()
  self:setTemporaryMood("idle", 8)
  self:updateVisualState()
end

function Companion:addTodosBatch(items)
  local inserted = 0
  for _, item in ipairs(items or {}) do
    local trimmed = util.trim(item)
    if trimmed ~= "" then
      table.insert(self.state.todos, {
        id = util.timestamp() .. "-" .. tostring(math.random(1000, 9999)),
        text = trimmed,
        day = self:todayKey(),
        done = false,
        created_at = readableNow(),
      })
      inserted = inserted + 1
    end
  end

  if inserted > 0 then
    self:saveState()
    hs.alert.show("已加入 " .. tostring(inserted) .. " 条待办", 1.5)
    self:setTemporaryMood("idle", 10)
    self:updateVisualState()
  end
end

function Companion:toggleTodo(todoId)
  local todo = self:getTodoById(todoId)
  if not todo then
    return
  end

  todo.done = not todo.done
  todo.completed_at = todo.done and readableNow() or nil
  local allDone = false
  if todo.done then
    local today = self:todayKey()
    local total = 0
    local remaining = 0
    for _, item in ipairs(self.state.todos or {}) do
      if item.day == today then
        total = total + 1
        if not item.done then
          remaining = remaining + 1
        end
      end
    end
    allDone = total > 0 and remaining == 0
  end

  self:saveState()
  if allDone then
    self:setTemporaryMood("jumping", 8)
  else
    self:setTemporaryMood(todo.done and "break" or "idle", 6)
  end
  self:updateVisualState()
end

function Companion:clearCompletedTodos()
  local kept = {}
  for _, todo in ipairs(self.state.todos or {}) do
    if not todo.done then
      table.insert(kept, todo)
    end
  end
  self.state.todos = kept
  self:saveState()
  self:updateVisualState()
end

function Companion:isFocusing()
  return self:getFocusRemainingSeconds() > 0
end

function Companion:getFocusRemainingSeconds()
  local endsAt = tonumber(self.state.focus_end_at or 0) or 0
  return math.max(0, endsAt - currentTimestamp())
end

function Companion:setTemporaryMood(mood, seconds)
  self.tempMood = mood
  self.tempMoodUntil = currentTimestamp() + (seconds or 10)
end

function Companion:currentMoodName()
  if self:isFocusing() then
    return "focus"
  end

  if self.tempMood == "focus" then
    self.tempMood = nil
    self.tempMoodUntil = nil
    return "idle"
  end

  if self.tempMood and self.tempMoodUntil and currentTimestamp() <= self.tempMoodUntil then
    return self.tempMood
  end

  return "idle"
end

-- Idle rotates through self.idlePool on a stable 5-minute time-slot boundary
-- so the choice doesn't flicker across per-second updateVisualState() ticks.
local IDLE_ROTATE_PERIOD_SECONDS = 5 * 60
local function pickIdlePoolEntry(pool)
  if not pool or #pool == 0 then return nil end
  local slot = math.floor(os.time() / IDLE_ROTATE_PERIOD_SECONDS) % #pool
  return pool[slot + 1]  -- Lua arrays are 1-based
end

function Companion:animationStateForMood(moodName)
  local name = moodName or self:currentMoodName()
  if name == "idle" then
    local cycle = config.companion.companion_idle_animation_cycle_states
    if type(cycle) == "table" and #cycle > 0 then
      local period = math.max(1, tonumber(config.companion.companion_idle_animation_cycle_seconds or 600) or 600)
      local slot = (math.floor(os.time() / period) % #cycle) + 1
      local state = cycle[slot]
      if type(state) == "string" and self.animationFrames and self.animationFrames[state] then
        return state
      end
    end
  end

  local map = config.companion.companion_animation_mood_map
  if type(map) == "table" and type(map[name]) == "string" then
    return map[name]
  end
  return name
end

function Companion:currentAnimationFrameEntry(moodName)
  local state = self:animationStateForMood(moodName)
  local frames = self.animationFrames and self.animationFrames[state]
  if not frames or #frames == 0 then
    return nil
  end

  local interval = math.max(0.05, tonumber(self.animationFrameInterval or 0.18) or 0.18)
  local index = (math.floor(hs.timer.secondsSinceEpoch() / interval) % #frames) + 1
  return frames[index]
end

function Companion:currentImageForMood(moodName)
  local name = moodName or self:currentMoodName()
  local animated = self:currentAnimationFrameEntry(name)
  if animated and animated.image then
    return animated.image
  end

  if name == "idle" then
    local entry = pickIdlePoolEntry(self.idlePool)
    if entry and entry.image then return entry.image end
  end
  return (self.images and self.images[name]) or (self.images and self.images.idle) or nil
end

function Companion:currentImagePathForMood(moodName)
  local name = moodName or self:currentMoodName()
  local animated = self:currentAnimationFrameEntry(name)
  if animated and animated.path then
    return animated.path
  end

  if name == "idle" then
    local entry = pickIdlePoolEntry(self.idlePool)
    if entry and entry.path then return entry.path end
  end
  return (self.imagePaths and self.imagePaths[name]) or (self.imagePaths and self.imagePaths.idle) or ""
end

function Companion:usesImageCompanion()
  return self:currentImageForMood("idle") ~= nil
    or self:currentImageForMood("focus") ~= nil
    or self:currentImageForMood("break") ~= nil
    or self:currentImageForMood("hungry") ~= nil
    or self:currentImageForMood("thirsty") ~= nil
    or self:currentImageForMood("sleepy") ~= nil
end

function Companion:statusText()
  if self:isFocusing() then
    return "doing " .. secondsToClock(self:getFocusRemainingSeconds())
  end

  local todos = self:getTodayTodos()
  return string.format("plan %d/%d", countDone(todos), #todos)
end

function Companion:focusChoiceText()
  if self:isFocusing() then
    return "doing " .. secondsToClock(self:getFocusRemainingSeconds())
  end
  return "do"
end

function Companion:renderPanelHtml()
  local todos = self:getTodayTodos()
  local reminders = self:getCustomReminders()
  local actionEndpoint = string.format("http://127.0.0.1:%d/companion-action", config.companion.panel_action_port)
  local panelMood = MOODS[self:currentMoodName()] or MOODS.idle
  local panelFace = htmlEscape(panelMood.face or MOODS.idle.face)
  local panelFacePath = self:currentImagePathForMood()
  local ownerName = htmlEscape(config.companion.owner_name or "小耳")
  local panelSkinUrl = htmlEscape(fileUrlForPath((os.getenv("HOME") or "") .. "/.hammerspoon/pai/assets/companion/panel/panel-paper-332x520.png"))
  local faceMarkup = string.format('<div class="face face-emoji">%s</div>', panelFace)
  if panelFacePath ~= "" then
    faceMarkup = string.format(
      '<div class="face face-image"><img src="%s" alt="%s" /></div>',
      htmlEscape(fileUrlForPath(panelFacePath)),
      ownerName
    )
  end

  -- ── todos ──────────────────────────────────
  local todoItems = {}
  for _, todo in ipairs(todos) do
    table.insert(todoItems, string.format([[
      <div class="todo-row %s" data-todo-id="%s" role="button" tabindex="0">
        <button type="button" class="todo-check %s" tabindex="-1" aria-hidden="true">%s</button>
        <div class="todo-copy"><div class="todo-text">%s</div></div>
      </div>
    ]], todo.done and "todo-done" or "", htmlEscape(todo.id), todo.done and "checked" or "", todo.done and "✓" or "", htmlEscape(todo.text)))
  end
  if #todoItems == 0 then
    table.insert(todoItems, [[
      <div class="empty-state">
        <div class="empty-title">0/0</div>
      </div>
    ]])
  end
  local inputRows = {}
  for _ = 1, 4 do
    table.insert(inputRows, string.format([[
      <div class="todo-input-row">
        <span class="todo-check ghost"></span>
        <input class="todo-input" type="text" placeholder="" />
      </div>
    ]]))
  end

  -- ── reminders split into today vs future (Beijing-local date comparison) ──
  local todayKey = self:todayKey()
  local todayReminderItems = {}
  local futureReminderItems = {}
  for _, reminder in ipairs(reminders) do
    local dt = chinaDateTable(reminder.at)
    local rKey = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
    local rowHtml
    if rKey == todayKey then
      rowHtml = string.format([[
        <div class="event-row %s">
          <div class="event-time">%s</div>
          <div class="event-text">%s</div>
          <button type="button" class="icon-btn" onclick="postAction('remove_custom_reminder', { reminder_id: '%s' })">×</button>
        </div>
      ]],
        reminder.triggered_at and "event-done" or "",
        htmlEscape(chinaDateString("%H:%M", reminder.at)),
        htmlEscape(reminder.text),
        htmlEscape(reminder.id))
      table.insert(todayReminderItems, rowHtml)
    elseif rKey > todayKey then
      -- Single-line compact: "4.25 周六 09:00 · 事件文字"
      rowHtml = string.format([[
        <div class="event-row future">
          <div class="event-meta">%d.%d 周%s %s</div>
          <div class="event-text">%s</div>
          <button type="button" class="icon-btn" onclick="postAction('remove_custom_reminder', { reminder_id: '%s' })">×</button>
        </div>
      ]],
        dt.month, dt.day,
        weekdayShort(dt),
        htmlEscape(chinaDateString("%H:%M", reminder.at)),
        htmlEscape(reminder.text),
        htmlEscape(reminder.id))
      table.insert(futureReminderItems, rowHtml)
    end
  end
  if #todayReminderItems == 0 then
    table.insert(todayReminderItems, [[
      <div class="empty-state">
        <div class="empty-title">无</div>
      </div>
    ]])
  end
  if #futureReminderItems == 0 then
    table.insert(futureReminderItems, [[
      <div class="empty-state">
        <div class="empty-title">无</div>
      </div>
    ]])
  end

  -- ── Which tab is currently active (persisted in state so it survives
  -- post-action HTML re-renders). Default first load → pomodoro.
  local activeTab = self.state.active_tab or "pomodoro"
  local function tabCls(tab) return (tab == activeTab) and " active" or "" end

  -- ── greeting + header line ─────────────────
  local nowTable = chinaDateTable()
  local hour = nowTable.hour
  local greeting
  if hour < 5 then greeting = "深夜了,别太累"
  elseif hour < 11 then greeting = "早上好呀"
  elseif hour < 14 then greeting = "中午好,吃了吗"
  elseif hour < 18 then greeting = "下午好"
  elseif hour < 22 then greeting = "晚上好"
  else greeting = "又是熬夜的晚上" end
  local headerDate = todayPanelLabel() .. " " .. chinaDateString("%H:%M")

  -- ── pomodoro state ──────────────────────────
  local focusActive = self:isFocusing()
  local focusRemaining = self:getFocusRemainingSeconds()
  local focusDurationSec = config.companion.focus_minutes * 60
  local focusDisplay = focusActive
    and secondsToClock(focusRemaining)
    or secondsToClock(focusDurationSec)
  local focusPct = focusActive and math.max(0, math.min(100,
    math.floor((1 - focusRemaining / focusDurationSec) * 100))) or 0
  local focusAction = focusActive and "stop_focus" or "start_focus"
  local focusButtonLabel = focusActive and "stop" or "go"

  return string.format([[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    :root {
      color-scheme: light;
      --ink: #4a3440;
      --ink-muted: #856b78;
      --ink-faint: #b8a0aa;
      --rose: #d986a0;
      --rose-deep: #bf6e8a;
      --rose-wash: rgba(217,134,160,0.16);
      --sage: #7b946b;
      --paper: rgba(255, 242, 228, 0.72);
      --paper-strong: rgba(255, 249, 241, 0.84);
      --line: rgba(123, 82, 65, 0.22);
      --font-hand: "Klee", "YuKyokasho", "HanziPen SC", "Hannotate SC", "Kaiti SC", "PingFang SC", cursive;
      --font-number: "Klee", "Chalkboard SE", "Bradley Hand", "YuKyokasho", cursive;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    /* Fully transparent window — no opaque body, no ambient gradient.
       The card alone carries the glass look. */
    html, body {
      height: 100%%;
      width: 100%%;
      background: transparent !important;
      font-family: var(--font-hand);
      color: var(--ink);
      overflow: hidden;
    }
    .card {
      position: absolute; inset: 0;
      border-radius: 20px;
      background: transparent;
      backdrop-filter: none;
      -webkit-backdrop-filter: none;
      border: 0;
      box-shadow: 0 9px 18px rgba(105, 76, 64, 0.07);
      display: flex; flex-direction: column; overflow: hidden;
      transform-origin: left top;
      animation: card-grow 480ms cubic-bezier(.2, 1.2, .3, 1);
    }
    .panel-skin {
      position: absolute; inset: 0;
      width: 100%%; height: 100%%;
      object-fit: fill;
      pointer-events: none;
      z-index: 0;
      user-select: none;
    }
    .sketch-overlay {
      display: none;
    }
    @keyframes card-grow {
      from { transform: scale(0.25); opacity: 0; }
      60%%  { transform: scale(1.04); opacity: 1; }
      to   { transform: scale(1); opacity: 1; }
    }
    /* ── Header: avatar + greeting + date + close ── */
    .card-header {
      position: relative; z-index: 5;
      display: flex; align-items: center; gap: 11px;
      padding: 16px 17px 8px;
    }
    .header-text { flex: 1; min-width: 0; }
    .header-title {
      font-family: var(--font-hand);
      font-size: 17px; font-weight: 700; color: var(--ink);
      line-height: 1.18; margin-bottom: 1px;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .header-sub {
      font-size: 12px; color: var(--ink-muted);
      font-family: var(--font-number);
      letter-spacing: 0.4px;
    }
    .btn-close {
      width: 28px; height: 28px; border-radius: 50%%;
      border: 1px solid rgba(126, 90, 74, 0.16);
      background:
        radial-gradient(circle at 32%% 18%%, rgba(255,255,255,0.62), transparent 42%%),
        rgba(255,255,255,0.36);
      color: var(--ink-muted);
      font-size: 15px; line-height: 1; cursor: pointer;
      display: flex; align-items: center; justify-content: center;
      font-family: var(--font-hand);
      transform: rotate(-4deg);
    }
    .btn-close:hover { background: var(--rose-wash); color: var(--rose-deep); }

    /* ── Tab pills ── */
    .tab-bar {
      display: flex; gap: 3px;
      margin: 7px 17px 12px;
      padding: 4px;
      background: rgba(255, 246, 238, 0.25);
      border: 0;
      border-radius: 17px 15px 19px 16px / 15px 19px 15px 18px;
      position: relative; z-index: 5;
    }
    .tab-bar::before,
    .tab-bar::after {
      content: "";
      position: absolute; inset: 0;
      border: 0.8px solid rgba(126,90,74,0.12);
      border-radius: 19px 15px 17px 16px / 14px 19px 15px 18px;
      pointer-events: none;
    }
    .tab-bar::after {
      inset: 2px 1px 1px 2px;
      opacity: 0.45;
      transform: rotate(-0.35deg);
    }
    .tab-pill {
      flex: 1; padding: 7px 0;
      font-family: var(--font-hand);
      font-size: 16px; font-weight: 700;
      border: 0; border-radius: 16px 13px 15px 14px / 13px 16px 12px 15px;
      background: transparent; color: var(--ink-muted);
      cursor: pointer; font-family: inherit;
      transition: all 180ms;
    }
    .tab-pill:hover { color: var(--ink); }
    .tab-pill.active {
      background:
        radial-gradient(ellipse at 26%% 20%%, rgba(255,255,255,0.26), transparent 36%%),
        radial-gradient(ellipse at 78%% 74%%, rgba(163,88,113,0.13), transparent 48%%),
        linear-gradient(135deg, rgba(221,144,163,0.58), rgba(230,167,181,0.46));
      color: #fffaf8;
      box-shadow: 0 1px 4px rgba(160, 91, 114, 0.09);
      transform: rotate(-1.2deg);
    }

    /* ── Content area ── */
    .content { position: relative; z-index: 5; flex: 1; overflow-y: auto; padding: 3px 17px 16px; }
    .tab-panel { display: none; }
    .tab-panel.active { display: block; animation: fade-in 200ms ease; }
    @keyframes fade-in { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: translateY(0); } }

    /* ── Pomodoro ── */
    .pomo-ring-wrap {
      position: relative; width: 176px; height: 176px; margin: 24px auto 21px;
    }
    .pomo-ring, .pomo-ring-fg {
      position: absolute; inset: 0; border-radius: 50%%;
    }
    .pomo-ring {
      border: 0;
    }
    .pomo-ring::before,
    .pomo-ring::after {
      content: "";
      position: absolute;
      inset: 3px 1px 0 4px;
      border: 3px solid rgba(197, 124, 139, 0.18);
      border-radius: 48%% 52%% 50%% 49%% / 51%% 47%% 53%% 49%%;
      transform: rotate(-1.4deg);
    }
    .pomo-ring::after {
      inset: 7px 4px 4px 1px;
      border-width: 1px;
      opacity: 0.28;
      transform: rotate(1.1deg);
    }
    .pomo-ring-fg {
      background: conic-gradient(rgba(204,125,142,0.40) 0%%, rgba(204,125,142,0.40) var(--pct, 0%%), transparent var(--pct, 0%%));
      opacity: 0.58;
      -webkit-mask: radial-gradient(circle, transparent 79px, #000 83px);
      mask: radial-gradient(circle, transparent 79px, #000 83px);
    }
    .pomo-center {
      position: absolute; inset: 0;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
    }
    .pomo-status, .pomo-duration { display: none; }
    .pomo-time { font-size: 36px; font-weight: 500; letter-spacing: 0.2px; color: var(--ink); font-family: var(--font-number); }
    .pomo-controls { display: flex; justify-content: center; gap: 7px; margin-bottom: 9px; }
    .btn {
      appearance: none; border: none; border-radius: 17px 15px 16px 15px / 15px 17px 13px 16px; padding: 9px 23px;
      font-family: var(--font-hand);
      font-size: 13px; font-weight: 700; cursor: pointer;
      transition: transform 120ms ease, opacity 120ms ease;
      font-family: inherit;
    }
    .btn:hover { transform: translateY(-1px); }
    .btn-primary {
      background:
        radial-gradient(ellipse at 30%% 18%%, rgba(255,255,255,0.32), transparent 38%%),
        linear-gradient(180deg, rgba(232,218,153,0.64), rgba(210,194,124,0.46));
      color: #5f4635; box-shadow: 0 3px 7px rgba(139,109,64,0.09);
      border: 0.8px dashed rgba(112, 83, 56, 0.32);
      transform: rotate(-0.8deg);
    }
    .btn-secondary {
      background: rgba(255,255,255,0.42); color: var(--ink);
      border: 1px solid var(--line);
    }

    /* ── Todos ── */
    .todo-list {
      display: flex; flex-direction: column; gap: 7px;
      max-height: 155px; overflow-y: auto; padding-right: 1px; margin-bottom: 9px;
    }
    .todo-row {
      display: flex; gap: 7px; align-items: center; padding: 7px 9px;
      border-radius: 16px 13px 15px 13px / 13px 16px 13px 15px; background: transparent;
      border: 0.8px solid rgba(126, 90, 74, 0.08);
      cursor: pointer;
    }
    .todo-row:hover { border-color: rgba(185, 112, 139, 0.22); }
    .todo-row.todo-done { background: rgba(236,246,239,0.18); }
    .todo-check {
      width: 19px; height: 19px; flex: 0 0 auto; border-radius: 50%%;
      border: 1.2px dashed rgba(185, 112, 139, 0.34); background: transparent; color: transparent;
      font-size: 12px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center;
      pointer-events: none;
    }
    .todo-check.checked { border-style: solid; border-color: var(--sage); background: rgba(123,148,107,0.12); color: var(--sage); }
    .todo-check.ghost { cursor: default; border-style: dashed; background: transparent; }
    .todo-copy { min-width: 0; }
    .todo-text { font-size: 12px; line-height: 1.3; word-break: break-word; color: var(--ink); }
    .todo-row.todo-done .todo-text { text-decoration: line-through; color: var(--ink-muted); }
    .todo-inputs { display: flex; flex-direction: column; gap: 7px; margin-bottom: 12px; max-height: 173px; overflow-y: auto; }
    .todo-input-row { display: grid; grid-template-columns: 19px 1fr; gap: 7px; align-items: center; }
    .input, .todo-input {
      width: 100%%; border: 0.8px solid rgba(126, 90, 74, 0.13); background: transparent;
      border-radius: 15px 12px 13px 13px / 12px 15px 13px 13px; padding: 9px 11px; font-size: 12px; color: var(--ink); outline: none;
      font-family: inherit;
    }
    .input:focus, .todo-input:focus {
      border-color: rgba(185,112,139,0.36); box-shadow: 0 0 0 2px rgba(217,134,160,0.08);
    }

    /* ── Events (reminders / future) ── */
    .event-list { display: flex; flex-direction: column; gap: 5px; margin-top: 8px; max-height: 253px; overflow-y: auto; padding-right: 1px; }
    .event-row {
      display: grid; grid-template-columns: 60px 1fr 25px;
      gap: 9px; align-items: center;
      padding: 8px 11px; border-radius: 16px 13px 15px 13px / 13px 16px 13px 15px;
      background: transparent;
      border: 0.8px solid rgba(126, 90, 74, 0.07);
    }
    .event-row.future { grid-template-columns: 111px 1fr 23px; }
    .event-row.event-done { opacity: 0.5; }
    .event-time { font-size: 11px; font-weight: 600; color: var(--ink-muted); font-family: var(--font-number); letter-spacing: 0.1px; }
    /* Single-line meta for future rows: "4.25 周六 09:00" */
    .event-meta {
      font-size: 9px;
      font-weight: 500;
      color: var(--ink-muted);
      font-family: var(--font-number);
      letter-spacing: 0.3px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .event-text { font-size: 12px; color: var(--ink); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .event-add {
      display: grid; gap: 7px; margin-bottom: 11px;
      padding: 0; border-radius: 0;
      background: transparent; border: 0;
    }
    .event-add-row { display: flex; gap: 7px; }
    .event-add-row .input { flex: 1; }
    .event-add-row .input.time { width: 81px; flex: 0 0 auto; }
    .event-add-row .input.date { width: 117px; flex: 0 0 auto; font-family: var(--font-number); }

    .empty-state { padding: 20px 11px; border-radius: 16px 13px 15px 13px / 13px 16px 13px 15px; background: transparent; text-align: center; border: 0; }
    .empty-title { font-size: 12px; font-weight: 700; color: var(--ink-muted); }
    .empty-copy { display: none; }
    .icon-btn { appearance: none; border: 0; background: transparent; color: var(--ink-faint); font-size: 15px; cursor: pointer; padding: 1px; }
    .icon-btn:hover { color: var(--rose-deep); }

    /* Minimal "+" add button — circular, translucent, no heavy fill */
    .btn-plus {
      appearance: none; border: 0.8px solid rgba(185,112,139,0.28);
      background: transparent;
      color: var(--rose-deep);
      font-size: 16px; font-weight: 300; line-height: 1;
      width: 28px; height: 28px; border-radius: 50%%;
      cursor: pointer; flex: 0 0 auto; padding: 0;
      display: inline-flex; align-items: center; justify-content: center;
      font-family: inherit;
      transition: all 150ms ease;
    }
    .btn-plus:hover {
      background: var(--rose);
      color: white;
      border-color: var(--rose);
      transform: scale(1.08);
    }

    .section-title { font-size: 11px; font-weight: 700; color: var(--ink-muted); letter-spacing: 0.2px; margin: 9px 1px 7px; font-family: var(--font-hand); }
    .save-row { display: flex; justify-content: flex-end; margin: 2px 0 8px; }
  </style>
</head>
<body>
  <div class="card">
    <img class="panel-skin" src="%s" alt="" />
    <svg class="sketch-overlay" viewBox="0 0 332 520" preserveAspectRatio="none" aria-hidden="true">
      <path d="M21 2 C92 -3 244 0 311 4 C329 12 332 31 329 76 C331 174 330 342 328 496 C318 517 296 520 255 517 C171 519 89 521 23 516 C4 508 2 488 4 448 C1 336 2 178 3 28 C7 13 12 6 21 2" stroke-width="1.3"/>
      <path d="M26 12 C93 8 238 10 304 13 C319 20 322 32 320 71 C321 173 319 334 319 486 C312 505 292 510 254 508 C166 510 88 511 30 506 C15 499 10 484 12 449 C10 342 11 181 12 33 C15 22 19 15 26 12" stroke-width="0.8"/>
      <path class="soft" d="M35 96 C94 89 241 91 294 96 C311 102 314 118 306 132 C246 134 83 134 29 130 C20 117 22 103 35 96" stroke-width="1.1"/>
      <path class="crease" d="M45 54 C86 49 132 53 175 48 C224 43 263 51 305 46" stroke-width="0.55"/>
      <path class="crease" d="M38 236 C82 223 124 232 168 219 C220 204 262 216 307 205" stroke-width="0.55"/>
      <path class="crease" d="M61 462 C109 450 155 462 205 452 C249 443 286 449 315 440" stroke-width="0.5"/>
      <path class="highlight" d="M95 26 C91 98 98 174 92 244 C87 321 94 401 88 493" stroke-width="0.55"/>
      <path class="highlight" d="M236 20 C232 116 243 193 238 289 C235 373 241 440 236 506" stroke-width="0.5"/>
      <circle class="dot" cx="52" cy="446" r="2.2"/>
      <circle class="dot" cx="61" cy="458" r="1.4"/>
      <circle class="dot" cx="284" cy="58" r="1.7"/>
      <path class="soft" d="M40 470 C58 462 70 470 80 482" stroke-width="0.9"/>
      <path class="soft" d="M260 29 C276 23 288 28 298 39" stroke-width="0.9"/>
    </svg>
    <div class="card-header">
      <div class="header-text">
        <div class="header-title">%s</div>
        <div class="header-sub">%s</div>
      </div>
      <button type="button" class="btn-close" onclick="postAction('close_panel')">×</button>
    </div>

    <div class="tab-bar">
      <button type="button" class="tab-pill%s" data-tab="pomodoro">番</button>
      <button type="button" class="tab-pill%s" data-tab="todos">待</button>
      <button type="button" class="tab-pill%s" data-tab="remind">提</button>
      <button type="button" class="tab-pill%s" data-tab="future">未</button>
    </div>

    <div class="content">
      <!-- ============== POMODORO ============== -->
      <div class="tab-panel%s" id="tab-pomodoro">
        <div class="pomo-ring-wrap">
          <div class="pomo-ring"></div>
          <div class="pomo-ring-fg" style="--pct: %d%%;"></div>
          <div class="pomo-center">
            <div class="pomo-status"></div>
            <div class="pomo-time">%s</div>
            <div class="pomo-duration"></div>
          </div>
        </div>
        <div class="pomo-controls">
          <button type="button" class="btn btn-primary" onclick="postAction('%s')">%s</button>
        </div>
      </div>

      <!-- ============== TODOS ============== -->
      <div class="tab-panel%s" id="tab-todos">
        <div class="section-title">%d/%d</div>
        <div class="todo-list">%s</div>
        <div class="save-row">
          <button type="button" class="btn btn-secondary" onclick="saveBatch()">存</button>
        </div>
        <div class="todo-inputs">%s</div>
      </div>

      <!-- ============== TODAY REMIND ============== -->
      <div class="tab-panel%s" id="tab-remind">
        <div class="event-add">
          <input id="remind-text" class="input" type="text" placeholder="做什么" />
          <div class="event-add-row">
            <input id="remind-time" class="input time" type="text" inputmode="numeric" list="quick-times" value="10:00" placeholder="10:00" />
            <button type="button" class="btn-plus" onclick="saveTodayRemind()" title="添加" aria-label="添加">+</button>
          </div>
        </div>
        <datalist id="quick-times">
          <option value="08:00"></option>
          <option value="09:00"></option>
          <option value="12:00"></option>
          <option value="12:30"></option>
          <option value="18:00"></option>
          <option value="22:30"></option>
        </datalist>
        <div class="event-list">%s</div>
      </div>

      <!-- ============== FUTURE ============== -->
      <div class="tab-panel%s" id="tab-future">
        <div class="event-add">
          <input id="future-text" class="input" type="text" placeholder="什么事" />
          <div class="event-add-row">
            <input id="future-date" class="input date" type="text" inputmode="numeric" placeholder="日期 YYYY-MM-DD" />
            <input id="future-time" class="input time" type="text" inputmode="numeric" list="quick-times" value="09:00" placeholder="时间 09:00" />
            <button type="button" class="btn-plus" onclick="saveFutureRemind()" title="添加" aria-label="添加">+</button>
          </div>
        </div>
        <div class="event-list">%s</div>
      </div>
    </div>
  </div>

  <script>
    const actionEndpoint = %q;
    const todayKey = %q;

    async function postAction(action, params) {
      try {
        const r = await fetch(actionEndpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json;charset=UTF-8' },
          body: JSON.stringify({ action, params: params || {} }),
        });
        return r.ok;
      } catch (e) { console.error('panel action failed', e); return false; }
    }
    // Tab switching — optimistic DOM toggle + persist to server so that
    // subsequent refreshPanel() renders come back with the same tab active.
    document.querySelectorAll('.tab-pill').forEach(p => {
      p.addEventListener('click', () => {
        const t = p.dataset.tab;
        document.querySelectorAll('.tab-pill').forEach(x => x.classList.remove('active'));
        p.classList.add('active');
        document.querySelectorAll('.tab-panel').forEach(x => x.classList.remove('active'));
        const pane = document.getElementById('tab-' + t);
        if (pane) pane.classList.add('active');
        postAction('set_tab', { tab: t });   // fire-and-forget
      });
    });
    document.querySelectorAll('.todo-row[data-todo-id]').forEach(row => {
      const toggle = async () => {
        const todoId = row.dataset.todoId;
        if (!todoId || row.dataset.busy === '1') return;
        row.dataset.busy = '1';
        await postAction('toggle', { todo_id: todoId });
      };
      row.addEventListener('click', toggle);
      row.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          toggle();
        }
      });
    });
    async function saveBatch() {
      const items = Array.from(document.querySelectorAll('.todo-input'))
        .map(n => n.value.trim()).filter(Boolean);
      if (!items.length) return;
      const ok = await postAction('add_batch', { items: JSON.stringify(items) });
      if (ok) document.querySelectorAll('.todo-input').forEach(n => { n.value = ''; });
    }
    document.querySelectorAll('.todo-input').forEach(input => {
      input.addEventListener('keydown', event => {
        if (event.key === 'Enter') {
          event.preventDefault();
          saveBatch();
        }
      });
    });
    async function saveTodayRemind() {
      const text = document.getElementById('remind-text').value.trim();
      const time = document.getElementById('remind-time').value.trim();
      if (!text || !time) return;
      const ok = await postAction('add_custom_reminder', { text, date: todayKey, time });
      if (ok) {
        document.getElementById('remind-text').value = '';
        document.getElementById('remind-time').value = '';
      }
    }
    async function saveFutureRemind() {
      const text = document.getElementById('future-text').value.trim();
      const date = document.getElementById('future-date').value.trim();
      const time = document.getElementById('future-time').value.trim();
      if (!text || !date || !time) return;
      const ok = await postAction('add_custom_reminder', { text, date, time });
      if (ok) {
        document.getElementById('future-text').value = '';
        document.getElementById('future-date').value = '';
        document.getElementById('future-time').value = '';
      }
    }
    document.getElementById('remind-text').addEventListener('keydown', e => { if (e.key === 'Enter') saveTodayRemind(); });
    document.getElementById('future-text').addEventListener('keydown', e => { if (e.key === 'Enter') saveFutureRemind(); });
    // Default future-date to "tomorrow in Beijing" so user can just type text & +
    (() => {
      const fd = document.getElementById('future-date');
      if (!fd || fd.value) return;
      // Shift UTC ts by +8h so Intl extracts Beijing wall-clock parts
      const t = new Date(Date.now() + 86400000);
      const p = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Asia/Shanghai', year:'numeric', month:'2-digit', day:'2-digit'
      }).formatToParts(t).reduce((a, x) => { if (x.type !== 'literal') a[x.type] = x.value; return a; }, {});
      fd.value = `${p.year}-${p.month}-${p.day}`;
    })();
  </script>
</body>
</html>
  ]],
    panelSkinUrl,                       -- 1. generated watercolor panel skin
    ownerName,                          -- 2. panel owner/title
    htmlEscape(headerDate),             -- 3. "4月24日 星期四 14:30"
    tabCls("pomodoro"),                 -- 4. tab-pill pomodoro " active"/""
    tabCls("todos"),                    -- 5. tab-pill todos
    tabCls("remind"),                   -- 6. tab-pill remind
    tabCls("future"),                   -- 7. tab-pill future
    tabCls("pomodoro"),                 -- 8. tab-panel pomodoro
    focusPct,                           -- 9. focus progress percent (0-100)
    htmlEscape(focusDisplay),           -- 10. "45:00" or "12:34"
    focusAction,                        -- 11. "start_focus" or "stop_focus"
    htmlEscape(focusButtonLabel),       -- 12. "go" or "stop"
    tabCls("todos"),                    -- 13. tab-panel todos
    countDone(todos),                   -- 14. done count
    #todos,                             -- 15. total todos
    table.concat(todoItems, "\n"),      -- 16. todo rows
    table.concat(inputRows, "\n"),      -- 17. input rows
    tabCls("remind"),                   -- 18. tab-panel remind
    table.concat(todayReminderItems, "\n"),   -- 19. today reminders
    tabCls("future"),                   -- 20. tab-panel future
    table.concat(futureReminderItems, "\n"),  -- 21. future reminders
    actionEndpoint,                     -- 22. action endpoint (%q)
    todayKey                            -- 23. today YYYY-MM-DD (%q, used by JS)
  )
end

function Companion:panelFrame()
  local screen = self.currentScreen or self:preferredScreen()
  local screenFrame = screen:frame()
  local width = config.companion.panel_width
  local height = config.companion.panel_height
  local x = self.anchorFrame.x - width - 18
  local y = self.anchorFrame.y - math.floor((height - self.anchorFrame.h) / 2)

  if x < screenFrame.x + 16 then
    x = screenFrame.x + 16
  end

  if y < screenFrame.y + 16 then
    y = screenFrame.y + 16
  end

  if y + height > screenFrame.y + screenFrame.h - 16 then
    y = screenFrame.y + screenFrame.h - height - 16
  end

  return {x = x, y = y, w = width, h = height}
end

function Companion:hidePanel()
  if self.panel then
    self.panel:hide()
  end
  self.panelVisible = false
end

function Companion:handlePanelAction(action, query)
  -- Track whether this action mutated visible panel data — if yes we call
  -- refreshPanel() at the end so the HTML list (todos, reminders, etc.)
  -- reflects the new state. Without this, Jane clicks "+" but nothing shows up.
  local needsRefresh = false

  if action == "start_focus" then
    self:startFocus(); needsRefresh = true
  elseif action == "stop_focus" then
    self:stopFocus(true); needsRefresh = true
  elseif action == "clear_done" then
    self:clearCompletedTodos(); needsRefresh = true
  elseif action == "toggle" then
    self:toggleTodo(query.todo_id or ""); needsRefresh = true
  elseif action == "add_custom_reminder" then
    local ok, message = self:addCustomReminder(query.text or "", query.date or "", query.time or "")
    hs.alert.show(message, ok and 1.4 or 1.8)
    needsRefresh = true   -- refresh either way (show empty/validation state too)
  elseif action == "remove_custom_reminder" then
    self:removeCustomReminder(query.reminder_id or ""); needsRefresh = true
  elseif action == "add_batch" then
    local items = {}
    local rawItems = query.items or ""
    local ok, decoded = pcall(hs.json.decode, rawItems)
    if ok and type(decoded) == "table" then
      items = decoded
    else
      for line in tostring(rawItems):gmatch("[^\n]+") do
        table.insert(items, line)
      end
    end
    self:addTodosBatch(items); needsRefresh = true
  elseif action == "close_panel" then
    self:hidePanel()
  elseif action == "set_tab" then
    local tab = tostring(query.tab or "")
    if tab == "pomodoro" or tab == "todos" or tab == "remind" or tab == "future" then
      self.state.active_tab = tab
      self:saveState()
      -- No refresh: frontend already toggled the visual class locally.
    end
  end

  if needsRefresh and self.panelVisible then
    self:refreshPanel()
  end

  hs.timer.doAfter(0.05, function()
    self:refreshPanel()
  end)
end

function Companion:panelActionHeaders(extra)
  local headers = {
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Methods"] = "POST, OPTIONS",
    ["Access-Control-Allow-Headers"] = "Content-Type",
    ["Cache-Control"] = "no-store",
  }
  if type(extra) == "table" then
    for key, value in pairs(extra) do
      headers[key] = value
    end
  end
  return headers
end

function Companion:handlePanelActionRequest(method, path, body)
  if method == "OPTIONS" then
    return "", 204, self:panelActionHeaders()
  end

  if path ~= "/companion-action" then
    return "Not found", 404, self:panelActionHeaders({
      ["Content-Type"] = "text/plain; charset=utf-8",
    })
  end

  if method ~= "POST" then
    return hs.json.encode({ok = false, error = "Method not allowed"}) or "{}",
      405,
      self:panelActionHeaders({
        ["Content-Type"] = "application/json; charset=utf-8",
      })
  end

  local ok, payload = pcall(hs.json.decode, body or "")
  if not ok or type(payload) ~= "table" then
    return hs.json.encode({ok = false, error = "Invalid request"}) or "{}",
      400,
      self:panelActionHeaders({
        ["Content-Type"] = "application/json; charset=utf-8",
      })
  end

  local action = tostring(payload.action or "")
  local params = type(payload.params) == "table" and payload.params or {}
  if action == "" then
    return hs.json.encode({ok = false, error = "Missing action"}) or "{}",
      400,
      self:panelActionHeaders({
        ["Content-Type"] = "application/json; charset=utf-8",
      })
  end

  self:handlePanelAction(action, params)
  return hs.json.encode({ok = true}) or "{}",
    200,
    self:panelActionHeaders({
      ["Content-Type"] = "application/json; charset=utf-8",
    })
end

function Companion:startPanelActionServer()
  if self.panelActionServer then
    self.panelActionServer:stop()
    self.panelActionServer = nil
  end

  local server = httpserver.new(false, false)
  server:setInterface("localhost")
  server:setPort(config.companion.panel_action_port)
  server:setCallback(function(method, path, headers, body)
    return self:handlePanelActionRequest(method, path, body)
  end)

  if server:start() then
    self.panelActionServer = server
  else
    log.ef("failed to start panel action server on port %s", tostring(config.companion.panel_action_port))
  end
end

function Companion:ensurePanel()
  local frame = self:panelFrame()

  if self.panel then
    self.panel:frame(frame)
    return
  end

  -- Borderless + transparent → no white titlebar, fully translucent window.
  -- `bringToFront(true)` + `allowTextEntry(true)` maximize the chance that
  -- inputs (and their IME candidate windows) get keyboard focus even though
  -- borderless NSWindows don't become "key" by default on macOS.
  self.panel = hs.webview.new(frame, { developerExtrasEnabled = false })
    :allowTextEntry(true)
    :windowStyle({"borderless"})
    :transparent(true)
    :bringToFront(true)
    :level(hs.drawing.windowLevels.floating)
    :behavior(
      hs.drawing.windowBehaviors.canJoinAllSpaces
      + hs.drawing.windowBehaviors.stationary
      + hs.drawing.windowBehaviors.ignoresCycle
    )
    :windowTitle("PAI Companion")

  self.panel:windowCallback(function(action)
    if action == "closing" then
      self.panelVisible = false
    elseif action == "focusChange" then
      self.panelVisible = self.panel:isVisible()
    end
  end)
end

function Companion:pollPanelActions()
  if not self.panel or not self.panelVisible or self.panelActionInFlight then
    return
  end

  self.panelActionInFlight = true
  self.panel:evaluateJavaScript([[
    (function() {
      if (!window.__paiQueue) { window.__paiQueue = []; }
      const items = window.__paiQueue.splice(0, window.__paiQueue.length);
      return JSON.stringify(items);
    })();
  ]], function(result, errorInfo)
    self.panelActionInFlight = false

    if not result or result == "" then
      return
    end

    local ok, decoded = pcall(hs.json.decode, result)
    if not ok or type(decoded) ~= "table" then
      return
    end

    for _, item in ipairs(decoded) do
      local action = item.action or ""
      local params = item.params or {}
      if action ~= "" then
        self:handlePanelAction(action, params)
      end
    end
  end)
end

function Companion:startPanelActionTimer()
  if self.panelActionTimer then
    self.panelActionTimer:stop()
  end

  self.panelActionTimer = hs.timer.doEvery(0.25, function()
    self:pollPanelActions()
  end)
end

function Companion:refreshPanel()
  if not self.panel then
    return
  end

  self.panel:frame(self:panelFrame())
  self.panel:html(self:renderPanelHtml())
end

function Companion:showControlPanel()
  self:ensurePanel()
  self:refreshPanel()
  self.panel:show()
  pcall(function()
    self.panel:bringToFront(true)
  end)
  self.panelVisible = true
end

function Companion:screenKey(screen)
  if not screen then
    return nil
  end

  local ok, uuid = pcall(function()
    return screen:getUUID()
  end)
  if ok and uuid and uuid ~= "" then
    return uuid
  end

  local okId, identifier = pcall(function()
    return screen:id()
  end)
  if okId and identifier then
    return tostring(identifier)
  end

  return nil
end

function Companion:screenForKey(screenKey)
  if not screenKey then
    return nil
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    if self:screenKey(screen) == screenKey then
      return screen
    end
  end

  return nil
end

function Companion:clampAnchor(frame, screen)
  local bounds = screen:frame()
  local margin = 8
  local width = frame.w or config.companion.width
  local height = frame.h or config.companion.height
  local maxX = bounds.x + bounds.w - width - margin
  local maxY = bounds.y + bounds.h - height - margin

  return {
    x = math.min(math.max(frame.x, bounds.x + margin), maxX),
    y = math.min(math.max(frame.y, bounds.y + margin), maxY),
    w = width,
    h = height,
  }
end

function Companion:storedAnchor()
  local saved = self.state.companion_position
  if type(saved) ~= "table" then
    return nil, nil
  end

  local screen = self:screenForKey(saved.screen_uuid)
  if not screen then
    return nil, nil
  end

  return self:clampAnchor({
    x = tonumber(saved.x) or screen:frame().x,
    y = tonumber(saved.y) or screen:frame().y,
    w = config.companion.width,
    h = config.companion.height,
  }, screen), screen
end

function Companion:rememberAnchor(frame, screen)
  if not frame or not screen then
    return
  end

  self.state.companion_position = {
    x = math.floor(frame.x + 0.5),
    y = math.floor(frame.y + 0.5),
    screen_uuid = self:screenKey(screen),
  }
  self:saveState()
end

function Companion:applyAnchorFrame()
  if self.canvas and self.anchorFrame then
    self.canvas:frame(self.anchorFrame)
  end

  if self.panelVisible then
    self:refreshPanel()
  end

  if self.bubbleCanvas and self.bubbleCanvas:isShowing() then
    self.bubbleCanvas:frame(self:bubbleFrame())
  end
end

function Companion:stopDragTap()
  if self.dragWatchdog then
    self.dragWatchdog:stop()
    self.dragWatchdog = nil
  end
  if self.dragTap then
    pcall(function() self.dragTap:stop() end)
    self.dragTap = nil
  end
  self.dragAnimationState = nil
  self.dragLastMouse = nil
end

function Companion:finishDrag()
  local didDrag = self.didDrag
  self:stopDragTap()

  if didDrag then
    self:rememberAnchor(self.anchorFrame, self.currentScreen or self:preferredScreen())
    self:showBubble(string.format("%s，你简直就是个天才！", config.companion.owner_name or "小耳"), 5)
  else
    self:showControlPanel()
  end
end

function Companion:startDragging()
  self:stopDragTap()

  self.dragStartMouse = hs.mouse.absolutePosition()
  self.dragLastMouse = self.dragStartMouse
  self.dragStartFrame = {
    x = self.anchorFrame.x,
    y = self.anchorFrame.y,
    w = self.anchorFrame.w,
    h = self.anchorFrame.h,
  }
  self.didDrag = false

  self.dragTap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDragged,
    hs.eventtap.event.types.leftMouseUp,
  }, function(event)
    local eventType = event:getType()

    if eventType == hs.eventtap.event.types.leftMouseDragged then
      local mousePos = hs.mouse.absolutePosition()
      local dx = mousePos.x - self.dragStartMouse.x
      local dy = mousePos.y - self.dragStartMouse.y
      local stepDx = mousePos.x - ((self.dragLastMouse and self.dragLastMouse.x) or self.dragStartMouse.x)
      if math.abs(dx) > 4 or math.abs(dy) > 4 then
        self.didDrag = true
      end
      if stepDx > 1 then
        self.dragAnimationState = "running-right"
      elseif stepDx < -1 then
        self.dragAnimationState = "running-left"
      end
      self.dragLastMouse = mousePos

      local screen = hs.mouse.getCurrentScreen() or self.currentScreen or self:preferredScreen()
      local nextFrame = self:clampAnchor({
        x = self.dragStartFrame.x + dx,
        y = self.dragStartFrame.y + dy,
        w = self.dragStartFrame.w,
        h = self.dragStartFrame.h,
      }, screen)
      self.currentScreen = screen
      self.anchorFrame = nextFrame
      self:applyAnchorFrame()
      self:updateVisualState()
    elseif eventType == hs.eventtap.event.types.leftMouseUp then
      self:finishDrag()
    end

    return false
  end)
  self.dragTap:start()

  self.dragWatchdog = hs.timer.doAfter(6, function()
    if self.dragTap then
      log.info("desktop companion drag tap watchdog fired — forcing cleanup")
      self:finishDrag()
    end
  end)
end

function Companion:startFocus()
  local durationSeconds = config.companion.focus_minutes * 60
  self.state.focus_started_at = currentTimestamp()
  self.state.focus_end_at = self.state.focus_started_at + durationSeconds
  self:saveState()
  self:showBubble("开干啦，我 45 分钟后叫你休息。", 6)
  self:startFocusTicker()
  self:updateVisualState()
end

function Companion:stopFocus(silent)
  self.state.focus_end_at = nil
  self.state.focus_started_at = nil
  if self.tempMood == "focus" then
    self.tempMood = nil
    self.tempMoodUntil = nil
  end
  self:saveState()

  if self.focusTimer then
    self.focusTimer:stop()
    self.focusTimer = nil
  end

  if not silent then
    self:setTemporaryMood("failed", 45)
    self:showSpotlightReminder("该休息啦～～", "failed", {requires_ack = true})
  end

  self:updateVisualState()
end

function Companion:startFocusTicker()
  if self.focusTimer then
    self.focusTimer:stop()
  end

  self.focusTimer = hs.timer.doEvery(1, function()
    if self:getFocusRemainingSeconds() <= 0 then
      self:stopFocus(false)
      return
    end
    self:updateVisualState()
  end)
end

function Companion:restoreFocusStateIfNeeded()
  if self:isFocusing() then
    self:startFocusTicker()
  else
    self.state.focus_end_at = nil
    self.state.focus_started_at = nil
    if self.tempMood == "focus" then
      self.tempMood = nil
      self.tempMoodUntil = nil
    end
    self:saveState()
  end
end

function Companion:remind(kind, message)
  self:setTemporaryMood(kind, 120)
  self:updateVisualState()
  self:showSpotlightReminder(message, kind, {requires_ack = true})
end

local function reminderMoodForText(text)
  local normalized = tostring(text or ""):lower()
  if normalized:find("吃饭", 1, true)
      or normalized:find("开饭", 1, true)
      or normalized:find("用餐", 1, true)
      or normalized:find("午饭", 1, true)
      or normalized:find("晚饭", 1, true)
      or normalized:find("早餐", 1, true)
      or normalized:find("干饭", 1, true) then
    return "hungry"
  end

  if normalized:find("喝水", 1, true)
      or normalized:find("饮水", 1, true)
      or normalized:find("补水", 1, true)
      or normalized:find("接水", 1, true)
      or normalized:find("倒水", 1, true)
      or normalized:find("水杯", 1, true) then
    return "thirsty"
  end

  if normalized:find("睡觉", 1, true)
      or normalized:find("睡啦", 1, true)
      or normalized:find("睡了", 1, true)
      or normalized:find("睡眠", 1, true)
      or normalized:find("晚安", 1, true)
      or normalized:find("上床", 1, true) then
    return "sleepy"
  end

  return "idle"
end

function Companion:scheduleChinaDailyReminder(clockText, moodKind, message)
  local hour, minute = tostring(clockText or ""):gsub("：", ":"):match("^(%d%d?)%:(%d%d)$")
  hour = tonumber(hour)
  minute = tonumber(minute)
  if not hour or not minute then
    return
  end

  local function fire()
    self:remind(moodKind, message)
    local nextDelay = math.max(1, nextChinaEpoch(hour, minute) - os.time())
    local nextTimer = hs.timer.doAfter(nextDelay, fire)
    table.insert(self.reminderTimers, nextTimer)
  end

  local delay = math.max(1, nextChinaEpoch(hour, minute) - os.time())
  local timer = hs.timer.doAfter(delay, fire)
  table.insert(self.reminderTimers, timer)
end

function Companion:scheduleIntervalReminder(intervalSeconds, moodKind, message)
  local interval = tonumber(intervalSeconds or 0) or 0
  if interval <= 0 then
    return
  end

  local timer = hs.timer.doEvery(interval, function()
    self:remind(moodKind, message)
  end)
  table.insert(self.reminderTimers, timer)
end

function Companion:setupReminderTimers()
  for _, timer in ipairs(self.reminderTimers) do
    timer:stop()
  end
  self.reminderTimers = {}

  self:scheduleChinaDailyReminder(config.companion.lunch_time, "hungry", "吃饭啦～")
  self:scheduleChinaDailyReminder(config.companion.dinner_time, "hungry", "吃饭啦～")
  self:scheduleChinaDailyReminder(config.companion.sleep_time, "sleepy", "睡觉啦～")
  self:scheduleIntervalReminder(config.companion.hydration_interval_seconds, "thirsty", "喝水啦～")

  local now = currentTimestamp()
  for _, reminder in ipairs(self:getCustomReminders()) do
    if not reminder.triggered_at then
      local targetAt = tonumber(reminder.at or 0) or 0
      local delay = math.max(1, targetAt - now)
      if targetAt <= now then
        delay = 1
      end
      table.insert(self.reminderTimers, hs.timer.doAfter(delay, function()
        local targetReminder = nil
        for _, item in ipairs(self.state.custom_reminders or {}) do
          if item.id == reminder.id then
            targetReminder = item
            break
          end
        end
        if not targetReminder or targetReminder.triggered_at then
          return
        end

        targetReminder.triggered_at = readableNow()
        self:saveState()
        self:remind(reminderMoodForText(targetReminder.text), targetReminder.text)
        if self.panelVisible then
          self:refreshPanel()
        end
      end))
    end
  end
end

function Companion:bubbleFrame()
  local width = 300
  local height = 34
  return {
    x = self.anchorFrame.x + ((self.anchorFrame.w - width) / 2),
    y = self.anchorFrame.y - 38,
    w = width,
    h = height,
  }
end

function Companion:ensureBubbleCanvas()
  if self.bubbleCanvas then
    return
  end

  local canvas = hs.canvas.new(self:bubbleFrame())
  canvas:level("floating")
  canvas:behavior({"canJoinAllSpaces", "stationary", "ignoresCycle"})
  canvas[1] = {
    id = "bubble",
    type = "rectangle",
    action = "fill",
    fillColor = {red = 1, green = 1, blue = 1, alpha = 0},
    strokeColor = {red = 1, green = 1, blue = 1, alpha = 0},
    strokeWidth = 0,
    frame = {x = 0, y = 0, w = 300, h = 34},
    trackMouseDown = false,
  }
  canvas[2] = {
    id = "tail",
    type = "segments",
    action = "fill",
    fillColor = {red = 1, green = 1, blue = 1, alpha = 0},
    strokeColor = {red = 1, green = 1, blue = 1, alpha = 0},
    strokeWidth = 0,
    coordinates = {
      {x = 0, y = 0},
      {x = 0, y = 0},
      {x = 0, y = 0},
    },
    closed = true,
    trackMouseDown = false,
  }
  canvas[3] = {
    id = "text",
    type = "text",
    text = "",
    textAlignment = "center",
    textColor = {red = 0.22, green = 0.16, blue = 0.20, alpha = 0.96},
    textFont = "PingFang SC",
    textSize = 16,
    frame = {x = 0, y = 5, w = 300, h = 24},
    trackMouseDown = true,
  }
  canvas:mouseCallback(function(_, message)
    if message == "mouseDown" then
      self:hideBubble()
    end
  end)
  canvas:hide()
  self.bubbleCanvas = canvas
end

function Companion:hideBubble()
  if self.bubbleHideTimer then
    self.bubbleHideTimer:stop()
    self.bubbleHideTimer = nil
  end
  if self.bubbleCanvas then
    self.bubbleCanvas:hide()
  end
end

function Companion:showBubble(message, duration)
  self:ensureBubbleCanvas()
  self.bubbleCanvas:frame(self:bubbleFrame())
  self.bubbleCanvas.text.text = message
  self.bubbleCanvas:show()

  if self.bubbleHideTimer then
    self.bubbleHideTimer:stop()
  end
  self.bubbleHideTimer = hs.timer.doAfter(duration or config.companion.bubble_duration_seconds, function()
    self:hideBubble()
  end)
end

function Companion:spotlightFrame(screen)
  local target = screen or self.currentScreen or self:preferredScreen()
  local frame = target:frame()
  return {x = frame.x, y = frame.y, w = frame.w, h = frame.h}, target
end

function Companion:ensureSpotlightCanvas(screen)
  local frame, targetScreen = self:spotlightFrame(screen)

  if self.spotlightCanvas then
    self.spotlightCanvas:frame(frame)
    return self.spotlightCanvas, frame, targetScreen
  end

  local canvas = hs.canvas.new(frame)
  canvas:level(hs.drawing.windowLevels.status)
  canvas:behavior(
    hs.drawing.windowBehaviors.canJoinAllSpaces
    + hs.drawing.windowBehaviors.stationary
    + hs.drawing.windowBehaviors.ignoresCycle
  )

  canvas[1] = {
    id = "backdrop",
    type = "rectangle",
    action = "fill",
    fillColor = {red = 1, green = 1, blue = 1, alpha = 0},
    frame = {x = 0, y = 0, w = frame.w, h = frame.h},
    trackMouseDown = true,
  }
  canvas[2] = {
    id = "burst",
    type = "circle",
    action = "stroke",
    strokeColor = {red = 0.93, green = 0.48, blue = 0.67, alpha = 0},
    strokeWidth = 6,
    frame = {x = frame.w / 2 - 40, y = frame.h / 2 - 40, w = 80, h = 80},
    trackMouseDown = true,
  }
  canvas[3] = {
    id = "core",
    type = "circle",
    action = "fill",
    fillColor = {red = 1.0, green = 0.90, blue = 0.94, alpha = 0},
    strokeColor = {red = 0.93, green = 0.48, blue = 0.67, alpha = 0},
    strokeWidth = 4,
    frame = {x = frame.w / 2 - 36, y = frame.h / 2 - 36, w = 72, h = 72},
    trackMouseDown = true,
  }
  canvas[4] = {
    id = "face",
    type = "text",
    text = MOODS.idle.face,
    textAlignment = "center",
    textColor = {white = 0.18, alpha = 0},
    textFont = "PingFang SC",
    textSize = 26,
    frame = {x = frame.w / 2 - 60, y = frame.h / 2 - 18, w = 120, h = 36},
    trackMouseDown = true,
  }
  canvas[5] = {
    id = "message",
    type = "text",
    text = "",
    textAlignment = "center",
    textColor = {white = 0.16, alpha = 0},
    textFont = "PingFang SC",
    textSize = 30,
    frame = {x = 60, y = frame.h / 2 + 70, w = frame.w - 120, h = 52},
    trackMouseDown = true,
  }
  canvas[6] = {
    id = "hint",
    type = "text",
    text = "",
    textAlignment = "center",
    textColor = {white = 0.35, alpha = 0},
    textFont = "PingFang SC",
    textSize = 14,
    frame = {x = 60, y = frame.h / 2 + 122, w = frame.w - 120, h = 28},
    trackMouseDown = true,
  }
  canvas[7] = {
    id = "sprite",
    type = "image",
    image = self:currentImageForMood(),
    imageAlpha = 0,
    frame = {x = frame.w / 2 - 44, y = frame.h / 2 - 44, w = 88, h = 88},
    trackMouseDown = true,
  }

  canvas:mouseCallback(function(_, message)
    if message == "mouseDown" then
      self:hideSpotlightReminder(true)
    end
  end)
  canvas:hide()
  self.spotlightCanvas = canvas
  return canvas, frame, targetScreen
end

function Companion:hideSpotlightReminder(playDismiss)
  if self.spotlightTimer then
    self.spotlightTimer:stop()
    self.spotlightTimer = nil
  end
  if self.spotlightAnimationTimer then
    self.spotlightAnimationTimer:stop()
    self.spotlightAnimationTimer = nil
  end
  for _, timer in ipairs(self.spotlightStepTimers or {}) do
    timer:stop()
  end
  self.spotlightStepTimers = {}
  if self.spotlightHideTimer then
    self.spotlightHideTimer:stop()
    self.spotlightHideTimer = nil
  end
  if self.spotlightCanvas then
    self.spotlightCanvas:hide()
  end
  if self.spotlightCompanionHidden and self.canvas then
    self.canvas:show()
    self.spotlightCompanionHidden = false
  end
  if playDismiss then
    playDismissSound()
  end
end

function Companion:showSpotlightReminder(message, moodName, options)
  options = options or {}
  local requiresAck = options.requires_ack == true
  self:hideBubble()
  self:hideSpotlightReminder()

  local canvas, frame, targetScreen = self:ensureSpotlightCanvas(self.currentScreen or self:preferredScreen())
  local mood = MOODS[moodName or "idle"] or MOODS.idle
  local reminderImage = self:currentImageForMood(moodName)
  local startAnchor = self.anchorFrame or self:anchorFromScreen(targetScreen)
  local startCenterX = (startAnchor.x - frame.x) + (startAnchor.w / 2)
  local startCenterY = (startAnchor.y - frame.y) + (startAnchor.h / 2)
  local centerX = frame.w / 2
  local centerY = frame.h / 2 - 24
  local messageWidth = math.min(frame.w - 120, 540)
  local messageX = (frame.w - messageWidth) / 2
  local usingSprite = reminderImage ~= nil
  local messageY = usingSprite and (centerY + 114) or (centerY + 72)
  local hintY = usingSprite and (centerY - 126) or (centerY + 118)
  local startSprite = {w = 92, h = 92}
  local centerSprite = {w = 168, h = 168}
  local burstSprite = {w = 188, h = 188}

  local function setCircle(cx, cy, radius, fillAlpha, strokeAlpha, faceAlpha, burstRadius, burstAlpha)
    canvas.core.frame = {x = cx - radius, y = cy - radius, w = radius * 2, h = radius * 2}
    canvas.core.fillColor = {red = mood.bg.red, green = mood.bg.green, blue = mood.bg.blue, alpha = fillAlpha}
    canvas.core.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = strokeAlpha}
    canvas.face.frame = {x = cx - radius, y = cy - 18, w = radius * 2, h = 36}
    canvas.face.textColor = {white = 0.16, alpha = faceAlpha}
    canvas.burst.frame = {x = cx - burstRadius, y = cy - burstRadius, w = burstRadius * 2, h = burstRadius * 2}
    canvas.burst.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = burstAlpha}
  end

  canvas.backdrop.fillColor = {red = 1, green = 1, blue = 1, alpha = 0}
  canvas.face.text = mood.face
  canvas.message.text = message
  canvas.message.textSize = 22
  canvas.message.frame = {x = messageX, y = messageY, w = messageWidth, h = 44}
  canvas.hint.frame = {x = messageX, y = hintY, w = messageWidth, h = 24}
  canvas.hint.text = requiresAck and "点一下我知道了" or ""
  canvas.message.textColor = {white = 0.16, alpha = 0}
  canvas.hint.textColor = {white = 0.35, alpha = 0}
  canvas.sprite.image = reminderImage
  canvas.sprite.imageAlpha = usingSprite and 1 or 0
  canvas.sprite.frame = {
    x = startCenterX - (startSprite.w / 2),
    y = startCenterY - (startSprite.h / 2),
    w = startSprite.w,
    h = startSprite.h,
  }
  if usingSprite then
    canvas.core.fillColor = {red = 0, green = 0, blue = 0, alpha = 0}
    canvas.core.strokeColor = {red = 0, green = 0, blue = 0, alpha = 0}
    canvas.face.textColor = {white = 0, alpha = 0}
    canvas.burst.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = 0}
    canvas.burst.frame = {x = centerX - 28, y = centerY - 28, w = 56, h = 56}
    if self.canvas and self.canvas:isShowing() then
      self.canvas:hide()
      self.spotlightCompanionHidden = true
    end
  else
    setCircle(startCenterX, startCenterY, 24, 0.96, 0.85, 1, 30, 0)
  end
  canvas:show()

  if usingSprite then
    self.spotlightAnimationTimer = hs.timer.doEvery(self.animationFrameInterval or 0.18, function()
      if self.spotlightCanvas and self.spotlightCanvas:isShowing() then
        self.spotlightCanvas.sprite.image = self:currentImageForMood(moodName)
      end
    end)
  end

  local steps = {
    {delay = 0.10, fn = function()
      canvas.backdrop.fillColor = {red = 1, green = 1, blue = 1, alpha = 0.03}
      if usingSprite then
        canvas.sprite.frame = {
          x = centerX - (centerSprite.w / 2),
          y = centerY - (centerSprite.h / 2),
          w = centerSprite.w,
          h = centerSprite.h,
        }
        canvas.burst.frame = {x = centerX - 64, y = centerY - 64, w = 128, h = 128}
        canvas.burst.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = 0.18}
      else
        setCircle(centerX, centerY, 42, 0.94, 0.82, 1, 48, 0.10)
      end
    end},
    {delay = 0.24, fn = function()
      playReminderSound()
      canvas.backdrop.fillColor = {red = 1, green = 1, blue = 1, alpha = 0.05}
      if usingSprite then
        canvas.sprite.frame = {
          x = centerX - (burstSprite.w / 2),
          y = centerY - (burstSprite.h / 2),
          w = burstSprite.w,
          h = burstSprite.h,
        }
        canvas.burst.frame = {x = centerX - 106, y = centerY - 106, w = 212, h = 212}
        canvas.burst.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = 0.48}
      else
        setCircle(centerX, centerY, 18, 0.22, 0.18, 0.12, 128, 0.62)
      end
      canvas.message.textColor = {white = 0.16, alpha = 0.92}
    end},
    {delay = 0.42, fn = function()
      canvas.backdrop.fillColor = {red = 1, green = 1, blue = 1, alpha = 0.04}
      if usingSprite then
        canvas.sprite.imageAlpha = 0.98
        canvas.sprite.frame = {
          x = centerX - (centerSprite.w / 2),
          y = centerY - (centerSprite.h / 2),
          w = centerSprite.w,
          h = centerSprite.h,
        }
        canvas.burst.frame = {x = centerX - 156, y = centerY - 156, w = 312, h = 312}
        canvas.burst.strokeColor = {red = mood.accent.red, green = mood.accent.green, blue = mood.accent.blue, alpha = 0}
      else
        setCircle(centerX, centerY, 10, 0, 0, 0, 188, 0)
      end
      canvas.message.textColor = {white = 0.16, alpha = 1}
      if requiresAck then
        canvas.hint.textColor = {white = 0.35, alpha = 0.92}
      end
    end},
  }

  self.spotlightStepTimers = {}
  for _, step in ipairs(steps) do
    table.insert(self.spotlightStepTimers, hs.timer.doAfter(step.delay, step.fn))
  end

  if requiresAck then
    self.spotlightHideTimer = nil
  else
    self.spotlightHideTimer = hs.timer.doAfter(2.1, function()
      self:hideSpotlightReminder()
    end)
  end
end

function Companion:nudgeMessage()
  return nil
end

function Companion:setupNudgeTimer()
  if self.nudgeTimer then
    self.nudgeTimer:stop()
  end

  if self.initialNudgeTimer then
    self.initialNudgeTimer:stop()
    self.initialNudgeTimer = nil
  end
end

function Companion:preferredScreen()
  return hs.mouse.getCurrentScreen()
    or (hs.window.frontmostWindow() and hs.window.frontmostWindow():screen())
    or hs.screen.mainScreen()
end

function Companion:anchorFromScreen(screen)
  local targetScreen = screen or self:preferredScreen()
  local frame = targetScreen:frame()
  return self:clampAnchor({
    x = frame.x + frame.w - config.companion.width - config.companion.margin_right,
    y = frame.y + frame.h - config.companion.height - config.companion.margin_bottom,
    w = config.companion.width,
    h = config.companion.height,
  }, targetScreen)
end

function Companion:buildCanvas()
  local storedFrame, storedScreen = self:storedAnchor()
  if storedFrame and storedScreen then
    self.currentScreen = storedScreen
    self.anchorFrame = storedFrame
  else
    self.currentScreen = self:preferredScreen()
    self.anchorFrame = self:anchorFromScreen(self.currentScreen)
  end

  local canvas = hs.canvas.new(self.anchorFrame)
  canvas:level("floating")
  canvas:behavior({"canJoinAllSpaces", "stationary", "ignoresCycle"})
  -- All element coordinates below assume the original 140×192 coordinate system.
  -- When config.companion.width/height are overridden (e.g. 210×288) via
  -- local_config.json, scale the whole canvas coordinate space so every frame,
  -- font size, and shape grows proportionally — avoids having to rewrite
  -- hundreds of hardcoded x/y/w/h values.
  do
    local scaleX = config.companion.width / 140
    local scaleY = config.companion.height / 192
    canvas:transformation(hs.canvas.matrix.scale(scaleX, scaleY))
  end

  local catHead = {
    {x = 44, y = 74},
    {x = 50, y = 52},
    {x = 62, y = 64},
    {x = 78, y = 58},
    {x = 90, y = 52},
    {x = 96, y = 74},
    {x = 108, y = 84},
    {x = 112, y = 108},
    {x = 104, y = 128},
    {x = 86, y = 142},
    {x = 54, y = 142},
    {x = 36, y = 128},
    {x = 28, y = 108},
    {x = 32, y = 84},
  }

  canvas[1] = {
    id = "shadow",
    type = "segments",
    action = "fill",
    fillColor = MOODS.idle.shadow,
    coordinates = shiftedCoordinates(catHead, 0, 8),
    closed = true,
    trackMouseDown = true,
  }

  canvas[2] = {
    id = "body",
    type = "segments",
    action = "fill",
    fillColor = MOODS.idle.bg,
    strokeColor = MOODS.idle.accent,
    strokeWidth = 4,
    coordinates = catHead,
    closed = true,
    trackMouseDown = true,
  }

  canvas[3] = {
    id = "leftEarInner",
    type = "segments",
    action = "fill",
    fillColor = {red = 0.98, green = 0.78, blue = 0.84, alpha = 0.82},
    coordinates = {
      {x = 49, y = 71},
      {x = 53, y = 58},
      {x = 61, y = 66},
    },
    closed = true,
    trackMouseDown = true,
  }

  canvas[4] = {
    id = "rightEarInner",
    type = "segments",
    action = "fill",
    fillColor = {red = 0.98, green = 0.78, blue = 0.84, alpha = 0.82},
    coordinates = {
      {x = 79, y = 66},
      {x = 87, y = 58},
      {x = 91, y = 71},
    },
    trackMouseDown = true,
  }

  if self:usesImageCompanion() then
    canvas[5] = {
      id = "face",
      type = "image",
      image = self:currentImageForMood(),
      imageAlpha = 1,
      frame = {x = 4, y = 40, w = 132, h = 118},
      trackMouseDown = true,
    }

    for index = 6, 10 do
      canvas[index] = {
        id = "imageSpacer" .. tostring(index),
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0, green = 0, blue = 0, alpha = 0},
        frame = {x = 0, y = 0, w = 1, h = 1},
        trackMouseDown = true,
      }
    end
  else
    canvas[5] = {
      id = "leftEye",
      type = "circle",
      action = "fill",
      fillColor = {red = 0.40, green = 0.30, blue = 0.34, alpha = 0.86},
      frame = {x = 46, y = 90, w = 8, h = 12},
      trackMouseDown = true,
    }

    canvas[6] = {
      id = "rightEye",
      type = "circle",
      action = "fill",
      fillColor = {red = 0.40, green = 0.30, blue = 0.34, alpha = 0.86},
      frame = {x = 86, y = 90, w = 8, h = 12},
      trackMouseDown = true,
    }

    canvas[7] = {
      id = "nose",
      type = "segments",
      action = "fill",
      fillColor = {red = 0.97, green = 0.62, blue = 0.72, alpha = 0.95},
      coordinates = {
        {x = 64, y = 106},
        {x = 70, y = 112},
        {x = 76, y = 106},
      },
      closed = true,
      trackMouseDown = true,
    }

    canvas[8] = {
      id = "mouth",
      type = "text",
      text = "︶",
      textAlignment = "center",
      textColor = {red = 0.56, green = 0.42, blue = 0.46, alpha = 0.70},
      textFont = "PingFang SC",
      textSize = 14,
      frame = {x = 60, y = 111, w = 20, h = 14},
      trackMouseDown = true,
    }

    canvas[9] = {
      id = "whiskersLeft",
      type = "segments",
      action = "stroke",
      strokeColor = {red = 0.72, green = 0.60, blue = 0.64, alpha = 0.75},
      strokeWidth = 1.3,
      coordinates = {
        {x = 60, y = 107},
        {x = 40, y = 101},
        {x = 60, y = 111},
        {x = 38, y = 111},
        {x = 60, y = 115},
        {x = 42, y = 121},
      },
      trackMouseDown = true,
    }

    canvas[10] = {
      id = "whiskersRight",
      type = "segments",
      action = "stroke",
      strokeColor = {red = 0.72, green = 0.60, blue = 0.64, alpha = 0.75},
      strokeWidth = 1.3,
      coordinates = {
        {x = 80, y = 107},
        {x = 100, y = 101},
        {x = 80, y = 111},
        {x = 102, y = 111},
        {x = 80, y = 115},
        {x = 98, y = 121},
      },
      trackMouseDown = true,
    }
  end

  canvas[11] = {
    id = "halo",
    type = "segments",
    action = "stroke",
    strokeColor = MOODS.idle.accent,
    strokeWidth = 2,
    coordinates = shiftedCoordinates(catHead, 0, -2),
    closed = true,
    alpha = 0.45,
    trackMouseDown = true,
  }

  canvas[12] = {
    id = "status",
    type = "text",
    text = self:statusText(),
    textAlignment = "center",
    textColor = {white = 0.2, alpha = 1},
    textFont = "PingFang SC",
    textSize = 7,
    textLineBreak = "truncateTail",
    frame = self:usesImageCompanion() and {x = 6, y = 162, w = 128, h = 16} or {x = 6, y = 156, w = 128, h = 16},
    trackMouseDown = true,
  }

  canvas[13] = {
    id = "hint",
    type = "text",
    text = "",
    textAlignment = "center",
    textColor = {white = 0.36, alpha = 0},
    textFont = "PingFang SC",
    textSize = 12,
    frame = {x = 10, y = 166, w = 120, h = 18},
    trackMouseDown = true,
  }

  canvas[14] = {
    id = "headTimeBg",
    type = "rectangle",
    action = "fill",
    fillColor = {red = 1.0, green = 1.0, blue = 1.0, alpha = 0.88},
    strokeColor = {red = 0.95, green = 0.75, blue = 0.83, alpha = 0.75},
    strokeWidth = 1.2,
    roundedRectRadii = {xRadius = 8, yRadius = 8},
    frame = {x = 18, y = 18, w = 104, h = 20},
    trackMouseDown = true,
  }

  -- Single-line head clock: "4月24日 星期四 14:30"
  -- Bg pushed down closer to the body/sprite (y=18-38, body starts at y=40).
  canvas[15] = {
    id = "headTime",
    type = "text",
    text = todayPanelLabel() .. " " .. chinaDateString("%H:%M"),
    textAlignment = "center",
    textColor = {red = 0.22, green = 0.16, blue = 0.22, alpha = 1},
    textFont = "PingFang SC",
    textSize = 8,
    frame = {x = 18, y = 21, w = 104, h = 14},
    trackMouseDown = true,
  }

  -- Legacy second line kept as an empty/transparent node so downstream code
  -- that references self.canvas.headDate (in updateVisualState, etc.) still works.
  canvas[16] = {
    id = "headDate",
    type = "text",
    text = "",
    textAlignment = "center",
    textColor = {red = 0, green = 0, blue = 0, alpha = 0},
    textFont = "PingFang SC",
    textSize = 1,
    frame = {x = 8, y = 36, w = 124, h = 1},
    trackMouseDown = false,
  }

  canvas:mouseCallback(function(_, message)
    if message == "mouseDown" then
      self:startDragging()
    end
  end)
  canvas:show()

  self.canvas = canvas
  self:updateVisualState()
end

function Companion:updateVisualState()
  if not self.canvas then
    return
  end

  if not self:isFocusing() and self.tempMood == "focus" then
    self.tempMood = nil
    self.tempMoodUntil = nil
  end

  local moodName = self:currentMoodName()
  local mood = MOODS[moodName] or MOODS.idle
  local imageMoodName = self.dragAnimationState or moodName
  local currentImage = self:currentImageForMood(imageMoodName)

  if currentImage then
    self.canvas.shadow.fillColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.body.fillColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.body.strokeColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.halo.strokeColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.leftEarInner.fillColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.rightEarInner.fillColor = {red = 0, green = 0, blue = 0, alpha = 0}
    self.canvas.face.image = currentImage
    self.canvas.face.imageAlpha = 1
    self.image = currentImage
  else
    self.canvas.shadow.fillColor = mood.shadow
    self.canvas.body.fillColor = mood.bg
    self.canvas.body.strokeColor = mood.accent
    self.canvas.halo.strokeColor = mood.accent
    self.canvas.leftEarInner.fillColor = {
      red = math.min(1, mood.accent.red + 0.12),
      green = math.min(1, mood.accent.green + 0.10),
      blue = math.min(1, mood.accent.blue + 0.12),
      alpha = 0.42,
    }
    self.canvas.rightEarInner.fillColor = {
      red = math.min(1, mood.accent.red + 0.12),
      green = math.min(1, mood.accent.green + 0.10),
      blue = math.min(1, mood.accent.blue + 0.12),
      alpha = 0.44,
    }
    self.canvas.leftEye.fillColor = {
      red = math.max(0.28, mood.accent.red * 0.55),
      green = math.max(0.22, mood.accent.green * 0.48),
      blue = math.max(0.24, mood.accent.blue * 0.50),
      alpha = 0.88,
    }
    self.canvas.rightEye.fillColor = self.canvas.leftEye.fillColor
    self.canvas.nose.fillColor = {
      red = math.min(1, mood.accent.red + 0.16),
      green = math.min(1, mood.accent.green + 0.12),
      blue = math.min(1, mood.accent.blue + 0.16),
      alpha = 0.92,
    }
    self.canvas.mouth.textColor = {
      red = math.max(0.42, mood.accent.red * 0.72),
      green = math.max(0.34, mood.accent.green * 0.62),
      blue = math.max(0.38, mood.accent.blue * 0.64),
      alpha = 0.68,
    }
    local whiskerColor = {
      red = math.min(1, mood.bg.red - 0.18),
      green = math.min(1, mood.bg.green - 0.20),
      blue = math.min(1, mood.bg.blue - 0.18),
      alpha = 0.70,
    }
    self.canvas.whiskersLeft.strokeColor = whiskerColor
    self.canvas.whiskersRight.strokeColor = whiskerColor
    self.image = nil
  end
  self.canvas.status.text = self:statusText()
  self.canvas.hint.text = ""

  if self.canvas.headTime then
    -- Single-line: "4月24日 星期四 14:30"
    self.canvas.headTime.text = todayPanelLabel() .. " " .. chinaDateString("%H:%M")
  end
  if self.canvas.headDate then
    -- No longer displayed (merged into headTime); keep node transparent.
    self.canvas.headDate.text = ""
  end
end

function Companion:startAnimation()
  if self.animationTimer then
    self.animationTimer:stop()
  end

  self.animationTimer = hs.timer.doEvery(config.companion.animation_interval_seconds, function()
    if not self.canvas or not self.anchorFrame then
      return
    end

    if not self.state.companion_position then
      local preferredScreen = self:preferredScreen()
      if preferredScreen and preferredScreen ~= self.currentScreen then
        self.currentScreen = preferredScreen
        self.anchorFrame = self:anchorFromScreen(self.currentScreen)
        if self.panelVisible then
          self:refreshPanel()
        end
      end
    end

    self.phase = self.phase + 1
    if self.dragTap then
      self.canvas:frame(self.anchorFrame)
      self:updateVisualState()
      return
    end

    local mood = self:currentMoodName()
    local amplitudeX = 0
    local amplitudeY = 2.5

    if mood == "focus" then
      amplitudeY = 1.2
      amplitudeX = 1.5
    elseif mood == "break" or mood == "hungry" or mood == "thirsty" or mood == "sleepy" then
      amplitudeY = 4.0
      amplitudeX = 4.0
    end

    local offsetX = math.sin(self.phase * 0.7) * amplitudeX
    local offsetY = math.sin(self.phase) * amplitudeY
    self.canvas:frame({
      x = self.anchorFrame.x + offsetX,
      y = self.anchorFrame.y + offsetY,
      w = self.anchorFrame.w,
      h = self.anchorFrame.h,
    })

    if self.bubbleCanvas and self.bubbleCanvas:isShowing() then
      self.bubbleCanvas:frame(self:bubbleFrame())
    end

    self:updateVisualState()
  end)
end

function Companion:syncExternalStateIfNeeded()
  local mtime = fileModificationTime(self.statePath)
  if not mtime then
    return
  end

  if self.lastStateMtime and mtime <= self.lastStateMtime then
    return
  end

  self:loadState()
  self:setupReminderTimers()
  self:updateVisualState()
  if self.panelVisible then
    self:refreshPanel()
  end
  log.info("desktop companion synced external state")
end

function Companion:startStateSyncTimer()
  if self.stateSyncTimer then
    self.stateSyncTimer:stop()
  end

  self.stateSyncTimer = hs.timer.doEvery(2, function()
    self:syncExternalStateIfNeeded()
  end)
end

function Companion:setupScreenWatcher()
  self.screenWatcher = hs.screen.watcher.new(function()
    if self.state.companion_position then
      local storedFrame, storedScreen = self:storedAnchor()
      if storedFrame and storedScreen then
        self.currentScreen = storedScreen
        self.anchorFrame = storedFrame
      else
        self.state.companion_position = nil
        self.currentScreen = self:preferredScreen()
        self.anchorFrame = self:anchorFromScreen(self.currentScreen)
        self:saveState()
      end
    else
      self.currentScreen = self:preferredScreen()
      self.anchorFrame = self:anchorFromScreen(self.currentScreen)
    end
    self:applyAnchorFrame()
  end)
  self.screenWatcher:start()
end

function Companion:setupDayRolloverTimer()
  if self.dayRolloverTimer then
    self.dayRolloverTimer:stop()
    self.dayRolloverTimer = nil
  end

  local function schedule()
    local delay = math.max(1, nextChinaEpoch(0, 0) - os.time())
    self.dayRolloverTimer = hs.timer.doAfter(delay, function()
      self:pruneTodos()
      self:updateVisualState()
      if self.panelVisible then
        self:refreshPanel()
      end
      schedule()
    end)
  end

  schedule()
end

function Companion:start()
  self:buildCanvas()
  self:setupReminderTimers()
  self:setupDayRolloverTimer()
  self:startPanelActionServer()
  self:startStateSyncTimer()
  self:restoreFocusStateIfNeeded()
  self:startAnimation()
  self:setupScreenWatcher()
  self:setupNudgeTimer()
  self.panelHotkey = hs.hotkey.bind(
    config.hotkeys.companion_panel[1],
    config.hotkeys.companion_panel[2],
    function()
      self:showControlPanel()
    end
  )
  log.info("desktop companion started")
end

function Companion:stop()
  if self.animationTimer then
    self.animationTimer:stop()
    self.animationTimer = nil
  end

  if self.focusTimer then
    self.focusTimer:stop()
    self.focusTimer = nil
  end

  if self.nudgeTimer then
    self.nudgeTimer:stop()
    self.nudgeTimer = nil
  end

  if self.initialNudgeTimer then
    self.initialNudgeTimer:stop()
    self.initialNudgeTimer = nil
  end

  if self.dayRolloverTimer then
    self.dayRolloverTimer:stop()
    self.dayRolloverTimer = nil
  end

  if self.panelActionTimer then
    self.panelActionTimer:stop()
    self.panelActionTimer = nil
  end

  if self.panelActionServer then
    self.panelActionServer:stop()
    self.panelActionServer = nil
  end

  if self.stateSyncTimer then
    self.stateSyncTimer:stop()
    self.stateSyncTimer = nil
  end

  for _, timer in ipairs(self.reminderTimers) do
    timer:stop()
  end
  self.reminderTimers = {}

  if self.screenWatcher then
    self.screenWatcher:stop()
    self.screenWatcher = nil
  end

  if self.panelHotkey then
    self.panelHotkey:delete()
    self.panelHotkey = nil
  end

  self:stopDragTap()

  if self.canvas then
    self.canvas:delete()
    self.canvas = nil
  end

  if self.panel then
    self.panel:delete()
    self.panel = nil
  end

  self:hideSpotlightReminder()
  if self.spotlightCanvas then
    self.spotlightCanvas:delete()
    self.spotlightCanvas = nil
  end

  if self.bubbleCanvas then
    self.bubbleCanvas:delete()
    self.bubbleCanvas = nil
  end
end

function M.start()
  if not config.companion.enabled then
    return nil
  end

  math.randomseed(currentTimestamp())

  if _G.__paiDesktopCompanion and _G.__paiDesktopCompanion.stop then
    pcall(function()
      _G.__paiDesktopCompanion:stop()
    end)
  end

  local instance = Companion.new()
  instance:start()
  _G.__paiDesktopCompanion = instance
  return instance
end

return M

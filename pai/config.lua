local home = os.getenv("HOME")
local localConfigPath = home .. "/.hammerspoon/pai/local_config.json"

local config = {}

local function loadLocalConfig()
  local attributes = hs.fs.attributes(localConfigPath)
  if not attributes then
    return {}
  end

  local file = io.open(localConfigPath, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(hs.json.decode, content)
  if ok and data then
    return data
  end

  return {}
end

local localConfig = loadLocalConfig()

local function nonEmpty(value, fallback)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return fallback
end

config.gemini = {
  api_key = hs.settings.get("pai_gemini_api_key") or os.getenv("GEMINI_API_KEY") or "",
  model = "gemini-2.5-flash",
}

config.openrouter = {
  api_key = localConfig.openrouter_api_key or os.getenv("OPENROUTER_API_KEY") or "",
  base_url = localConfig.openrouter_base_url or "https://openrouter.ai/api/v1/chat/completions",
  model = localConfig.openrouter_model or "openai/gpt-4o-mini",
}

config.hotkeys = {
  voice_toggle = {{"alt"}, "q"},
  voice_agent_toggle = {{"alt"}, "a"},
  translate_toggle = {{"alt"}, "t"},
  output_latest = {{"alt"}, "w"},
  companion_panel = {{"ctrl", "alt"}, "p"},
}

config.capture = {
  release_delay = 0.12,
  selection_delay = 0.25,
}

config.output = {
  paste_delay_seconds = 0.18,
  keep_result_in_clipboard = true,
}

config.audio = {
  ffmpeg_path = "/opt/homebrew/bin/ffmpeg",
  input_device = "1",
  channels = 1,
  sample_rate = 16000,
  stop_grace_seconds = 0.8,
  temp_dir = home .. "/.hammerspoon/pai/tmp",
  temp_retention_days = 7,
  recorder_log = "/tmp/pai-voice-recorder.log",
  transcribe_script = home .. "/.hammerspoon/pai/helpers/transcribe_gemini.py",
}

config.agent = {
  bridge_url = "http://127.0.0.1:9876",
  bridge_server_script = home .. "/.hammerspoon/pai/bridge/server.py",
  bridge_log = "/tmp/pai-agent-bridge.log",
  start_wait_seconds = 0.8,
  session_memory_path = home .. "/.hammerspoon/pai/session_memory.json",
  drafts_dir = home .. "/Downloads",
  draft_editor_app = "/Applications/ColaMD.app",
  reveal_in_finder = true,
}

config.companion = {
  enabled = true,
  state_path = home .. "/.hammerspoon/pai/companion_state.json",
  panel_action_port = 8766,
  width = localConfig.companion_width or 140,
  height = localConfig.companion_height or 192,
  margin_right = 28,
  margin_bottom = 28,
  owner_name = nonEmpty(localConfig.companion_owner_name, "小耳"),
  lunch_time = localConfig.companion_lunch_time or "12:30",
  dinner_time = localConfig.companion_dinner_time or "18:00",
  sleep_time = localConfig.companion_sleep_time or "22:30",
  hydration_interval_seconds = localConfig.companion_hydration_interval_seconds or 3600,
  focus_minutes = 45,
  animation_interval_seconds = localConfig.companion_animation_interval_seconds or 0.35,
  animation_frame_interval_seconds = localConfig.companion_animation_frame_interval_seconds or 0.18,
  nudge_interval_seconds = 300,
  bubble_duration_seconds = 8,
  panel_width = localConfig.companion_panel_width or 299,
  panel_height = localConfig.companion_panel_height or 469,
  companion_image_path = localConfig.companion_image_path or (home .. "/.hammerspoon/pai/assets/companion/cat.png"),
  -- Optional idle rotation pool — array of image paths. When set,
  -- currentImageForMood cycles through them every 5 minutes on a stable
  -- time-slot boundary (no per-frame flicker).
  companion_idle_image_paths = localConfig.companion_idle_image_paths or nil,
  companion_focus_image_path = localConfig.companion_focus_image_path or (home .. "/.hammerspoon/pai/assets/companion/cat-focus.png"),
  companion_break_image_path = localConfig.companion_break_image_path or (home .. "/.hammerspoon/pai/assets/companion/cat-break.png"),
  companion_hungry_image_path = localConfig.companion_hungry_image_path or (home .. "/.hammerspoon/pai/assets/companion/cat-hungry.png"),
  companion_sleepy_image_path = localConfig.companion_sleepy_image_path or (home .. "/.hammerspoon/pai/assets/companion/cat-sleepy.png"),
  companion_animation_root = localConfig.companion_animation_root or nil,
  companion_animation_mood_map = localConfig.companion_animation_mood_map or nil,
  companion_idle_animation_cycle_states = localConfig.companion_idle_animation_cycle_states or nil,
  companion_idle_animation_cycle_seconds = localConfig.companion_idle_animation_cycle_seconds or 600,
}

config.prompts = {
  task = [[
You are PAI, a macOS writing operator.
The user provides:
1. The selected text from the screen
2. A spoken instruction describing what to do with that text

Carry out the spoken instruction on the selected text.

Rules:
- Return only the final text.
- Do not explain what you changed.
- Do not add markdown fences, labels, or quotation marks unless the instruction explicitly asks for them.
- Preserve names, facts, numbers, URLs, and formatting when possible.
- If the instruction asks for translation, output only the translation.
- If the instruction asks for a reply, output only the reply text.
- If the instruction asks for a summary, output only the summary.
]],
  translate_to_english = [[
Translate the following text into natural, fluent English.
Rules:
- Output only the English translation.
- Preserve names, numbers, URLs, and formatting.
- Do not explain or add notes.
]],
  translate_to_chinese = [[
Translate the following text into natural, fluent simplified Chinese.
Rules:
- Output only the Chinese translation.
- Preserve names, numbers, URLs, and formatting.
- Do not explain or add notes.
]],
}

config.paths = {
  local_config = localConfigPath,
}

return config

#!/usr/bin/env -S wayrun --lua-host
-- Window switcher for KDE, niri and Hyprland: one entry point and keyword, as
-- the built-in `w` search used to be. The compositor is chosen at runtime.

local ID = "windows"

local common = wayrun.import("windows/common")
local BACKENDS = {
  wayrun.import("windows/niri"),
  wayrun.import("windows/hyprland"),
  wayrun.import("windows/kde"),
}

local function detect_by_env()
  local desktop = (wayrun.env("XDG_CURRENT_DESKTOP") or ""):lower()
  if desktop ~= "" then
    for _, backend in ipairs(BACKENDS) do
      if desktop:find(backend.desktop, 1, true) then
        return backend
      end
    end
  end
  for _, backend in ipairs(BACKENDS) do
    if backend.socket_env and wayrun.env(backend.socket_env) then
      return backend
    end
  end
  return nil
end

-- A resident launcher may carry no compositor environment, so fall back to
-- whichever backend answers first.
local function detect_by_probe()
  for _, backend in ipairs(BACKENDS) do
    if wayrun.which(backend.tool) then
      local list = backend.list()
      if list then
        return backend, list
      end
    end
  end
  return nil
end

local function select()
  local backend = detect_by_env()
  if backend then
    return backend, backend.list()
  end
  return detect_by_probe()
end

local function search(text)
  local backend, list = select()
  if not backend then
    return common.hint(
      common.t("No window backend found", "未找到可用的窗口后端"),
      common.t("Run WayRun under KDE, niri or Hyprland", "请在 KDE、niri 或 Hyprland 会话中使用")
    )
  end
  if not wayrun.which(backend.tool) then
    return common.hint(
      common.t(backend.tool .. " not found", "未找到 " .. backend.tool .. " 命令"),
      common.t("Install it or run WayRun inside " .. backend.name, "请安装，或在 " .. backend.name .. " 会话中使用")
    )
  end
  if not list then
    return common.hint(
      common.t(backend.name .. " is unreachable", backend.name .. " 无法连接"),
      common.t("Does `" .. backend.tool .. "` work in this session?", "当前会话中 `" .. backend.tool .. "` 可用吗？")
    )
  end
  return common.rows(text or "", list, ID)
end

return {
  {
    id = ID,
    name = "Windows",
    icon = wayrun.icon("preferences-system-windows"),
    description = "Switch between open windows (KDE, niri, Hyprland)",
    api = 1,
    exec = { "busctl", "niri", "hyprctl" },
    env = { "XDG_CURRENT_DESKTOP", "NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE" },
    search = search,
    top = function() return search("") end,
    command = function(action, payload)
      if action ~= "focus" or type(payload) ~= "table" or type(payload.id) ~= "string" then
        return
      end
      local backend = detect_by_env()
      if backend and backend.focus(payload.id) then
        common.remember(payload.id)
        return
      end
      for _, candidate in ipairs(BACKENDS) do
        if candidate ~= backend and candidate.focus(payload.id) then
          common.remember(payload.id)
          return
        end
      end
    end,
  },
}

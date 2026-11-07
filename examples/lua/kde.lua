#!/usr/bin/env -S wayrun --lua-host
-- KDE System Settings search.
--
-- Plasma has no single index of settings. System Settings is a collection of
-- KCM modules, and every installed settings page ships a desktop file:
--
--   <data dir>/applications/kcm_*.desktop
--
-- Each file carries the localized name, icon and the command that opens the
-- module (`systemsettings kcm_*`; a few use `kcmshell6 kcm_*` for a standalone
-- window). Plasma 5 installed the same files under kservices5/. The reader
-- lives in kde/modules.lua.
--
-- Descriptions are not in the desktop files; the module list is the only
-- public source (`kcmshell6 --list`), read lazily by kde/describe.lua. If it
-- cannot run, the plugin still lists and opens modules by name.
--
-- The command line can open a module, not scroll to one control inside it, so
-- a row opens the page that owns the setting -- the same limit the DMS plugin
-- has with its IPC.

local util = wayrun.import("kde/util")
local modules = wayrun.import("kde/modules")
local describe = wayrun.import("kde/describe")
local match = wayrun.import("kde/match")

local settings_icon = wayrun.icon("preferences-system")
local copy_icon = wayrun.icon("papirus:edit-copy")

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local MAX_RESULTS = 15
local MAX_TOP = 50
local MAX_TITLE = 120
local MAX_SUMMARY = 200
local MAX_DESCRIPTION = 160


local function row_of(module)
  local description = util.cut(describe.get(module.id), MAX_DESCRIPTION)
  local summary = description ~= "" and description or t("System Settings page", "系统设置页面")

  local actions = {
    {
      title = t("Copy module id", "复制模块 ID"),
      id = "copy_id",
      action = { type = "copy", text = module.id },
      icon = copy_icon,
    },
  }
  local root = modules.settings_root()
  if root then
    actions[#actions + 1] = {
      title = t("Open all settings", "打开全部设置"),
      id = "open_settings",
      action = { type = "run", cmd = root },
      icon = settings_icon,
    }
  end

  return {
    title = util.cut(module.name, MAX_TITLE),
    summary = util.cut(summary, MAX_SUMMARY),
    icon = (module.icon and wayrun.icon(module.icon)) or settings_icon,
    on_click = module.command and { type = "run", cmd = module.command }
      or { type = "run", cmd = "systemsettings" },
    actions = actions,
  }
end

local function hint()
  return {
    {
      title = t("KDE settings not found", "未找到 KDE 设置"),
      summary = t(
        "Install Plasma System Settings to browse its pages",
        "安装 Plasma 系统设置后即可浏览设置页面"
      ),
      icon = settings_icon,
    },
  }
end


local function search(text)
  local list = modules.all()
  if #list == 0 then
    return hint()
  end

  local query = util.one_line(text):lower()
  if query == "" then
    local rows = {}
    for index = 1, math.min(#list, MAX_TOP) do
      rows[#rows + 1] = row_of(list[index])
    end
    return rows
  end

  -- All localized names are considered for a non-ASCII query; otherwise the
  -- display, English and session names cover the common case without making
  -- two-letter queries match every language in the desktop files.
  local hits = match.rank(list, query, describe.get, util.has_non_ascii(query))
  local rows = {}
  for index = 1, math.min(#hits, MAX_RESULTS) do
    rows[#rows + 1] = row_of(hits[index].module)
  end
  return rows
end

return {
  {
    id = "kde-settings",
    name = t("KDE Settings", "KDE 设置"),
    icon = settings_icon,
    description = t(
      "Search Plasma System Settings and open their page",
      "搜索 Plasma 系统设置项并打开对应页面"
    ),
    api = 1,
    exec = { "systemsettings", "kcmshell6", "kcmshell5" },
    env = {
      "XDG_DATA_HOME",
      "XDG_DATA_DIRS",
      "XDG_SESSION_TYPE",
      "WAYLAND_DISPLAY",
      "DISPLAY",
      "LC_ALL",
      "LC_MESSAGES",
      "LANG",
    },
    -- KCM desktop files live in the XDG data dirs (applications/ on Plasma 6,
    -- kservices5/ on Plasma 5).
    read = {
      "~/.local/share/applications",
      "~/.local/share/kservices5",
      "~/.local/share/kservices6",
      "/usr/local/share/applications",
      "/usr/local/share/kservices5",
      "/usr/local/share/kservices6",
      "/usr/share/applications",
      "/usr/share/kservices5",
      "/usr/share/kservices6",
    },
    search = search,
    top = function() return search("") end,
  },
}

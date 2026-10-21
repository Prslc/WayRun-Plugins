#!/usr/bin/env -S wayrun --lua-host
-- Wallpaper picker over DankMaterialShell's `wallpaper` IPC.
-- Point DIR and the read area at your wallpaper folder.

local home = wayrun.home() or ""
local DIR = home .. "/Pictures/Wallpapers"
local EXT = { png = true, jpg = true, jpeg = true, webp = true, gif = true, bmp = true }

local function quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function list(text)
  local query = text and text:lower() or ""
  local current = nil
  local out = wayrun.exec("dms", { "ipc", "call", "wallpaper", "get" })
  if out and out.code == 0 then
    current = out.stdout:gsub("%s+$", "")
  end
  local items = {}
  for _, name in ipairs(wayrun.fs.list(DIR) or {}) do
    local ext = name:match("%.([^.]+)$")
    ext = ext and ext:lower()
    if ext and EXT[ext] and (query == "" or name:lower():find(query, 1, true)) then
      local path = DIR .. "/" .. name
      local stat = wayrun.fs.stat(path)
      if stat then
        items[#items + 1] = { name = name, path = path, mtime = stat.mtime_ns }
      end
    end
  end
  table.sort(items, function(a, b) return a.mtime > b.mtime end)

  local rows = {}
  for index, item in ipairs(items) do
    if index > 10 then
      break
    end
    rows[#rows + 1] = {
      title = item.name,
      summary = (item.path == current and "Current · " or "") .. item.path,
      preview = { type = "image", path = item.path },
      on_click = { type = "run", cmd = "dms ipc call wallpaper set " .. quote(item.path) },
      actions = {
        { title = "Copy path", id = "copy_path", action = { type = "copy", text = item.path } },
        { title = "Reveal", id = "reveal", action = { type = "reveal", uri = wayrun.file_uri(item.path) } },
      },
    }
  end
  return rows
end

return {
  {
    id = "wallpaper",
    name = "Wallpaper",
    icon = wayrun.icon("preferences-desktop-wallpaper"),
    description = "Switch the DMS wallpaper",
    api = 1,
    exec = { "dms" },
    read = { "~/Pictures/Wallpapers" },
    search = function(text) return list(text) end,
    top = function() return list("") end,
  },
}

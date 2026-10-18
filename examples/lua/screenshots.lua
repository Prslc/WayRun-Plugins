#!/usr/bin/env -S wayrun --lua-host
-- Recent screenshots with image previews and the usual file actions.
-- Point DIR and the read area at your screenshot folder.

local home = wayrun.home() or ""
local DIR = home .. "/Pictures/Screenshots"
local EXT = { png = true, jpg = true, jpeg = true, webp = true, gif = true, svg = true, bmp = true }

local function file_uri(path)
  return "file://" .. path:gsub("[^%w%-%._~/]", function(c)
    return string.format("%%%02X", c:byte())
  end)
end

local function recent(text)
  local query = text and text:lower() or ""
  local items = {}
  for _, name in ipairs(wayrun.fs.list(DIR) or {}) do
    local ext = name:match("%.([^.]+)$")
    ext = ext and ext:lower()
    if ext and EXT[ext] and (query == "" or name:lower():find(query, 1, true)) then
      local path = DIR .. "/" .. name
      local stat = wayrun.fs.stat(path)
      if stat then
        items[#items + 1] = { name = name, path = path, mtime = stat.mtime_ns, size = stat.size }
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
      summary = item.path,
      preview = { type = "image", path = item.path },
      on_click = { type = "open", uri = file_uri(item.path) },
      actions = {
        { title = "Copy path", id = "copy_path", action = { type = "copy", text = item.path } },
        { title = "Reveal", id = "reveal", action = { type = "reveal", uri = file_uri(item.path) } },
      },
    }
  end
  return rows
end

return {
  {
    id = "screenshots",
    name = "Screenshots",
    icon = wayrun.icon("image-x-generic"),
    description = "Recent screenshots",
    api = 1,
    read = { "~/Pictures/Screenshots" },
    search = function(text) return recent(text) end,
    top = function() return recent("") end,
  },
}

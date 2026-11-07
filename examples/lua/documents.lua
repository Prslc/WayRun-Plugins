#!/usr/bin/env -S wayrun --lua-host
-- Text and Markdown notes with a plain-text preview of their opening lines.

local DIR = (wayrun.script_dir() or "") .. "/documents"
local EXT = { txt = true, md = true }
local MAX_PREVIEW = 4096

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local function excerpt(text)
  if #text <= MAX_PREVIEW then
    return text
  end
  local cut = MAX_PREVIEW
  while cut > 0 do
    local byte = text:byte(cut + 1)
    if not byte or byte < 0x80 or byte >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return text:sub(1, cut) .. "…"
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
    if index > 8 then
      break
    end
    local body = nil
    if item.size <= 512 * 1024 then
      local text = wayrun.fs.read(item.path)
      if text then
        body = excerpt(text)
      end
    end
    rows[#rows + 1] = {
      title = item.name,
      summary = item.path,
      preview = (body and body ~= "") and { type = "text", text = body } or nil,
      on_click = { type = "open", uri = wayrun.file_uri(item.path) },
      actions = {
        { title = t("Copy path", "复制路径"), id = "copy_path", action = { type = "copy", text = item.path } },
        { title = t("Reveal", "在文件管理器中显示"), id = "reveal", action = { type = "reveal", uri = wayrun.file_uri(item.path) } },
      },
    }
  end
  return rows
end

return {
  {
    id = "documents",
    name = t("Documents", "笔记"),
    icon = wayrun.icon("text-x-generic"),
    description = t("Text and Markdown notes", "文本与 Markdown 笔记"),
    api = 1,
    search = function(text) return recent(text) end,
    top = function() return recent("") end,
  },
}

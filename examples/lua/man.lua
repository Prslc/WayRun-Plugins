#!/usr/bin/env -S wayrun --lua-host

local locale = wayrun.locale and wayrun.locale() or "en"
local zh = locale:match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local icon = wayrun.icon("papirus:app.devsuite.Manuals")
  or wayrun.icon("papirus:deepin-manual")
  or wayrun.icon("papirus:utilities-terminal")

local function sh(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function parse(stdout)
  local entries = {}
  for line in stdout:gmatch("[^\n]+") do
    local name, section, summary = line:match("^(%S+)%s+%(([^%)]+)%)%s+%-%s+(.*)$")
    if name then
      entries[#entries + 1] = { name = name, section = section, summary = summary }
    end
  end
  return entries
end

local function score(entry, query)
  local name = entry.name:lower()
  if name == query then
    return 3
  end
  if name:sub(1, #query) == query then
    return 2
  end
  return 1
end

local function search(text)
  if not text or text:match("^%s*$") then
    return {}
  end

  local ok, res = pcall(wayrun.exec, "apropos", { "-l", "--", text })
  if not ok then
    return {
      {
        title = t("Man search failed", "man 搜索失败"),
        summary = tostring(res)
      }
    }
  end
  if not res or res.code ~= 0 then
    return {}
  end

  local entries = parse(res.stdout)
  local query = text:lower()
  table.sort(entries, function(a, b)
    local sa, sb = score(a, query), score(b, query)
    if sa ~= sb then
      return sa > sb
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.section < b.section
  end)

  local rows = {}
  for i = 1, math.min(#entries, 8) do
    local entry = entries[i]
    rows[i] = {
      title = entry.name,
      summary = "(" .. entry.section .. ") " .. entry.summary,
      on_click = {
        type = "run_in_terminal",
        cmd = "man " .. sh(entry.section) .. " " .. sh(entry.name)
      }
    }
  end
  return rows
end

return {
  {
    id = "man",
    name = t("Man Pages", "Man 手册"),
    icon = icon,
    description = t("Search local man pages", "搜索本地 man 手册"),
    api = 1,
    exec = { "apropos" },
    top = function()
      return {
        {
          title = t("Search man pages", "搜索 man 手册"),
          summary = t(
            "Type a keyword; Enter opens the page in a terminal",
            "输入关键词，Enter 在终端中打开"
          )
        }
      }
    end,
    search = search
  }
}

#!/usr/bin/env -S wayrun --lua-host
-- Package search across the configured pacman repositories and the AUR.

local locale = wayrun.locale and wayrun.locale() or "en"
local zh = locale:match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local repo_icon = wayrun.icon("papirus:distributor-logo-archlinux")
local aur_icon = wayrun.icon("papirus:deepin-app-store")
local copy_icon = wayrun.script_dir() .. "/assets/copy_icon.svg"

local AUR_RPC = "https://aur.archlinux.org/rpc/"
local AUR_PACKAGE = "https://aur.archlinux.org/packages/"
local ARCH_PACKAGE = "https://archlinux.org/packages/"

local PER_SOURCE = 6
local AUR_TTL = 600
local AUR_TIMEOUT_MS = 1400

local OFFICIAL = {
  core = true,
  extra = true,
  multilib = true,
  ["core-testing"] = true,
  ["extra-testing"] = true,
  ["multilib-testing"] = true,
  ["core-staging"] = true,
  ["extra-staging"] = true,
  ["multilib-staging"] = true,
}

local AUR_MODES = { a = true, aur = true }
local REPO_MODES = { p = true, pkg = true, repo = true, pacman = true }

local helper = wayrun.which("paru") and "paru" or (wayrun.which("yay") and "yay" or nil)

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function text_of(value)
  return type(value) == "string" and value or ""
end

-- pacman treats the pattern as a regular expression.
local function literal(text)
  return (text:gsub("[%^%$%.%[%]%(%)%{%}%*%+%?%|\\]", "\\%0"))
end

---@class PacmanEntry
---@field repo string
---@field name string
---@field version string
---@field flags string
---@field desc string
---@field installed boolean

---@param title string
---@param summary string?
---@return WayrunRow
local function hint_row(title, summary)
  return { title = title, summary = summary }
end

---@param text string
---@return PacmanEntry[] entries, boolean truncated
local function pacman_entries(text)
  local ok, res = pcall(wayrun.exec, "pacman", { "-Ss", "--", literal(text) })
  if not ok then
    wayrun.log("pacman search failed: " .. tostring(res))
    return {}, false
  end
  if not res then
    return {}, false
  end
  if res.stderr_truncated then
    wayrun.log("pacman stderr truncated")
  end
  local truncated = res.stdout_truncated == true
  if res.code ~= 0 then
    return {}, truncated
  end

  local entries, current = {}, nil
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local repo, name, version, flags = line:match("^(%S+)/(%S+)%s+(%S+)%s*(.*)$")
    if repo then
      current = { repo = repo, name = name, version = version, flags = flags, desc = "" }
      entries[#entries + 1] = current
    elseif current then
      local desc = line:match("^%s+(.+)$")
      if desc then
        current.desc = current.desc == "" and desc or (current.desc .. " " .. desc)
      end
    end
  end

  for _, entry in ipairs(entries) do
    entry.desc = trim(entry.desc)
    entry.installed = entry.flags:find("[installed", 1, true) ~= nil
  end
  return entries, truncated
end

local function aur_params(text)
  return { v = 5, type = "search", arg = text, by = "name-desc" }
end

---@class AurEntry
---@field name string
---@field version string
---@field desc string
---@field votes integer
---@field popularity number
---@field out_of_date boolean
---@field maintainer string
---@field url string
---@field base string
---@field submitted integer
---@field modified integer

---@param body string
---@return AurEntry[]
local function aur_entries_from(body)
  local ok, data = pcall(wayrun.json.decode, body)
  if not ok or type(data) ~= "table" or type(data.results) ~= "table" then
    return {}
  end

  local entries = {}
  for _, item in ipairs(data.results) do
    local name = text_of(item.Name)
    if name ~= "" then
      entries[#entries + 1] = {
        name = name,
        version = text_of(item.Version),
        desc = trim(text_of(item.Description):gsub("%s+", " ")),
        votes = type(item.NumVotes) == "number" and item.NumVotes or 0,
        popularity = type(item.Popularity) == "number" and item.Popularity or 0,
        out_of_date = type(item.OutOfDate) == "number",
        maintainer = text_of(item.Maintainer),
        url = text_of(item.URL),
        base = text_of(item.PackageBase),
        submitted = type(item.FirstSubmitted) == "number" and math.floor(item.FirstSubmitted) or 0,
        modified = type(item.LastModified) == "number" and math.floor(item.LastModified) or 0,
      }
    end
  end
  return entries
end

-- Returns nil when the request fails, so stale rows can stand in for it;
-- an empty table is a successful search with no matches.
local function aur_entries(text)
  local ok, res = pcall(wayrun.http.get, AUR_RPC, aur_params(text), {
    ttl = AUR_TTL,
    timeout_ms = AUR_TIMEOUT_MS,
  })
  if not ok then
    wayrun.log("AUR search failed: " .. (tostring(res):match("^[^\n]*") or ""))
    return nil
  end
  if not res or res.status ~= 200 or not res.body then
    return nil
  end
  return aur_entries_from(res.body)
end

local function cached_aur_entries(text)
  local ok, res = pcall(wayrun.http.cached, AUR_RPC, aur_params(text))
  if not ok or not res or not res.body then
    return {}
  end
  return aur_entries_from(res.body)
end

local function score(name, query)
  local lower = name:lower()
  if lower == query then
    return 3
  end
  if lower:sub(1, #query) == query then
    return 2
  end
  if lower:find(query, 1, true) then
    return 1
  end
  return 0
end

---@param entry PacmanEntry|AurEntry
---@param aur boolean
---@return string
local function install_command(entry, aur)
  if not aur then
    return "sudo pacman -S --needed " .. entry.name
  end
  if helper then
    return helper .. " -S " .. entry.name
  end
  return "git clone https://aur.archlinux.org/" .. entry.name .. ".git && cd "
    .. entry.name .. " && makepkg -si"
end

---@param entry PacmanEntry|AurEntry
---@param aur boolean
---@return WayrunActionItem
local function install_action(entry, aur)
  return {
    title = t("Copy install command", "复制安装命令"),
    id = "copy_install",
    action = { type = "copy", text = install_command(entry, aur) },
    icon = copy_icon,
  }
end

---@param entry PacmanEntry
---@return string?
local function repo_page(entry)
  if OFFICIAL[entry.repo] then
    return ARCH_PACKAGE .. entry.repo .. "/x86_64/" .. wayrun.urlencode(entry.name) .. "/"
  end
  if entry.repo == "archlinuxcn" then
    return "https://github.com/archlinuxcn/repo/tree/master/archlinuxcn/"
      .. wayrun.urlencode(entry.name)
  end
  return nil
end

---@param text string
---@return string
local function md_escape(text)
  return (text:gsub("([\\`*_%[%]%(%)<>#!|~&])", "\\%1"))
end

---@param label string
---@param value string
---@return string
local function field(label, value)
  return label .. (zh and "：" or ": ") .. value
end

-- AUR timestamps are Unix seconds; use the launcher's UTC civil fields, with
-- day-count arithmetic as the fallback on a launcher that predates them.
---@param timestamp integer
---@return string
local function date_of(timestamp)
  if wayrun.date then
    local date = wayrun.date(timestamp)
    return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
  end
  local z = timestamp // 86400 + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then
    y = y + 1
  end
  return string.format("%04d-%02d-%02d", y, m, d)
end

---@param lines string[]
---@return WayrunPreview
local function markdown_preview(lines)
  return { type = "text", format = "markdown", text = table.concat(lines, "\n") }
end

---@param entry PacmanEntry
---@param page string?
---@return WayrunPreview
local function pacman_preview(entry, page)
  local meta = { entry.repo, entry.version }
  if entry.installed then
    meta[#meta + 1] = t("installed", "已安装")
  end
  local lines = { "## " .. entry.name, "", table.concat(meta, " · ") }
  if entry.desc ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = md_escape(entry.desc)
  end
  lines[#lines + 1] = ""
  if page then
    lines[#lines + 1] = field(t("Docs", "文档"), md_escape(page))
  else
    lines[#lines + 1] = t("Enter copies the install command", "Enter 复制安装命令")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "```"
  lines[#lines + 1] = install_command(entry, false)
  lines[#lines + 1] = "```"
  return markdown_preview(lines)
end

---@param entry AurEntry
---@return WayrunPreview
local function aur_preview(entry)
  local meta = { "AUR", entry.version }
  if entry.votes > 0 then
    meta[#meta + 1] = "★ " .. entry.votes
  end
  if entry.out_of_date then
    meta[#meta + 1] = t("out of date", "已过期")
  end
  local lines = { "## " .. entry.name, "", table.concat(meta, " · ") }
  if entry.desc ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = md_escape(entry.desc)
  end
  lines[#lines + 1] = ""

  local fields = {
    field(t("Maintainer", "维护者"),
      entry.maintainer ~= "" and md_escape(entry.maintainer) or t("orphan", "无")),
    field(t("Popularity", "热度"), string.format("%.2f", entry.popularity)),
  }
  if entry.submitted > 0 then
    fields[#fields + 1] = field(t("Submitted", "首次提交"), date_of(entry.submitted))
  end
  if entry.modified > 0 then
    fields[#fields + 1] = field(t("Last modified", "最后更新"), date_of(entry.modified))
  end
  if entry.base ~= "" and entry.base ~= entry.name then
    fields[#fields + 1] = field(t("Package base", "基础包"), md_escape(entry.base))
  end
  if entry.url ~= "" then
    fields[#fields + 1] = field(t("Upstream", "上游"), md_escape(entry.url))
  end
  fields[#fields + 1] = field("AUR", md_escape(AUR_PACKAGE .. wayrun.urlencode(entry.name)))
  lines[#lines + 1] = table.concat(fields, "  \n")
  lines[#lines + 1] = ""
  lines[#lines + 1] = "```"
  lines[#lines + 1] = install_command(entry, true)
  lines[#lines + 1] = "```"
  return markdown_preview(lines)
end

---@param entry PacmanEntry
---@return WayrunRow
local function pacman_row(entry)
  local parts = { entry.repo, entry.version }
  if entry.installed then
    parts[#parts + 1] = t("installed", "已安装")
  end

  local summary = table.concat(parts, " · ")
  local page = repo_page(entry)
  if not page then
    summary = t("Enter copies the install command · ", "Enter 复制安装命令 · ") .. summary
  end

  return {
    title = entry.name,
    summary = summary,
    icon = repo_icon,
    preview = pacman_preview(entry, page),
    on_click = page and { type = "open", uri = page }
      or { type = "copy", text = install_command(entry, false) },
    actions = { install_action(entry, false) },
  }
end

---@param entry AurEntry
---@return WayrunRow
local function aur_row(entry)
  local parts = { "AUR", entry.version }
  if entry.votes > 0 then
    parts[#parts + 1] = "★ " .. entry.votes
  end
  if entry.out_of_date then
    parts[#parts + 1] = t("out of date", "已过期")
  end

  return {
    title = entry.name,
    summary = table.concat(parts, " · "),
    icon = aur_icon,
    preview = aur_preview(entry),
    on_click = { type = "open", uri = AUR_PACKAGE .. wayrun.urlencode(entry.name) },
    actions = { install_action(entry, true) },
  }
end

---@param text string
---@return WayrunRow[] rows, boolean truncated
local function pacman_rows(text)
  local entries, truncated = pacman_entries(text)
  local query = text:lower()
  table.sort(entries, function(a, b)
    local sa, sb = score(a.name, query), score(b.name, query)
    if sa ~= sb then
      return sa > sb
    end
    if a.installed ~= b.installed then
      return a.installed
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.repo < b.repo
  end)

  local out = {}
  for i = 1, math.min(#entries, PER_SOURCE) do
    out[#out + 1] = pacman_row(entries[i])
  end
  return out, truncated
end

---@param entries AurEntry[]?
---@param query string
---@return WayrunRow[]
local function aur_rows(entries, query)
  entries = entries or {}
  table.sort(entries, function(a, b)
    local sa, sb = score(a.name, query), score(b.name, query)
    if sa ~= sb then
      return sa > sb
    end
    if a.popularity ~= b.popularity then
      return a.popularity > b.popularity
    end
    if a.votes ~= b.votes then
      return a.votes > b.votes
    end
    return a.name < b.name
  end)

  local out = {}
  for i = 1, math.min(#entries, PER_SOURCE) do
    out[#out + 1] = aur_row(entries[i])
  end
  return out
end

---@param first WayrunRow[]
---@param second WayrunRow[]
---@return WayrunRow[]
local function merge_rows(first, second)
  local out, seen = {}, {}
  for _, group in ipairs({ first, second }) do
    for _, row in ipairs(group) do
      local key = row.title:lower()
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = row
      end
    end
  end
  return out
end

---@param text string
---@return WayrunRow[]
local function no_results(text)
  return { hint_row(t("No packages found", "未找到软件包"), text) }
end

---@return WayrunRow
local function truncated_row()
  return hint_row(
    t("Results truncated", "结果被截断"),
    t("Narrow the query to see every pacman match", "缩小关键词以查看全部 pacman 结果")
  )
end

---@param text string
---@param emit fun(rows: WayrunRow[])?
---@return WayrunRow[]
local function search_aur(text, emit)
  local stale = aur_rows(cached_aur_entries(text), text:lower())
  if emit and #stale > 0 then
    emit(stale)
  end

  local fresh = aur_entries(text)
  local rows = fresh and aur_rows(fresh, text:lower()) or stale
  if #rows == 0 then
    return no_results(text)
  end
  return rows
end

---@param text string
---@return WayrunRow[]
local function search_repo(text)
  local rows, truncated = pacman_rows(text)
  if truncated then
    rows[#rows + 1] = truncated_row()
  end
  if #rows == 0 then
    return no_results(text)
  end
  return rows
end

---@param text string
---@param emit fun(rows: WayrunRow[])?
---@return WayrunRow[]
local function search_both(text, emit)
  if #text < 2 then
    return search_repo(text)
  end

  local repos, truncated = pacman_rows(text)
  local stale = aur_rows(cached_aur_entries(text), text:lower())
  if emit then
    local preview = merge_rows(repos, stale)
    if truncated then
      preview[#preview + 1] = truncated_row()
    end
    if #preview > 0 then
      emit(preview)
    end
  end

  local fresh = aur_entries(text)
  local rows = merge_rows(repos, fresh and aur_rows(fresh, text:lower()) or stale)
  if truncated then
    rows[#rows + 1] = truncated_row()
  end
  if #rows == 0 then
    return no_results(text)
  end
  return rows
end

---@return WayrunRow[]
local function aur_mode_hint()
  return {
    hint_row(
      t("Search the AUR", "搜索 AUR"),
      t("a / aur <keywords>", "a / aur <关键词>")
    ),
  }
end

---@return WayrunRow[]
local function repo_mode_hint()
  return {
    hint_row(
      t("Search pacman repositories", "搜索 pacman 仓库"),
      t("p / repo <keywords> — official and third-party repos",
        "p / repo <关键词> — 官方与第三方仓库")
    ),
  }
end

---@param text string
---@param emit fun(rows: WayrunRow[])?
---@return WayrunRow[]
local function search(text, emit)
  text = trim(text)
  if text == "" then
    return {}
  end

  local first, rest = text:match("^(%S+)%s+(.*)$")
  local mode = (first or text):lower()
  rest = rest and trim(rest) or ""

  if AUR_MODES[mode] then
    if rest == "" then
      return aur_mode_hint()
    end
    return search_aur(rest, emit)
  end

  if REPO_MODES[mode] then
    if rest == "" then
      return repo_mode_hint()
    end
    return search_repo(rest)
  end

  return search_both(text, emit)
end

---@return WayrunRow[]
local function top()
  return {
    hint_row(
      t("Search pacman repositories", "搜索 pacman 仓库"),
      t("p / repo <keywords> — official and third-party repos",
        "p / repo <关键词> — 官方与第三方仓库")
    ),
    hint_row(
      t("Search the AUR", "搜索 AUR"),
      t("a / aur <keywords>", "a / aur <关键词>")
    ),
    hint_row(
      t("Search both", "同时搜索两者"),
      t("Type keywords directly", "直接输入关键词")
    ),
  }
end

---@type WayrunPlugin[]
local plugins = {
  {
    id = "arch-packages",
    name = t("Arch Packages", "Arch 软件包"),
    icon = repo_icon,
    description = t("Search pacman repositories and the AUR",
      "搜索 pacman 仓库与 AUR"),
    api = 1,
    exec = { "pacman" },
    top = top,
    search = search,
  },
}

return plugins

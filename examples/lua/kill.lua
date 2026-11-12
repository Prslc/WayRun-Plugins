#!/usr/bin/env -S wayrun --lua-host
-- Process list comes from ps; signals go through exec's argv. The launcher's
-- app list adds application names and icons, and the empty query lists only
-- those apps. Selection and execution are separated by one RPC, so /proc
-- starttime is rechecked to make sure the PID was not reused.

local locale = wayrun.locale and wayrun.locale() or "en"
local zh = locale:match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local ICON = wayrun.icon("papirus:utilities-system-monitor")
local GENERIC_ICON = wayrun.icon("papirus:application-x-executable")
local PS_TTL = 1
local APPS_TTL = 300
local MAX_ROWS = 50

-- Killing one of these ends the session; the launcher's own host is also the
-- process answering the search. Prefix-matched, so a truncated comm counts.
local PROTECTED = { "wayrun" }
local session = (wayrun.desktop and wayrun.desktop()) or ""
if session == "kde" then
  PROTECTED = { "wayrun", "kwin_wayland", "kwin_x11", "plasmashell", "startplasma" }
elseif session == "niri" then
  PROTECTED = { "wayrun", "niri" }
elseif session == "hyprland" then
  PROTECTED = { "wayrun", "hyprland" }
elseif session == "sway" then
  PROTECTED = { "wayrun", "sway" }
elseif session == "wayfire" then
  PROTECTED = { "wayrun", "wayfire" }
end

local function protected(comm)
  comm = comm:lower()
  for _, name in ipairs(PROTECTED) do
    if comm:sub(1, #name) == name then return true end
  end
  return false
end

local function build_apps()
  local apps = {}
  local function add(key, app)
    key = key and key:lower()
    if key and key ~= "" and not apps[key] then
      apps[key] = { name = app.name, icon = app.icon or GENERIC_ICON }
    end
  end
  for _, app in ipairs(wayrun.apps()) do
    local stem = app.id:gsub("%.desktop$", "")
    local keys = { stem }
    if app.exec then table.insert(keys, 1, app.exec) end
    for _, key in ipairs(keys) do
      add(key, app)
      -- A flatpak or reverse-DNS id names the app; its tail is the comm.
      add(key:match("%.([^.]+)$"), app)
      -- The kernel truncates comm to 15 bytes, and the lookup is by comm.
      add(key:sub(1, 15), app)
    end
  end
  return apps
end

-- The host is resident, so the map lives in this process; kv carries it across
-- a reaped host, so a cold spawn does not pay the launcher's app scan again.
local apps_cache, apps_at

local function desktop_apps()
  -- A launcher that predates wayrun.apps still lists processes, unnamed.
  if not wayrun.apps then return {} end
  local now = wayrun.time()
  if apps_cache and now - apps_at < APPS_TTL then return apps_cache end
  local cached = wayrun.kv.get("apps")
  if cached then
    local saved = wayrun.json.decode(cached)
    if type(saved) == "table" and saved.at and saved.apps and now - saved.at < APPS_TTL then
      apps_cache, apps_at = saved.apps, saved.at
      return apps_cache
    end
  end
  apps_cache, apps_at = build_apps(), now
  wayrun.kv.set("apps", wayrun.json.encode({ at = now, apps = apps_cache }), APPS_TTL)
  return apps_cache
end

local function start_time(pid)
  local ok, stat = pcall(wayrun.fs.read, "/proc/" .. pid .. "/stat")
  if not ok or not stat then return nil end
  -- comm may contain spaces and parentheses, so count fields after the last
  -- ')' instead; starttime is field 22, i.e. the 20th token after state.
  local rest = stat:match("^.*%)%s(.*)$")
  if not rest then return nil end
  local index = 0
  for field in rest:gmatch("%S+") do
    index = index + 1
    if index == 20 then return field end
  end
end

local uid_cache

local function user_id()
  if uid_cache then return uid_cache end
  local ok, res = pcall(wayrun.exec, "id", { "-u" })
  if not ok then return nil end
  uid_cache = res.stdout:match("^%s*(%d+)")
  return uid_cache
end

local ps_cache, ps_at

local function processes()
  local now = wayrun.time()
  if ps_cache and now - ps_at < PS_TTL then return ps_cache end

  local uid = user_id()
  if not uid then
    return nil, t("Cannot determine the current user", "无法确定当前用户")
  end

  local ok, res = pcall(wayrun.exec, "ps",
    { "-u", uid, "-o", "pid=,ppid=,pcpu=,pmem=,comm=", "--sort=-pcpu" })
  if not ok then return nil, tostring(res) end

  local list = {}
  for line in res.stdout:gmatch("[^\n]+") do
    -- comm can contain spaces (Electron helpers), so keep it last and take
    -- the rest of the line.
    local pid, ppid, cpu, mem, comm =
      line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(.-)%s*$")
    if pid then
      list[#list + 1] = { pid = pid, ppid = ppid, cpu = cpu, mem = mem, comm = comm }
    end
  end
  ps_cache, ps_at = list, now
  return list
end

local readlink = wayrun.fs.readlink

local function exe_of(pid, cache)
  if not readlink then return nil end
  local target = cache[pid]
  if target == nil then
    target = readlink("/proc/" .. pid .. "/exe") or false
    cache[pid] = target
  end
  return target or nil
end

-- A program that forks itself (nvim --embed, helper re-execs) would otherwise
-- show up once per process. The same comm under a parent hides it, and so does
-- the same executable under another comm (Firefox content processes).
local function nested_copy(p, by_pid, apps, exe)
  local key, ppid = p.comm:lower(), p.ppid
  local depth = 0
  while ppid and ppid ~= "0" and depth < 64 do
    local parent = by_pid[ppid]
    if not parent then return false end
    if parent.comm:lower() == key then return true end
    if apps[parent.comm:lower()] then
      local mine, theirs = exe_of(p.pid, exe), exe_of(parent.pid, exe)
      if mine and theirs and mine == theirs then return true end
    end
    ppid, depth = parent.ppid, depth + 1
  end
  return false
end

local function row(p, app)
  local payload = { pid = p.pid, start = start_time(p.pid) }
  local summary = ("%s%% CPU · %s%% MEM · PID %s"):format(p.cpu, p.mem, p.pid)
  if app and app.name:lower() ~= p.comm:lower() then
    summary = p.comm .. " · " .. summary
  end
  return {
    title = app and app.name or p.comm,
    summary = summary,
    icon = (app and app.icon) or GENERIC_ICON,
    on_click = { type = "plugin", plugin = "kill",
                 action = "term", payload = payload },
    actions = {
      {
        title = "SIGKILL",
        action = { type = "plugin", plugin = "kill",
                   action = "kill", payload = payload },
      },
      {
        title = t("Copy PID", "复制 PID"),
        action = { type = "copy", text = p.pid },
      },
    },
  }
end

local function search(text)
  local list, err = processes()
  if not list then
    return { {
      title = t("Could not list processes", "无法列出进程"),
      summary = err,
      icon = ICON,
    } }
  end

  local apps, rows = desktop_apps(), {}
  local by_pid, exe = {}, {}
  for _, p in ipairs(list) do by_pid[p.pid] = p end

  local query = text:lower()
  for _, p in ipairs(list) do
    if #rows >= MAX_ROWS then break end
    local comm = p.comm:lower()
    if not protected(comm) then
      local app = apps[comm]
      local hit
      if text == "" then
        hit = app ~= nil
      else
        local name = (app and app.name or p.comm):lower()
        hit = comm:find(query, 1, true) ~= nil or name:find(query, 1, true) ~= nil
      end
      if hit and not nested_copy(p, by_pid, apps, exe) then
        rows[#rows + 1] = row(p, app)
      end
    end
  end
  return rows
end

local function command(action, payload)
  local pid = tostring(payload.pid)

  if payload.start then
    local current = start_time(pid)
    if current and current ~= payload.start then
      wayrun.log("kill: PID " .. pid .. " was reused, skipped")
      return
    end
  end

  local sig = action == "kill" and "-KILL" or "-TERM"
  local ok, res = pcall(wayrun.exec, "kill", { sig, pid })
  ps_cache = nil
  if not ok or res.code ~= 0 then
    local why = ok and (res.stderr ~= "" and res.stderr or "exit " .. res.code)
      or tostring(res)
    wayrun.log("kill " .. pid .. ": " .. why)
  end
end

return {
  {
    id = "kill",
    name = t("Kill Process", "结束进程"),
    icon = ICON,
    description = t("Find a process by name and send SIGTERM or SIGKILL",
                    "按名称查找进程并发送 SIGTERM / SIGKILL"),
    api = 1,
    exec = { "id", "ps", "kill" },
    read = { "/proc" },
    search = search,
    top = function() return search("") end,
    command = command,
  },
}

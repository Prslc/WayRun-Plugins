-- Module descriptions.
--
-- Desktop files carry no description, so the only public source is the
-- module list (`kcmshell6 --list`). It costs one short Qt process (~115ms), so
-- the result is cached in the plugin's kv store: the core forks a fresh host
-- for each keyword-less search, so an in-process cache would never survive it.
-- The store is keyed on the module directories' stamp, which is also where a
-- new or removed KCM shows up. The child inherits the plugin's declared locale
-- variables, which is as close to WayRun's locale as the exec contract allows;
-- a failure leaves descriptions empty and rows still open modules by name.

local util = wayrun.import("kde/util")
local modules = wayrun.import("kde/modules")

local describe = {}

-- Same order as the exec declaration in the plugin table.
local PROGRAMS = { "kcmshell6", "kcmshell5", "systemsettings" }

local KEY = "module-descriptions"

local function parse(stdout)
  local map = {}
  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local id, description = line:match("^%s*([%w_%.%-]+)%s+%-%s+(.+)%s*$")
    if id and description ~= "" then
      map[id] = util.one_line(description)
    end
  end
  return map
end

-- A store that cannot be read or written only costs the subprocess, so every
-- call is best-effort.
local function from_store(stamp)
  local ok, raw = pcall(wayrun.kv.get, KEY)
  if not ok or type(raw) ~= "string" then
    return nil
  end
  local decoded, saved = pcall(wayrun.json.decode, raw)
  if
    not decoded
    or type(saved) ~= "table"
    or saved.stamp ~= stamp
    or type(saved.list) ~= "table"
  then
    return nil
  end
  return saved.list
end

local function to_store(stamp, map)
  local ok, raw = pcall(wayrun.json.encode, { stamp = stamp, list = map })
  if ok then
    pcall(wayrun.kv.set, KEY, raw)
  end
end

local cached
local loaded = false

local function load()
  if loaded then
    return cached
  end
  loaded = true

  local stamp = modules.stamp()
  local stored = from_store(stamp)
  if stored then
    cached = stored
    return cached
  end

  for _, program in ipairs(PROGRAMS) do
    if wayrun.which(program) then
      local ok, out = pcall(wayrun.exec, program, { "--list" })
      if ok and out and out.code == 0 then
        local map = parse(out.stdout)
        if next(map) then
          cached = map
          to_store(stamp, map)
          return cached
        end
      end
    end
  end

  cached = {}
  return cached
end

function describe.get(id)
  return load()[id] or ""
end

return describe

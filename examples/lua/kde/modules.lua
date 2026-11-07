-- Reads KCM desktop files into module records.
--
-- Plasma 6 installs them under applications/, Plasma 5 under kservices5/.
-- The desktop file carries the localized name, icon and the command that
-- opens the module (systemsettings kcm_* or kcmshell6 kcm_*).

local util = wayrun.import("kde/util")
local locale = wayrun.import("kde/locale")

local modules = {}

local MODULE_SUBDIRS = { "applications", "kservices6", "kservices5" }
local PROGRAMS = { "systemsettings", "kcmshell6", "kcmshell5" }


local function unescape(value)
  return (value:gsub("\\(.)", function(char)
    if char == "s" then
      return " "
    elseif char == "n" then
      return "\n"
    elseif char == "t" then
      return "\t"
    elseif char == "r" then
      return "\r"
    end
    return char
  end))
end

-- Only [Desktop Entry] counts; third-party files may carry other sections.
local function parse(text)
  local entry = {}
  local in_entry = false
  for line in text:gmatch("[^\r\n]+") do
    local bare = line:gsub("^%s+", ""):gsub("%s+$", "")
    if bare:sub(1, 1) == "[" then
      in_entry = bare == "[Desktop Entry]"
    elseif in_entry and bare ~= "" and bare:sub(1, 1) ~= "#" then
      local key, value = bare:match("^([^=]+)=(.*)$")
      if key then
        entry[key] = unescape(value)
      end
    end
  end
  return entry
end


local function data_dirs()
  local out, seen = {}, {}
  local function add(dir)
    if dir and dir ~= "" and not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end

  local home = wayrun.env("XDG_DATA_HOME")
  if not home or home == "" then
    local base = wayrun.home()
    if base and base ~= "" then
      home = base .. "/.local/share"
    end
  end
  add(home)

  local dirs = wayrun.env("XDG_DATA_DIRS")
  if not dirs or dirs == "" then
    dirs = "/usr/local/share:/usr/share"
  end
  for dir in dirs:gmatch("[^:]+") do
    add(dir)
  end
  return out
end

local function module_dirs()
  local out = {}
  for _, dir in ipairs(data_dirs()) do
    for _, sub in ipairs(MODULE_SUBDIRS) do
      out[#out + 1] = dir .. "/" .. sub
    end
  end
  return out
end


-- System Settings hides KCMs that only work on one Qt platform; honour the
-- same marker so an X11 session does not list Wayland-only pages.
local function qt_platform()
  local session = util.lower(wayrun.env("XDG_SESSION_TYPE"))
  local wayland_display = wayrun.env("WAYLAND_DISPLAY")
  if session == "wayland" or (wayland_display and wayland_display ~= "") then
    return "wayland"
  end
  if session == "x11" or (wayrun.env("DISPLAY") or "") ~= "" then
    return "xcb"
  end
  return nil
end

local function platform_allowed(value)
  if not value or value == "" then
    return true
  end
  local current = qt_platform()
  if not current then
    return true
  end
  for platform in value:gmatch("[^,;%s]+") do
    if platform:lower() == current then
      return true
    end
  end
  return false
end

-- NoDisplay is true for every KCM (they are not application-menu entries);
-- only Hidden, the desktop-entry deletion marker, removes a page.
local function is_hidden(entry)
  return util.lower(entry.Hidden) == "true"
end

-- Desktop file names are exactly kcm_<module>.desktop; the module id is what
-- systemsettings and kcmshell6 take.
local function module_of(file)
  local name = file:match("^(kcm_.+)%.desktop$")
  if name and name:match("^[%w_%.%-]+$") then
    return name
  end
  return nil
end


local function fallback_program()
  for _, program in ipairs(PROGRAMS) do
    if wayrun.which(program) then
      return program
    end
  end
  return nil
end

local function open_command(entry, module, program)
  local exec = entry.Exec or ""
  exec = exec:gsub("%s+$", ""):gsub("%%[fFuUdDnNickvm]", "")
  -- Trust the desktop file only when it names this module; a stale or strange
  -- Exec must not open something else.
  if exec ~= "" and exec:find(module, 1, true) then
    return exec
  end
  if program then
    return program .. " " .. util.quote(module)
  end
  return nil
end

-- Only System Settings has a root window; kcmshell6 without a module does
-- nothing, so its presence is not enough for an "all settings" action.
local root_checked, root

function modules.settings_root()
  if not root_checked then
    root_checked = true
    if wayrun.which("systemsettings") then
      root = "systemsettings"
    end
  end
  return root
end


local function keyword_list(entry, module, display)
  local out = {}
  local function add(value)
    for raw in (value or ""):gmatch("[^;]+") do
      local word = util.one_line(raw)
      if word ~= "" then
        out[#out + 1] = util.lower(word)
      end
    end
  end

  add(entry.Keywords)
  add(entry["X-KDE-Keywords"])
  add(locale.localized(entry, "Keywords", display))
  out[#out + 1] = util.lower(module)
  out[#out + 1] = util.lower(module:gsub("^kcm_", ""):gsub("[_%.%-]+", " "))
  return out
end

local function lower_list(values)
  local out = {}
  for _, value in ipairs(values) do
    out[#out + 1] = util.lower(value)
  end
  return out
end

local function record(entry, module, program, display, session)
  local name = util.one_line(locale.localized(entry, "Name", display))
  local name_en = util.one_line(entry.Name or "")
  local name_session = util.one_line(locale.localized(entry, "Name", session))
  if name == "" then
    name = name_en
  end
  if name == "" then
    name = module:gsub("^kcm_", ""):gsub("[_%-]+", " ")
  end
  if name_en == "" then
    name_en = name
  end

  return {
    id = module,
    icon = entry.Icon,
    name = name,
    name_en = name_en,
    name_lc = util.lower(name),
    name_en_lc = util.lower(name_en),
    name_session_lc = util.lower(name_session),
    alt_names_lc = lower_list(locale.all_names(entry, "Name")),
    keywords = keyword_list(entry, module, display),
    command = open_command(entry, module, program),
  }
end

-- A resident host must notice installed or removed KCMs. The directory's
-- mtime changes when a desktop file is added or removed, and is far cheaper
-- than re-reading all of them on every keystroke.
local function data_key(dirs)
  local parts = {}
  for _, dir in ipairs(dirs) do
    local stat = util.safe_stat(dir)
    parts[#parts + 1] = dir
    parts[#parts + 1] = stat and (tostring(stat.mtime_ns) .. ":" .. tostring(stat.size)) or "-"
  end
  return table.concat(parts, ":")
end

local cache = { key = nil, list = nil }

-- The directory stamp `modules.all` caches on, for a store keyed on the same
-- installed modules (descriptions are read from the module list, not the files).
function modules.stamp()
  return data_key(module_dirs())
end

function modules.all()
  local dirs = module_dirs()
  local key = data_key(dirs)
  if cache.list and cache.key == key then
    return cache.list
  end

  local display = locale.display_codes()
  local session = locale.session_codes()
  local program = fallback_program()
  local list, seen = {}, {}

  for _, dir in ipairs(dirs) do
    for _, file in ipairs(util.safe_list(dir) or {}) do
      local module = module_of(file)
      if module and not seen[module] then
        -- Earlier data dirs win, as in the XDG spec, even when the shadowed
        -- file is unusable: a broken user override should not fall through
        -- and show the system copy under a different icon or command.
        seen[module] = true
        local text = util.safe_read(dir .. "/" .. file)
        local entry = text and parse(text) or {}
        if not is_hidden(entry) and platform_allowed(entry["X-KDE-OnlyShowOnQtPlatforms"]) then
          list[#list + 1] = record(entry, module, program, display, session)
        end
      end
    end
  end

  table.sort(list, function(a, b)
    if a.name_en_lc ~= b.name_en_lc then
      return a.name_en_lc < b.name_en_lc
    end
    return a.id < b.id
  end)

  cache.key, cache.list = key, list
  return list
end

return modules

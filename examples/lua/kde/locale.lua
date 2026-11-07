-- Desktop-entry locale handling.
--
-- KDE keys use the language_COUNTRY form with an uppercase country
-- ("Name[zh_CN]"). WayRun reports the launcher's stem in lowercase
-- ("zh_cn"), and POSIX environments add an encoding and sometimes a
-- modifier ("zh_CN.UTF-8", "sr@latin").

local util = wayrun.import("kde/util")

local locale = {}

local function canonical_region(region)
  if region:match("^%a%a$") then
    return region:upper()
  end
  if region:match("^%d%d%d$") then
    return region
  end
  -- Script subtags such as "Hans" are title case.
  return region:sub(1, 1):upper() .. region:sub(2):lower()
end

-- Candidates for one locale, most specific first, in both separator forms.
function locale.codes(raw)
  if not raw or raw == "" then
    return {}
  end
  local text = raw:gsub("%..*$", "")
  local modifier = text:match("@(.+)$")
  local base = text:gsub("@.*$", "")
  if base == "" or base == "C" or base == "POSIX" then
    return {}
  end

  local language, region = base:match("^([^_%-]+)[_%-](.+)$")
  language = (language or base):lower()
  region = region and region ~= "" and canonical_region(region) or nil

  local out, seen = {}, {}
  local function add(value)
    if value and value ~= "" and not seen[value] then
      seen[value] = true
      out[#out + 1] = value
    end
  end

  if region then
    local with_modifier = modifier and (region .. "@" .. modifier) or region
    add(language .. "_" .. with_modifier)
    add(language .. "-" .. with_modifier)
  end
  if modifier then
    add(language .. "@" .. modifier)
  end
  if region then
    add(language .. "_" .. region)
    add(language .. "-" .. region)
  end
  add(language)
  add(base)
  return out
end

-- The KDE UI locale comes from the session, in the usual priority order.
function locale.session_codes()
  local raw = wayrun.env("LC_ALL")
  if not raw or raw == "" then
    raw = wayrun.env("LC_MESSAGES")
  end
  if not raw or raw == "" then
    raw = wayrun.env("LANG")
  end
  if not raw or raw == "" then
    return {}
  end
  return locale.codes(raw)
end

-- WayRun's own locale decides how rows read. When it names only a language
-- ("zh"), the session locale's region makes the desktop-entry key specific
-- enough to match ("zh_CN").
function locale.display_codes()
  local codes = locale.codes(wayrun.locale())
  local language = codes[1] and codes[1]:match("^([^_%-]+)$")
  if not language then
    return codes
  end

  local extra = {}
  for _, code in ipairs(locale.session_codes()) do
    if code ~= language and code:match("^" .. language .. "[_%-]") then
      extra[#extra + 1] = code
    end
  end
  for index = #extra, 1, -1 do
    table.insert(codes, 1, extra[index])
  end
  return codes
end

function locale.localized(entry, base, codes)
  for _, code in ipairs(codes) do
    local value = entry[base .. "[" .. code .. "]"]
    if value and value ~= "" then
      return value
    end
  end
  return entry[base] or ""
end

-- Every translated value, so a Chinese query can still match an English UI.
function locale.all_names(entry, base)
  local prefix = base .. "["
  local out, seen = {}, {}
  for key, value in pairs(entry) do
    if type(value) == "string" and value ~= "" and key:sub(1, #prefix) == prefix then
      local text = util.one_line(value)
      if text ~= "" and not seen[text] then
        seen[text] = true
        out[#out + 1] = text
      end
    end
  end
  return out
end

return locale

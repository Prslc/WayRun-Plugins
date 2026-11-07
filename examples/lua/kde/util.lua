-- Shared text and filesystem helpers for the KDE settings plugin.

local util = {}

function util.cut(text, max)
  if not text or #text <= max then
    return text
  end
  local at = max
  while at > 0 do
    local byte = text:byte(at + 1)
    if not byte or byte < 0x80 or byte >= 0xC0 then
      break
    end
    at = at - 1
  end
  return text:sub(1, at) .. "…"
end

function util.one_line(text)
  if type(text) ~= "string" then
    return ""
  end
  return (text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function util.lower(text)
  return type(text) == "string" and text:lower() or ""
end

function util.has_non_ascii(text)
  return text:find("[\128-\255]") ~= nil
end

-- Reads raise outside the plugin's declared areas; callers treat a raise and
-- an absent file alike.
function util.safe_list(path)
  local ok, value = pcall(wayrun.fs.list, path)
  return ok and value or nil
end

function util.safe_read(path)
  local ok, value = pcall(wayrun.fs.read, path)
  return ok and value or nil
end

function util.safe_stat(path)
  local ok, value = pcall(wayrun.fs.stat, path)
  return ok and value or nil
end

return util

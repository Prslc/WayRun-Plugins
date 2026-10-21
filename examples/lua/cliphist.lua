#!/usr/bin/env -S wayrun --lua-host
-- Clipboard history over `cliphist`; a row copies its entry back with wl-copy.

local icon = wayrun.icon("papirus:clipboard") or wayrun.icon("edit-paste")
local MAX_ROWS = 50
-- `wayrun.time()` is whole seconds, so the cache lives for the second it was
-- fetched in; `top` (entering the keyword) always refetches first.
local TTL = 1
local cached, fetched_at = nil, nil

-- cliphist prints `id<TAB>preview` or `id<TAB>type<TAB>preview`; the id is
-- digits only because a row interpolates it into a shell line.
local function parse(out)
  local entries = {}
  for line in out:gmatch("[^\n]+") do
    local id, _, preview = line:match("^(%d+)\t([^\t]*)\t(.*)$")
    if not id then
      id, preview = line:match("^(%d+)\t(.*)$")
    end
    if id and preview then
      entries[#entries + 1] = { id = id, preview = preview, lower = preview:lower() }
    end
  end
  return entries
end

local function fetch()
  local ok, result = pcall(wayrun.exec, "cliphist", { "list" })
  if not ok or not result or result.code ~= 0 then
    return {}
  end
  return parse(result.stdout)
end

-- A resident host keeps this table across calls; the `top` request (entering
-- the keyword) bypasses the cache so a show never starts from a stale list.
local function entries(fresh)
  local now = wayrun.time()
  if not fresh and cached and now - fetched_at < TTL then
    return cached
  end
  cached, fetched_at = fetch(), now
  return cached
end

local function rows(list, text)
  local query = (text or ""):lower()
  local out = {}
  for _, entry in ipairs(list) do
    if #out >= MAX_ROWS then
      break
    end
    if query == "" or entry.lower:find(query, 1, true) then
      out[#out + 1] = {
        title = entry.preview,
        on_click = { type = "run", cmd = "cliphist decode " .. entry.id .. " | wl-copy" },
      }
    end
  end
  return out
end

return {
  {
    id = "clipboard",
    name = "Clipboard History",
    icon = icon,
    description = "Search clipboard history",
    api = 1,
    exec = { "cliphist" },
    -- exec clears the environment; a custom XDG_CACHE_HOME moves cliphist's
    -- database away from `~/.cache/cliphist`.
    env = { "XDG_CACHE_HOME" },
    search = function(text)
      return rows(entries(false), text)
    end,
    top = function()
      return rows(entries(true), "")
    end,
  },
}

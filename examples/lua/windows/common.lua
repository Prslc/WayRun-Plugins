-- Shared scoring, MRU and row rendering for the compositor backends.

local common = {}

local MRU_KEY = "mru"
local MRU_LIMIT = 100

local FALLBACK_ICON = wayrun.icon("preferences-system-windows")
local zh = wayrun.locale():match("^zh") ~= nil

-- Best hit kind per window, in the launcher's own strength order.
local KIND_RANK = { exact = 1, prefix = 2, word = 3, substring = 4, loose = 5 }

function common.t(en, cn)
  return zh and cn or en
end

function common.hint(title, summary)
  return { { title = title, summary = summary, icon = FALLBACK_ICON } }
end

function common.icon_for(name)
  if not name then
    return FALLBACK_ICON
  end
  return wayrun.icon(name) or wayrun.icon("papirus:" .. name) or FALLBACK_ICON
end

local function load_mru()
  local text = wayrun.kv.get(MRU_KEY)
  if not text then
    return {}
  end
  local ok, mru = pcall(wayrun.json.decode, text)
  if not ok or type(mru) ~= "table" then
    return {}
  end
  return mru
end

local function save_mru(mru)
  local entries = {}
  for id, ts in pairs(mru) do
    entries[#entries + 1] = { id = id, ts = ts }
  end
  table.sort(entries, function(a, b)
    return a.ts > b.ts
  end)
  local kept = {}
  for i = 1, math.min(#entries, MRU_LIMIT) do
    kept[entries[i].id] = entries[i].ts
  end
  wayrun.kv.set(MRU_KEY, wayrun.json.encode(kept))
end

function common.remember(id)
  local mru = load_mru()
  mru[id] = wayrun.time()
  save_mru(mru)
end

local function rank(query, item)
  local candidates = { item.title }
  if item.app_id then
    candidates[#candidates + 1] = item.app_id
  end
  local ok, hits = pcall(wayrun.fuzzy.match, query, candidates)
  if not ok or type(hits) ~= "table" then
    return nil
  end
  local best
  for _, hit in ipairs(hits) do
    local weight = KIND_RANK[hit.kind]
    if weight and (not best or weight < best) then
      best = weight
    end
  end
  return best
end

-- The compositor's own order for an empty query; MRU is what Alt+Tab would
-- give, and none of the backends records it.
local function ordered(list, text)
  if text == "" then
    local mru = load_mru()
    local position = {}
    for i, item in ipairs(list) do
      position[item.id] = i
    end
    table.sort(list, function(a, b)
      local ta, tb = mru[a.id] or 0, mru[b.id] or 0
      if ta ~= tb then
        return ta > tb
      end
      return position[a.id] < position[b.id]
    end)
    return list
  end

  local scored = {}
  for i, item in ipairs(list) do
    local weight = rank(text, item)
    if weight then
      scored[#scored + 1] = { item = item, weight = weight, order = i }
    end
  end
  table.sort(scored, function(a, b)
    if a.weight ~= b.weight then
      return a.weight < b.weight
    end
    return a.order < b.order
  end)
  local kept = {}
  for _, entry in ipairs(scored) do
    kept[#kept + 1] = entry.item
  end
  return kept
end

local function summary_for(item)
  if item.summary then
    return item.summary
  end
  local app = item.app_id
  if app and item.workspace then
    return app .. " · " .. common.t("workspace ", "工作区 ") .. item.workspace
  end
  return app or (item.workspace and common.t("workspace ", "工作区 ") .. item.workspace)
end

function common.rows(text, list, plugin_id)
  list = ordered(list, text or "")
  local out = {}
  for _, item in ipairs(list) do
    out[#out + 1] = {
      title = item.title,
      summary = summary_for(item),
      icon = common.icon_for(item.app_id),
      on_click = { type = "plugin", plugin = plugin_id, action = "focus", payload = { id = item.id } },
      actions = {
        { title = common.t("Copy title", "复制标题"), action = { type = "copy", text = item.title } },
      },
    }
  end
  return out
end

return common

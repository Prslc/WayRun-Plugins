#!/usr/bin/env -S wayrun --lua-host
-- Web search suggestions from a Firefox-style suggest endpoint, one header
-- row plus one row per suggestion. The engine is this plugin's own choice.

local assets = wayrun.script_dir() .. "/assets/"

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local ENGINES = {
  google = {
    name = "Google",
    icon = assets .. "globe_icon.svg",
    search_url = "https://www.google.com/search?q=",
    suggest_url = "https://suggestqueries.google.com/complete/search?client=firefox",
  },
  duckduckgo = {
    name = "DuckDuckGo",
    icon = assets .. "globe_icon.svg",
    search_url = "https://duckduckgo.com/?q=",
    suggest_url = "https://duckduckgo.com/ac/?type=list",
  },
}

-- Pick one of the tables above.
local engine = ENGINES.google

local icon = engine.icon
local copy_icon = assets .. "copy_icon.svg"
local summary = t("Search on " .. engine.name, "在 " .. engine.name .. " 上搜索")

local function result_url(query)
  return engine.search_url .. wayrun.urlencode(query)
end

local function row(title, query)
  local uri = result_url(query)
  return {
    title = title,
    summary = summary,
    on_click = { type = "open", uri = uri },
    icon = icon,
    actions = {
      {
        title = t("Copy URL", "复制链接"),
        action = { type = "copy", text = uri },
        icon = copy_icon,
        id = "copy_url",
      },
    },
  }
end

return {
  {
    id = "web-search",
    name = engine.name,
    icon = icon,
    description = t("Search " .. engine.name .. " suggestions", "搜索 " .. engine.name .. " 的建议"),
    api = 1,
    search = function(text)
      if text == "" then
        return {}
      end
      local res = wayrun.http.get(engine.suggest_url, { q = text }, { ttl = 300 })
      local payload = wayrun.json.decode(res.body)
      local out = { row(t("Search: ", "搜索：") .. text, text) }
      local suggestions = type(payload) == "table" and payload[2] or nil
      if type(suggestions) == "table" then
        for _, phrase in ipairs(suggestions) do
          if type(phrase) == "string" then
            out[#out + 1] = row(phrase, phrase)
          end
        end
      end
      return out
    end,
  },
}

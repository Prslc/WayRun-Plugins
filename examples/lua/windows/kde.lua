-- KWin serves KRunner's "Windows" runner over D-Bus; an empty query lists
-- every window, and Run(matchId) activates one.

local kde = {
  tool = "busctl",
  name = "KDE",
  desktop = "kde",
}

local SERVICE, OBJECT, IFACE = "org.kde.KWin", "/WindowsRunner", "org.kde.krunner1"

local function busctl(args)
  local ok, result = pcall(wayrun.exec, "busctl", args)
  if not ok or result.code ~= 0 then
    return nil
  end
  return result.stdout
end

function kde.list()
  local output = busctl({ "--user", "--json=short", "call", SERVICE, OBJECT, IFACE, "Match", "s", "" })
  if not output then
    return nil
  end
  local ok, doc = pcall(wayrun.json.decode, output)
  if not ok or type(doc) ~= "table" or type(doc.data) ~= "table" or type(doc.data[1]) ~= "table" then
    return nil
  end

  -- KRunner repeats a window once per relevance tier.
  local seen, list = {}, {}
  for _, match in ipairs(doc.data[1]) do
    local id = match[1]
    if type(id) == "string" and not seen[id] then
      seen[id] = true
      local props = match[6]
      -- Titles carry bidi isolates that leak into a plain list.
      local title = (match[2] or ""):gsub("\226\128\142", ""):gsub("\226\129[\166-\169]", "")
      list[#list + 1] = {
        id = id,
        title = title,
        app_id = match[3],
        summary = props and props.subtext and props.subtext.data,
      }
    end
  end
  return list
end

function kde.focus(id)
  local ok, result = pcall(wayrun.exec, "busctl", {
    "--user",
    "call",
    SERVICE,
    OBJECT,
    IFACE,
    "Run",
    "ss",
    id,
    "",
  })
  return ok and result.code == 0
end

return kde

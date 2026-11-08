-- niri IPC: `niri msg --json windows` lists, `niri msg action focus-window`
-- focuses by window id.

local common = wayrun.import("windows/common")

local niri = {
  tool = "niri",
  name = "niri",
  desktop = "niri",
  socket_env = "NIRI_SOCKET",
}

local function trimmed(value)
  if type(value) ~= "string" then
    return ""
  end
  return value:match("^%s*(.-)%s*$")
end

function niri.list()
  local ok, result = pcall(wayrun.exec, "niri", { "msg", "--json", "windows" })
  if not ok or result.code ~= 0 then
    return nil
  end
  local parsed, decoded = pcall(wayrun.json.decode, result.stdout)
  if not parsed or type(decoded) ~= "table" then
    return nil
  end

  local list = {}
  for _, window in ipairs(decoded) do
    if type(window) == "table" and type(window.id) == "number" then
      local app_id = type(window.app_id) == "string" and window.app_id or nil
      local title = trimmed(window.title)
      if title == "" then
        title = app_id or common.t("Untitled", "无标题")
      end
      list[#list + 1] = {
        id = tostring(window.id),
        title = title,
        app_id = app_id,
        workspace = type(window.workspace_id) == "number" and tostring(window.workspace_id) or nil,
      }
    end
  end
  return list
end

function niri.focus(id)
  local ok, result = pcall(wayrun.exec, "niri", { "msg", "action", "focus-window", "--id", id })
  return ok and result.code == 0
end

return niri

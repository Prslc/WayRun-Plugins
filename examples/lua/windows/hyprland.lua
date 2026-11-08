-- Hyprland IPC: `hyprctl -j clients` lists, `hyprctl dispatch focuswindow
-- address:<address>` focuses.

local common = wayrun.import("windows/common")

local hyprland = {
  tool = "hyprctl",
  name = "Hyprland",
  desktop = "hyprland",
  socket_env = "HYPRLAND_INSTANCE_SIGNATURE",
}

local function trimmed(value)
  if type(value) ~= "string" then
    return ""
  end
  return value:match("^%s*(.-)%s*$")
end

function hyprland.list()
  local ok, result = pcall(wayrun.exec, "hyprctl", { "-j", "clients" })
  if not ok or result.code ~= 0 then
    return nil
  end
  local parsed, decoded = pcall(wayrun.json.decode, result.stdout)
  if not parsed or type(decoded) ~= "table" then
    return nil
  end

  local list = {}
  for _, client in ipairs(decoded) do
    -- An unmapped client has no surface yet; a hidden one sits on a special
    -- workspace that is not shown.
    if type(client) == "table" and type(client.address) == "string" and client.mapped == true and client.hidden ~= true then
      local class = trimmed(client.class)
      local initial = trimmed(client.initialClass)
      local app_id = class ~= "" and class or (initial ~= "" and initial or nil)

      local title = trimmed(client.title)
      if title == "" then
        title = app_id or common.t("Untitled", "无标题")
      end

      local workspace = type(client.workspace) == "table" and client.workspace or nil
      local workspace_label
      if workspace then
        local name = trimmed(workspace.name)
        if name ~= "" then
          workspace_label = name
        elseif type(workspace.id) == "number" then
          workspace_label = tostring(workspace.id)
        end
      end

      list[#list + 1] = {
        id = client.address,
        title = title,
        app_id = app_id,
        workspace = workspace_label,
      }
    end
  end
  return list
end

function hyprland.focus(id)
  local ok, result = pcall(wayrun.exec, "hyprctl", { "dispatch", "focuswindow", "address:" .. id })
  return ok and result.code == 0
end

return hyprland

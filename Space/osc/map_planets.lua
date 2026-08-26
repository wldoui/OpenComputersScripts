-- map_planets.lua
-- BFS over real ntm_stardar API only: getCurrentPlanet(), getPlanetStats(name), getSatellites(name)
-- No getBodies() exists — this is the only honest way to build a full system map.

local component = require("component")
local serialization = require("serialization")
local filesystem = require("filesystem")

if not component.isAvailable("ntm_stardar") then
  print("No 'ntm_stardar' component found.")
  return
end

local stardar = component.ntm_stardar

local visited = {}   -- [planetName] = statsTable
local queue = {}
local edges = {}      -- [planetName] = { parent = ..., satellites = {...} }

local function pushIfNew(name)
  if name and name ~= "" and not visited[name] and not (function()
      for _, q in ipairs(queue) do if q == name then return true end end
      return false
    end)() then
    table.insert(queue, name)
  end
end

local start = stardar.getCurrentPlanet()
if not start then
  print("getCurrentPlanet() returned nothing.")
  return
end
pushIfNew(start)

local STAT_FIELDS = {
  "name", "parent", "star", "tidalLock", "axialTilt", "landable",
  "mass", "processingLevel", "radius", "semiMajorAxis", "sunPower",
  "gravity", "rotPeriod", "orbPeriod"
}

while #queue > 0 do
  local name = table.remove(queue, 1)
  if not visited[name] then
    local raw = { stardar.getPlanetStats(name) }
    if raw[1] == nil then
      -- nil, "No body with that name found." -- record the miss, don't invent stats
      visited[name] = { error = raw[2] or "unknown lookup failure" }
    else
      local stats = {}
      for i, field in ipairs(STAT_FIELDS) do
        stats[field] = raw[i]
      end
      visited[name] = stats

      if stats.parent then pushIfNew(stats.parent) end

      local sats = { stardar.getSatellites(name) }
      local satList = {}
      if sats[1] ~= nil then
        for _, satName in ipairs(sats) do
          table.insert(satList, satName)
          pushIfNew(satName)
        end
      end
      edges[name] = satList
    end
  end
end

-- ---- output ----
print("=== SYSTEM MAP (BFS from " .. start .. ") ===")
for name, stats in pairs(visited) do
  if stats.error then
    print(name .. "  [ERROR: " .. stats.error .. "]")
  else
    print(string.format("%s  parent=%s star=%s landable=%s radius=%skm grav=%sm/s2 orbit=%sd",
      name, tostring(stats.parent), tostring(stats.star), tostring(stats.landable),
      tostring(stats.radius), tostring(stats.gravity), tostring(stats.orbPeriod)))
    local sats = edges[name]
    if sats and #sats > 0 then
      print("  satellites: " .. table.concat(sats, ", "))
    end
  end
end

filesystem.makeDirectory("/data")
local f = io.open("/data/system_map.dat", "w")
f:write(serialization.serialize({ start = start, bodies = visited, satellites = edges }))
f:close()
print("")
print("Saved: /data/system_map.dat (paste this file's content back to me to extend space_view.lua)")

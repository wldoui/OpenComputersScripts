-- space_view.lua
-- Pseudo-3D Space Control viewer for OpenComputers + HBM Space (NTM-Space 0.9.2).
--
-- Renders entirely on the GPU/Screen (no hologram projector, no world voxels).
-- Uses ONLY documented ntm_stardar / ntm_rocket_pad callbacks -- nothing here
-- is invented. Where the API genuinely has no data (object positions,
-- rocket-in-flight telemetry), the UI says so explicitly instead of
-- making numbers up.
--
-- REQUIRES:
--   /lib/vector3.lua
--   /lib/render3d.lua
--   an OC cable wired directly into the StarDar CORE block (metadata >= 12)
--   optionally: an ntm_rocket_pad on the same network, for pad status
--
-- RUN: space_view

local component = require("component")
local event = require("event")
local term = require("term")
local keyboard = require("keyboard")
local Vector3 = require("vector3")
local Render3D = require("render3d")

local gpu = component.gpu

--------------------------------------------------------------------------
-- Component discovery (never assumes -- always checks)
--------------------------------------------------------------------------

local function firstOfType(ctype)
  for address in component.list(ctype) do
    return component.proxy(address)
  end
  return nil
end

local stardar = firstOfType("ntm_stardar")
if not stardar then
  io.stderr:write("No 'ntm_stardar' component found on this network.\n")
  io.stderr:write("Connect an OC cable directly to the StarDar CORE block\n")
  io.stderr:write("(the block with metadata >= 12), then retry.\n")
  return
end

local rocketPad = firstOfType("ntm_rocket_pad") -- optional

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function fmt(v)
  if v == nil then return "N/A" end
  if type(v) == "boolean" then return v and "yes" or "no" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.2f", v)
  end
  return tostring(v)
end

-- Calls fn(...) safely and packs *all* return values (component proxy
-- calls can return a variable-length "list" per the HBM wiki).
local function safePack(fn, ...)
  local packed = table.pack(pcall(fn, ...))
  if not packed[1] then
    return nil, packed[2] -- pcall error message
  end
  return packed
end

--------------------------------------------------------------------------
-- Screen layout
--------------------------------------------------------------------------

local screenW, screenH = gpu.getResolution()
local HEADER_H = 2
local FOOTER_H = 2
local PANEL_W = 28

local viewX, viewY = 1, HEADER_H + 1
local viewW = screenW - PANEL_W - 1
local viewH = screenH - HEADER_H - FOOTER_H
local panelX = viewW + 2

--------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------

local camera = Render3D.Camera.new()
camera.distance = 28

--------------------------------------------------------------------------
-- Scene / data model
--------------------------------------------------------------------------

local PLANET_VISUAL_RADIUS = 9  -- stylised render size, NOT to scale
local MOON_ORBIT_RADIUS = 17

local scene = {
  planetName = nil,
  planetStats = nil,
  planetMesh = nil,
  moons = {},        -- { name, localPos }  -- LAYOUT ONLY, see header note
  padStatus = nil,
  screenObjects = {}, -- rebuilt every frame, used for click-selection
}

local function fetchPlanetStats(name)
  local packed, err = safePack(stardar.getPlanetStats, name)
  if not packed then return nil, err end
  if packed[2] == nil then return nil, packed[3] or "No body with that name found." end
  return {
    name = packed[2], parent = packed[3], star = packed[4],
    tidallyLockedTo = packed[5], axialTilt = packed[6], landable = packed[7],
    massKg = packed[8], processingLevel = packed[9], radiusKm = packed[10],
    semiMajorAxisKm = packed[11], sunPowerPct = packed[12],
    surfaceGravity = packed[13], rotationalPeriod = packed[14],
    orbitalPeriod = packed[15],
  }
end

local function fetchMoonNames(name)
  local packed, err = safePack(stardar.getSatellites, name)
  if not packed then return {}, err end
  if packed[2] == nil then return {}, packed[3] or "No body with that name found." end
  local names = {}
  for i = 2, packed.n do
    if packed[i] ~= nil then names[#names + 1] = packed[i] end
  end
  return names
end

local function fetchRocketPadStatus()
  if not rocketPad then return nil end
  local status = {}

  local energyPacked = safePack(rocketPad.getEnergyInfo)
  if energyPacked then
    status.energy, status.energyMax = energyPacked[2], energyPacked[3]
  end

  local fuelPacked = safePack(rocketPad.getFuel)
  if fuelPacked then
    status.fuelTanks = {}
    local i = 2
    while fuelPacked[i] ~= nil do
      status.fuelTanks[#status.fuelTanks + 1] = {
        fill = fuelPacked[i], max = fuelPacked[i + 1], fluid = fuelPacked[i + 2],
      }
      i = i + 3
    end
  end

  local solidPacked = safePack(rocketPad.getSolidFuel)
  if solidPacked then
    status.solidFuel, status.solidFuelMax = solidPacked[2], solidPacked[3]
  end

  local canPacked = safePack(rocketPad.canLaunch)
  if canPacked then status.canLaunch = canPacked[2] end

  local statsPacked = safePack(rocketPad.getRocketStats)
  if statsPacked and statsPacked[2] ~= nil then
    status.stages, status.launchMass, status.height =
      statsPacked[2], statsPacked[3], statsPacked[4]
  elseif statsPacked then
    status.rocketError = statsPacked[3] or "No rocket on pad."
  end

  local destPacked = safePack(rocketPad.getDestination)
  if destPacked and destPacked[2] ~= nil then
    status.destination = destPacked[2]
  elseif destPacked then
    status.destinationError = destPacked[3] or "No destination."
  end

  return status
end

local function refreshData()
  local ok, planetName = pcall(function() return stardar.getCurrentPlanet() end)
  scene.planetName = ok and planetName or ("ERROR: " .. tostring(planetName))

  scene.planetMesh = Render3D.generateBlockyPlanet(PLANET_VISUAL_RADIUS, 6)

  scene.moons = {}
  if ok then
    local stats = fetchPlanetStats(planetName)
    scene.planetStats = stats

    local moonNames = fetchMoonNames(planetName)
    local count = math.max(#moonNames, 1)
    for i, mname in ipairs(moonNames) do
      local angle = (i - 1) * (2 * math.pi / count)
      local pos = Vector3.new(
        math.cos(angle) * MOON_ORBIT_RADIUS,
        math.sin(angle * 0.5) * 2, -- visual stagger only
        math.sin(angle) * MOON_ORBIT_RADIUS
      )
      scene.moons[#scene.moons + 1] = { name = mname, localPos = pos }
    end
  end

  scene.padStatus = fetchRocketPadStatus()
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

local function project(pos)
  return camera:project(pos, viewW, viewH)
end

local function renderViewport()
  local buf, depthBuf = {}, {}
  for y = 1, viewH do
    buf[y] = {}
    depthBuf[y] = {}
    for x = 1, viewW do
      buf[y][x] = " "
      depthBuf[y][x] = math.huge
    end
  end

  local lightDir = Vector3.new(0.4, 0.8, 0.4):normalize()

  -- Planet surface
  if scene.planetMesh then
    for _, cell in ipairs(scene.planetMesh) do
      local sx, sy, depth = project(cell.pos)
      if sx then
        local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
        if ix >= 1 and ix <= viewW and iy >= 1 and iy <= viewH then
          if depth < depthBuf[iy][ix] then
            local brightness = cell.normal:dot(lightDir)
            buf[iy][ix] = Render3D.shadeChar(brightness)
            depthBuf[iy][ix] = depth
          end
        end
      end
    end
  end

  scene.screenObjects = {}

  -- Moons (layout markers)
  for _, moon in ipairs(scene.moons) do
    local sx, sy = project(moon.localPos)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      if ix >= 1 and ix <= viewW and iy >= 1 and iy <= viewH then
        buf[iy][ix] = "o"
        scene.screenObjects[#scene.screenObjects + 1] = {
          kind = "moon", name = moon.name, sx = ix, sy = iy,
        }
      end
    end
  end

  -- Rocket pad marker (static ground marker -- no in-flight position exists)
  if rocketPad then
    local padPos = Vector3.new(PLANET_VISUAL_RADIUS + 4, 0, 0)
    local sx, sy = project(padPos)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      if ix >= 1 and ix <= viewW and iy >= 1 and iy <= viewH then
        buf[iy][ix] = "P"
        scene.screenObjects[#scene.screenObjects + 1] = {
          kind = "pad", name = "ROCKET PAD", sx = ix, sy = iy,
        }
      end
    end
  end

  gpu.setBackground(0x000000)
  gpu.setForeground(0x33CCFF)
  for y = 1, viewH do
    gpu.set(viewX, viewY + y - 1, table.concat(buf[y]))
  end
end

local function drawHeader()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, screenW, HEADER_H, " ")
  gpu.set(2, 1, "OPEN SPACE CONTROL // STAR DAR")
  gpu.set(2, 2, string.rep("-", screenW - 2))
end

local function drawFooter()
  gpu.fill(1, screenH - FOOTER_H + 1, screenW, FOOTER_H, " ")
  gpu.set(2, screenH - FOOTER_H + 1, string.rep("-", screenW - 2))
  gpu.set(2, screenH, "[WASD] rotate [E/Z] zoom [click] select [r] refresh [esc] quit")
end

local selected = nil

local function drawPanel()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(panelX, viewY, PANEL_W, viewH, " ")

  local y = viewY
  local function line(text)
    if y <= viewY + viewH - 1 then
      gpu.set(panelX, y, text)
      y = y + 1
    end
  end

  if selected then
    line("SELECTED:")
    line(tostring(selected.name))
    line("")
    if selected.kind == "moon" then
      line("Type: satellite/moon")
      line("Position: LAYOUT ONLY")
      line("(ntm_stardar exposes no")
      line(" real orbital coords)")
    elseif selected.kind == "pad" then
      local s = scene.padStatus
      line("Type: rocket launch pad")
      line("")
      if s then
        line("Energy: " .. fmt(s.energy) .. "/" .. fmt(s.energyMax))
        line("Solid fuel: " .. fmt(s.solidFuel) .. "/" .. fmt(s.solidFuelMax))
        if s.fuelTanks then
          for i, tank in ipairs(s.fuelTanks) do
            line(string.format("Tank %d: %s %s/%s",
              i, tostring(tank.fluid), fmt(tank.fill), fmt(tank.max)))
          end
        end
        line("Can launch: " .. fmt(s.canLaunch))
        if s.stages then
          line("Stages: " .. fmt(s.stages))
          line("Launch mass: " .. fmt(s.launchMass))
          line("Height: " .. fmt(s.height))
        else
          line("Rocket: " .. tostring(s.rocketError))
        end
        if s.destination then
          line("Dest: " .. tostring(s.destination))
        else
          line("Dest: " .. tostring(s.destinationError))
        end
      else
        line("(no rocket pad data)")
      end
    end
    line("")
    line("[click empty space]")
    line("to deselect")
  else
    line("PLANET:")
    line(tostring(scene.planetName))
    line("")
    local st = scene.planetStats
    if st then
      line("Star: " .. fmt(st.star))
      line("Landable: " .. fmt(st.landable))
      line("Radius: " .. fmt(st.radiusKm) .. " km")
      line("Gravity: " .. fmt(st.surfaceGravity) .. " m/s^2")
      line("Orbital period: " .. fmt(st.orbitalPeriod) .. " d")
    end
    line("")
    line("Moons (" .. #scene.moons .. "):")
    for _, m in ipairs(scene.moons) do
      line("  - " .. m.name)
    end
    line("")
    if rocketPad then
      line("Rocket pad: connected")
      line("(click the 'P' marker)")
    else
      line("Rocket pad: not found")
    end
  end
end

--------------------------------------------------------------------------
-- Interaction
--------------------------------------------------------------------------

local function trySelect(x, y)
  local best, bestDist
  for _, obj in ipairs(scene.screenObjects) do
    local ox, oy = viewX + obj.sx - 1, viewY + obj.sy - 1
    local dist = math.abs(ox - x) + math.abs(oy - y)
    if not bestDist or dist < bestDist then
      bestDist, best = dist, obj
    end
  end
  if best and bestDist <= 2 then
    selected = best
  else
    selected = nil
  end
end

--------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------

local function redraw()
  renderViewport()
  drawPanel()
end

drawHeader()
drawFooter()
refreshData()
redraw()

local running = true
local lastDrag = nil

while running do
  local e = { event.pull(0.5) }
  local ename = e[1]
  local needsRedraw = false

  if ename == "key_down" then
    local code = e[4]
    if code == keyboard.keys.escape or code == keyboard.keys.q then
      running = false
    elseif code == keyboard.keys.w then
      camera.pitch = math.min(camera.pitch + 0.1, 1.5); needsRedraw = true
    elseif code == keyboard.keys.s then
      camera.pitch = math.max(camera.pitch - 0.1, -1.5); needsRedraw = true
    elseif code == keyboard.keys.a then
      camera.yaw = camera.yaw - 0.15; needsRedraw = true
    elseif code == keyboard.keys.d then
      camera.yaw = camera.yaw + 0.15; needsRedraw = true
    elseif code == keyboard.keys.e then
      camera.distance = math.max(12, camera.distance - 2); needsRedraw = true
    elseif code == keyboard.keys.z then
      camera.distance = math.min(60, camera.distance + 2); needsRedraw = true
    elseif code == keyboard.keys.r then
      refreshData(); needsRedraw = true
    end
  elseif ename == "touch" then
    trySelect(e[3], e[4])
    needsRedraw = true
  elseif ename == "drag" then
    local x, y = e[3], e[4]
    if lastDrag then
      camera.yaw = camera.yaw + (x - lastDrag.x) * 0.05
      camera.pitch = math.max(-1.5, math.min(1.5, camera.pitch - (y - lastDrag.y) * 0.05))
      needsRedraw = true
    end
    lastDrag = { x = x, y = y }
  elseif ename == "scroll" then
    local dir = e[5] or 0
    camera.distance = math.max(12, math.min(60, camera.distance - dir * 2))
    needsRedraw = true
  end

  if ename ~= "drag" then lastDrag = nil end

  if needsRedraw then
    redraw()
  end
end

term.clear()
print("Space Control closed.")

-- space_view.lua
-- OPEN SPACE CONTROL -- futuristic pseudo-3D viewer for HBM Space + OpenComputers.
--
-- Rendered entirely on GPU/Screen text-mode -- no hologram projector, no
-- voxels placed in the world. Requires a colour-capable GPU (Tier 2/3)
-- for the full look; falls back to monochrome automatically on Tier 1.
--
-- HONESTY CONTRACT (read this before changing anything):
--   REAL data (always pulled live from the game, never invented):
--     - current planet name + full stats        (ntm_stardar)
--     - moon/satellite NAMES                     (ntm_stardar)
--     - rocket pad energy/fuel/stage/launch data (ntm_rocket_pad)
--   DECORATIVE / labelled-as-such (never presented as measured telemetry):
--     - starfield, orbit rings, moon layout positions, planet color grade
--     - the animated rocket flight path (marked "SIMULATED" on screen --
--       HBM Space's OC API has no in-flight rocket position, real or not)
--
-- REQUIRES:
--   /lib/vector3.lua
--   /lib/render3d.lua
--   OC cable wired directly to the StarDar CORE block (metadata >= 12)
--   optional: an ntm_rocket_pad on the same network
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
-- Component discovery
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
  io.stderr:write("(the block whose metadata is >= 12), then retry.\n")
  return
end

local rocketPad = firstOfType("ntm_rocket_pad") -- optional

--------------------------------------------------------------------------
-- Colour support detection
--------------------------------------------------------------------------

local COLOR = gpu.getDepth() > 1

local PALETTE = {
  bg        = 0x000000,
  chrome    = 0x2A6E8A,   -- panel borders
  title     = 0x7CE8FF,
  text      = 0xC8D8E0,
  dim       = 0x4C6570,
  star      = 0x445577,
  ring      = 0x2E5FA0,
  moon      = 0x66FFEA,
  pad       = 0xFFA83C,
  flight    = 0xFF5C5C,
  flightTip = 0xFFE38C,
  select    = 0xFFF35C,
  ok        = 0x62D97C,
  bad       = 0xFF5C5C,
}

local function setFg(c)
  if COLOR then gpu.setForeground(c) else gpu.setForeground(0xFFFFFF) end
end

--------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------

local function fmt(v)
  if v == nil then return "N/A" end
  if type(v) == "boolean" then return v and "YES" or "NO" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.2f", v)
  end
  return tostring(v)
end

local function safePack(fn, ...)
  local packed = table.pack(pcall(fn, ...))
  if not packed[1] then return nil, packed[2] end
  return packed
end

--------------------------------------------------------------------------
-- Screen layout
--------------------------------------------------------------------------

local screenW, screenH = gpu.getResolution()
local HEADER_H = 3
local FOOTER_H = 3
local PANEL_W = 30

local viewX, viewY = 2, HEADER_H + 2
local viewW = screenW - PANEL_W - 4
local viewH = screenH - HEADER_H - FOOTER_H - 2
local panelX = viewX + viewW + 3

--------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------

local camera = Render3D.Camera.new()
camera.distance = 30
camera.yaw = 0.8
camera.pitch = 0.45

--------------------------------------------------------------------------
-- Scene / data model
--------------------------------------------------------------------------

local PLANET_R = 9          -- stylised render size, NOT to scale
local MOON_ORBIT_R = 18
local STARFIELD_R = 500

local scene = {
  planetName = nil,
  planetStats = nil,
  planetMesh = nil,
  moons = {},           -- { name, localPos }         -- LAYOUT ONLY
  stars = Render3D.starfield(140, STARFIELD_R, 90210),
  padStatus = nil,
  screenObjects = {},   -- rebuilt each frame, used for click-selection
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
  if energyPacked then status.energy, status.energyMax = energyPacked[2], energyPacked[3] end

  local fuelPacked = safePack(rocketPad.getFuel)
  if fuelPacked then
    status.fuelTanks = {}
    local i = 2
    while fuelPacked[i] ~= nil do
      status.fuelTanks[#status.fuelTanks + 1] =
        { fill = fuelPacked[i], max = fuelPacked[i + 1], fluid = fuelPacked[i + 2] }
      i = i + 3
    end
  end

  local solidPacked = safePack(rocketPad.getSolidFuel)
  if solidPacked then status.solidFuel, status.solidFuelMax = solidPacked[2], solidPacked[3] end

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

local function findMoonByName(name)
  if not name then return nil end
  local lname = tostring(name):lower()
  for _, m in ipairs(scene.moons) do
    if m.name:lower():find(lname, 1, true) or lname:find(m.name:lower(), 1, true) then
      return m
    end
  end
  return nil
end

local function refreshData()
  local ok, planetName = pcall(function() return stardar.getCurrentPlanet() end)
  scene.planetName = ok and planetName or ("ERROR: " .. tostring(planetName))
  scene.planetMesh = Render3D.generateBlockyPlanet(PLANET_R, 7)

  scene.moons = {}
  if ok then
    scene.planetStats = fetchPlanetStats(planetName)
    local moonNames = fetchMoonNames(planetName)
    local count = math.max(#moonNames, 1)
    for i, mname in ipairs(moonNames) do
      local a = (i - 1) * (2 * math.pi / count)
      scene.moons[#scene.moons + 1] = {
        name = mname,
        localPos = Vector3.new(math.cos(a) * MOON_ORBIT_R, math.sin(a * 0.5) * 2, math.sin(a) * MOON_ORBIT_R),
      }
    end
  end

  scene.padStatus = fetchRocketPadStatus()
end

--------------------------------------------------------------------------
-- Simulated flight path (clearly marked, never confused with telemetry)
--------------------------------------------------------------------------

local flight = nil -- { from, to, startClock, duration, real }
local selectedRef = nil -- must be declared before renderViewport()/trySelect() close over it

local function startFlight(real)
  local padPos = Vector3.new(PLANET_R + 4, 0, 0)
  local dest = findMoonByName(scene.padStatus and scene.padStatus.destination)
  local toPos = dest and dest.localPos or Vector3.new(MOON_ORBIT_R * 1.1, 6, MOON_ORBIT_R * 0.4)
  flight = { from = padPos, to = toPos, startClock = os.clock(), duration = 16, real = real }
end

local function flightPosition(t)
  local lin = flight.from + (flight.to - flight.from) * t
  local bulge = math.sin(t * math.pi) * 6
  return lin + Vector3.new(0, bulge, 0)
end

--------------------------------------------------------------------------
-- Rendering: char buffer + colour buffer, blitted as runs (cheap on GPU)
--------------------------------------------------------------------------

local function project(pos) return camera:project(pos, viewW, viewH) end

local function newBuffers()
  local buf, col, depth = {}, {}, {}
  for y = 1, viewH do
    buf[y], col[y], depth[y] = {}, {}, {}
    for x = 1, viewW do
      buf[y][x] = " "
      col[y][x] = PALETTE.bg
      depth[y][x] = math.huge
    end
  end
  return buf, col, depth
end

local function plot(buf, col, depth, x, y, ch, color, testDepth, force)
  if x < 1 or x > viewW or y < 1 or y > viewH then return end
  if force or not testDepth or testDepth < depth[y][x] then
    buf[y][x] = ch
    col[y][x] = color
    if testDepth then depth[y][x] = testDepth end
  end
end

local function renderViewport()
  local buf, col, depth = newBuffers()
  local lightDir = Vector3.new(0.4, 0.85, 0.35):normalize()

  -- 1) Starfield (background, no depth test)
  for _, s in ipairs(scene.stars) do
    local sx, sy = project(s)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      plot(buf, col, depth, ix, iy, ".", PALETTE.star, nil, true)
    end
  end

  -- 2) Orbit ring (layout only) -- depth tested so the planet occludes it
  if #scene.moons > 0 then
    local ring = Render3D.ringPoints(MOON_ORBIT_R, 64, 0)
    for _, p in ipairs(ring) do
      local sx, sy, d = project(p)
      if sx then
        local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
        plot(buf, col, depth, ix, iy, "\xC2\xB7", PALETTE.ring, d, false)
      end
    end
  end

  -- 3) Blocky planet, shaded + coloured, depth tested
  scene.planetPixels = {}
  for _, cell in ipairs(scene.planetMesh) do
    local sx, sy, d = project(cell.pos)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      if ix >= 1 and ix <= viewW and iy >= 1 and iy <= viewH and d < depth[iy][ix] then
        local brightness = math.max(0, cell.normal:dot(lightDir))
        buf[iy][ix] = Render3D.shadeChar(brightness)
        col[iy][ix] = COLOR and Render3D.colorForBrightness(brightness) or 0xFFFFFF
        depth[iy][ix] = d
        scene.planetPixels[iy .. ":" .. ix] = true
      end
    end
  end

  -- 4) Simulated rocket flight path, if active
  scene.screenObjects = {}
  if flight then
    local t = (os.clock() - flight.startClock) / flight.duration
    if t >= 1 then
      flight = nil
    else
      for k = 0, 5 do
        local tt = t - k * 0.035
        if tt >= 0 then
          local pos = flightPosition(tt)
          local sx, sy = project(pos)
          if sx then
            local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
            local ch = (k == 0) and "*" or "."
            local color = (k == 0) and PALETTE.flightTip or PALETTE.flight
            plot(buf, col, depth, ix, iy, ch, color, nil, true)
          end
        end
      end
    end
  end

  -- 5) Moons (selectable markers, always on top)
  for _, moon in ipairs(scene.moons) do
    local sx, sy = project(moon.localPos)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      plot(buf, col, depth, ix, iy, "o", PALETTE.moon, nil, true)
      scene.screenObjects[#scene.screenObjects + 1] = { kind = "moon", name = moon.name, sx = ix, sy = iy }
    end
  end

  -- 6) Rocket pad marker (static ground marker, real component if present)
  if rocketPad then
    local padPos = Vector3.new(PLANET_R + 4, 0, 0)
    local sx, sy = project(padPos)
    if sx then
      local ix, iy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      plot(buf, col, depth, ix, iy, "P", PALETTE.pad, nil, true)
      scene.screenObjects[#scene.screenObjects + 1] = { kind = "pad", name = "ROCKET PAD", sx = ix, sy = iy }
    end
  end

  -- 7) Planet itself is selectable: any drawn planet pixel counts
  scene.screenObjects[#scene.screenObjects + 1] = {
    kind = "planet", name = scene.planetName, sx = math.floor(viewW / 2), sy = math.floor(viewH / 2), isBody = true,
  }

  -- 8) Selection highlight
  if selectedRef then
    for _, o in ipairs(scene.screenObjects) do
      if o.kind == selectedRef.kind and o.name == selectedRef.name and not o.isBody then
        col[o.sy][o.sx] = PALETTE.select
        if o.sx - 1 >= 1 then buf[o.sy][o.sx - 1] = "["; col[o.sy][o.sx - 1] = PALETTE.select end
        if o.sx + 1 <= viewW then buf[o.sy][o.sx + 1] = "]"; col[o.sy][o.sx + 1] = PALETTE.select end
      end
    end
  end

  -- Blit: group each row into runs of equal colour to minimise GPU calls
  gpu.setBackground(PALETTE.bg)
  for y = 1, viewH do
    local x = 1
    while x <= viewW do
      local c = col[y][x]
      local startX = x
      local chars = {}
      while x <= viewW and col[y][x] == c do
        chars[#chars + 1] = buf[y][x]
        x = x + 1
      end
      setFg(c)
      gpu.set(viewX + startX - 1, viewY + y - 1, table.concat(chars))
    end
  end
end

--------------------------------------------------------------------------
-- Chrome: header / footer / boxed panel
--------------------------------------------------------------------------

local function box(x, y, w, h, title)
  setFg(PALETTE.chrome)
  gpu.set(x, y, "\xE2\x94\x8C" .. string.rep("\xE2\x94\x80", w - 2) .. "\xE2\x94\x90")
  for i = 1, h - 2 do
    gpu.set(x, y + i, "\xE2\x94\x82")
    gpu.set(x + w - 1, y + i, "\xE2\x94\x82")
  end
  gpu.set(x, y + h - 1, "\xE2\x94\x94" .. string.rep("\xE2\x94\x80", w - 2) .. "\xE2\x94\x98")
  if title then
    setFg(PALETTE.title)
    gpu.set(x + 2, y, " " .. title .. " ")
  end
end

local function drawChrome()
  gpu.setBackground(PALETTE.bg)
  gpu.fill(1, 1, screenW, screenH, " ")

  setFg(PALETTE.title)
  gpu.set(2, 1, "\xE2\x97\x89 OPEN SPACE CONTROL")
  setFg(PALETTE.dim)
  gpu.set(screenW - 10, 1, os.date("%H:%M:%S"))

  setFg(rocketPad and PALETTE.ok or PALETTE.dim)
  gpu.set(2, 2, (rocketPad and "\xE2\x97\x8F" or "\xE2\x97\x8B") .. " ROCKET PAD")
  setFg(PALETTE.ok)
  gpu.set(20, 2, "\xE2\x97\x8F STAR DAR LINK OK")

  box(viewX - 1, viewY - 1, viewW + 2, viewH + 2, "ORBITAL VIEW \xE2\x80\x94 " .. tostring(scene.planetName))
  box(panelX - 1, viewY - 1, PANEL_W + 2, viewH + 2, "TELEMETRY")

  setFg(PALETTE.dim)
  gpu.set(2, screenH - 1, "[WASD] rotate  [E/Z] zoom  [click] select  [t] preview flight")
  gpu.set(2, screenH, "[l] launch (real, confirm x2)  [r] refresh  [esc] quit")
end

--------------------------------------------------------------------------
-- Telemetry panel
--------------------------------------------------------------------------

selectedRef = nil -- initial value (declared earlier, above renderViewport)
local statusMsg, statusUntil = nil, 0

local function drawPanel()
  local x, y = panelX, viewY
  local function line(text, color)
    if y <= viewY + viewH - 1 then
      setFg(color or PALETTE.text)
      gpu.set(x, y, text)
      y = y + 1
    end
  end

  gpu.setBackground(PALETTE.bg)
  gpu.fill(x, viewY, PANEL_W, viewH, " ")

  if selectedRef and selectedRef.kind == "moon" then
    line("MOON / SATELLITE", PALETTE.title)
    line(selectedRef.name)
    line("")
    line("Position: LAYOUT ONLY", PALETTE.dim)
    line("(no real orbital coords", PALETTE.dim)
    line(" in this API)", PALETTE.dim)
  elseif selectedRef and selectedRef.kind == "pad" then
    line("ROCKET LAUNCH PAD", PALETTE.title)
    local s = scene.padStatus
    if s then
      line("Energy:  " .. fmt(s.energy) .. " / " .. fmt(s.energyMax))
      line("Solid fuel: " .. fmt(s.solidFuel) .. "/" .. fmt(s.solidFuelMax))
      if s.fuelTanks then
        for i, t in ipairs(s.fuelTanks) do
          line(string.format(" tank%d %s %s/%s", i, tostring(t.fluid), fmt(t.fill), fmt(t.max)))
        end
      end
      line("Can launch: " .. fmt(s.canLaunch), s.canLaunch and PALETTE.ok or PALETTE.bad)
      if s.stages then
        line("Stages: " .. fmt(s.stages))
        line("Mass: " .. fmt(s.launchMass))
        line("Height: " .. fmt(s.height))
      else
        line("Rocket: " .. tostring(s.rocketError), PALETTE.dim)
      end
      line("Dest: " .. tostring(s.destination or s.destinationError), PALETTE.text)
    else
      line("(no data)", PALETTE.dim)
    end
  elseif selectedRef and selectedRef.kind == "planet" then
    line("PLANET", PALETTE.title)
    line(tostring(scene.planetName))
    local st = scene.planetStats
    if st then
      line("")
      line("Star: " .. fmt(st.star))
      line("Landable: " .. fmt(st.landable))
      line("Radius: " .. fmt(st.radiusKm) .. " km")
      line("Gravity: " .. fmt(st.surfaceGravity) .. " m/s^2")
      line("Axial tilt: " .. fmt(st.axialTilt) .. " deg")
      line("Rot. period: " .. fmt(st.rotationalPeriod) .. " t")
      line("Orb. period: " .. fmt(st.orbitalPeriod) .. " d")
      line("Sun power: " .. fmt(st.sunPowerPct) .. " %")
    end
  else
    line("PLANET", PALETTE.title)
    line(tostring(scene.planetName))
    line("")
    line("MOONS (" .. #scene.moons .. ")", PALETTE.title)
    for _, m in ipairs(scene.moons) do line("  o " .. m.name, PALETTE.moon) end
    line("")
    line("ROCKET PAD", PALETTE.title)
    line(rocketPad and "connected" or "not found", rocketPad and PALETTE.ok or PALETTE.dim)
  end

  if flight then
    line("")
    line("FLIGHT: " .. (flight.real and "LAUNCHED (path simulated)" or "PREVIEW (simulated)"),
      PALETTE.flightTip)
  end

  if statusMsg and os.clock() < statusUntil then
    line("")
    line(statusMsg, PALETTE.flightTip)
  end
end

local function setStatus(msg, seconds)
  statusMsg, statusUntil = msg, os.clock() + (seconds or 3)
end

--------------------------------------------------------------------------
-- Interaction
--------------------------------------------------------------------------

local function trySelect(x, y)
  local best, bestDist
  for _, obj in ipairs(scene.screenObjects) do
    if not obj.isBody then
      local ox, oy = viewX + obj.sx - 1, viewY + obj.sy - 1
      local dist = math.abs(ox - x) + math.abs(oy - y)
      if not bestDist or dist < bestDist then bestDist, best = dist, obj end
    end
  end
  if best and bestDist <= 2 then
    selectedRef = best
    return
  end
  -- fall back: did the click land on a rendered planet pixel?
  local ly, lx = y - viewY + 1, x - viewX + 1
  if scene.planetPixels and scene.planetPixels[ly .. ":" .. lx] then
    selectedRef = { kind = "planet", name = scene.planetName }
  else
    selectedRef = nil
  end
end

--------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------

local function redraw()
  drawChrome()
  renderViewport()
  drawPanel()
end

refreshData()
redraw()

local running = true
local lastDrag = nil
local pendingLaunch = false
local pendingLaunchUntil = 0

while running do
  local e = { event.pull(flight and 0.1 or 0.5) }
  local ename = e[1]
  local needsRedraw = (ename == nil) and flight ~= nil -- timeout tick while animating

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
      camera.distance = math.max(14, camera.distance - 2); needsRedraw = true
    elseif code == keyboard.keys.z then
      camera.distance = math.min(80, camera.distance + 2); needsRedraw = true
    elseif code == keyboard.keys.r then
      refreshData(); needsRedraw = true
    elseif code == keyboard.keys.t then
      startFlight(false)
      setStatus("Preview flight started (simulated path).")
      needsRedraw = true
    elseif code == keyboard.keys.l then
      if not rocketPad then
        setStatus("No rocket pad connected.")
      elseif pendingLaunch and os.clock() < pendingLaunchUntil then
        pendingLaunch = false
        local ok, err = pcall(function() return rocketPad.launch() end)
        if ok then
          setStatus("Launch command sent.")
          startFlight(true)
        else
          setStatus("Launch failed: " .. tostring(err))
        end
        refreshData()
      else
        pendingLaunch = true
        pendingLaunchUntil = os.clock() + 4
        setStatus("Press L again within 4s to CONFIRM real launch.", 4)
      end
      needsRedraw = true
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
    camera.distance = math.max(14, math.min(80, camera.distance - dir * 2))
    needsRedraw = true
  end

  if ename ~= "drag" then lastDrag = nil end
  if flight then needsRedraw = true end

  if needsRedraw then redraw() end
end

term.clear()
print("Space Control closed.")

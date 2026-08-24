-- space_control.lua
-- OpenOS control program for HBM's Nuclear Tech Mod: Space (NTM-Space)
-- Implements the full "ntm_stardar" OpenComputers API:
--   getCurrentPlanet()
--   getPlanetStats(name)
--   getSatellites(name)
--
-- Requires: an OC cable connected directly to the StarDar's CORE block
-- (the block with metadata >= 12 -- check with F3, NOT the legs/rack blocks).
--
-- Run with: space_control

local component = require("component")
local event = require("event")
local term = require("term")
local gpu = component.gpu

--------------------------------------------------------------------
-- Component discovery
--------------------------------------------------------------------

local function findStardar()
  if not component.isAvailable("ntm_stardar") then
    return nil, "No 'ntm_stardar' component found.\n" ..
      "Make sure the OC cable is connected directly to the StarDar's\n" ..
      "CORE block (metadata >= 12), not to the legs/rack/platform blocks."
  end
  return component.ntm_stardar
end

local stardar, err = findStardar()
if not stardar then
  io.stderr:write(err .. "\n")
  return
end

--------------------------------------------------------------------
-- API wrappers (with pcall, since some calls can error/yield)
--------------------------------------------------------------------

-- getCurrentPlanet() -> string
local function getCurrentPlanet()
  local ok, name = pcall(function() return stardar.getCurrentPlanet() end)
  if not ok then return nil, name end
  return name
end

-- getPlanetStats(name) -> table or nil, error
local function getPlanetStats(name)
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(function()
    return stardar.getPlanetStats(name)
  end)
  if not ok then return nil, a end
  if a == nil then return nil, b or "No body with that name found." end

  return {
    name              = a,
    parent            = b,
    star              = c,
    tidallyLockedTo   = d,
    axialTilt         = e,
    landable          = f,
    massKg            = g,
    processingLevel   = h,
    radiusKm          = i,
    semiMajorAxisKm   = j,
    sunPowerPct       = k,
    surfaceGravity    = l,
    rotationalPeriod  = m,
    orbitalPeriod     = n,
  }
end

-- getSatellites(name) -> table of names, or nil, error
local function getSatellites(name)
  local ok, first, rest = pcall(function()
    return { stardar.getSatellites(name) }
  end)
  if not ok then return nil, first end

  local result = first
  if result[1] == nil then
    return nil, result[2] or "No body with that name found."
  end
  return result
end

--------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------

local w, h = gpu.getResolution()

local function fmt(v)
  if v == nil then return "N/A" end
  if type(v) == "boolean" then return v and "yes" or "no" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.3f", v)
  end
  return tostring(v)
end

local function drawHeader(title)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
  gpu.set(2, 1, ("=" ):rep(w - 2))
  gpu.set(2, 2, title)
  gpu.set(2, 3, ("=" ):rep(w - 2))
end

local function printLine(x, y, label, value)
  gpu.set(x, y, string.format("%-22s %s", label, value))
end

--------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------

local function showPlanet(name)
  local stats, statErr = getPlanetStats(name)
  if not stats then
    drawHeader("STAR DAR // ERROR")
    gpu.set(2, 5, "Could not fetch stats for '" .. name .. "':")
    gpu.set(2, 6, tostring(statErr))
    gpu.set(2, h - 1, "[Enter] back")
    return
  end

  drawHeader("STAR DAR // " .. stats.name)

  local y = 5
  printLine(2, y, "Parent body:", fmt(stats.parent)); y = y + 1
  printLine(2, y, "Star:", fmt(stats.star)); y = y + 1
  printLine(2, y, "Tidally locked to:", fmt(stats.tidallyLockedTo)); y = y + 1
  printLine(2, y, "Landable:", fmt(stats.landable)); y = y + 2

  printLine(2, y, "Axial tilt (deg):", fmt(stats.axialTilt)); y = y + 1
  printLine(2, y, "Mass (kg):", fmt(stats.massKg)); y = y + 1
  printLine(2, y, "Radius (km):", fmt(stats.radiusKm)); y = y + 1
  printLine(2, y, "Semi-major axis (km):", fmt(stats.semiMajorAxisKm)); y = y + 1
  printLine(2, y, "Surface gravity (m/s^2):", fmt(stats.surfaceGravity)); y = y + 1
  printLine(2, y, "Sun power (%):", fmt(stats.sunPowerPct)); y = y + 1
  printLine(2, y, "Rotational period (t):", fmt(stats.rotationalPeriod)); y = y + 1
  printLine(2, y, "Orbital period (days):", fmt(stats.orbitalPeriod)); y = y + 1
  printLine(2, y, "Processing level req.:", fmt(stats.processingLevel)); y = y + 2

  local sats, satErr = getSatellites(name)
  gpu.set(2, y, "Satellites:")
  y = y + 1
  if sats then
    for _, sname in ipairs(sats) do
      gpu.set(4, y, "- " .. tostring(sname))
      y = y + 1
      if y > h - 3 then
        gpu.set(4, y, "...")
        break
      end
    end
  else
    gpu.set(4, y, "(" .. tostring(satErr) .. ")")
  end

  gpu.set(2, h - 1, "[s] satellites view   [/] lookup planet   [q] quit")
end

local function showSatellitesOf(name)
  drawHeader("STAR DAR // SATELLITES OF " .. name)
  local sats, satErr = getSatellites(name)
  if not sats then
    gpu.set(2, 5, "Error: " .. tostring(satErr))
  else
    local y = 5
    for idx, sname in ipairs(sats) do
      gpu.set(2, y, idx .. ". " .. tostring(sname))
      y = y + 1
    end
    if #sats == 0 then
      gpu.set(2, 5, "(no satellites found)")
    end
  end
  gpu.set(2, h - 1, "[Enter] back")
end

local function promptPlanetName(default)
  gpu.set(2, h - 1, ("Enter planet name: "))
  term.setCursor(21, h - 1)
  gpu.setForeground(0x00FF00)
  local input = term.read({ history = {} })
  gpu.setForeground(0xFFFFFF)
  if not input then return default end
  input = input:gsub("%s+$", "")
  if input == "" then return default end
  return input
end

--------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------

local function main()
  local current, curErr = getCurrentPlanet()
  if not current then
    io.stderr:write("Failed to read current planet: " .. tostring(curErr) .. "\n")
    return
  end

  local viewing = current
  local mode = "planet" -- "planet" | "satellites"

  while true do
    term.clear()
    if mode == "planet" then
      showPlanet(viewing)
    else
      showSatellitesOf(viewing)
    end

    local _, _, char, code = event.pull("key_down")

    if mode == "satellites" then
      -- any key returns to planet view
      mode = "planet"
    else
      local key = string.char(char):lower()
      if key == "q" then
        break
      elseif key == "s" then
        mode = "satellites"
      elseif key == "/" then
        term.clear()
        showPlanet(viewing)
        local name = promptPlanetName(viewing)
        viewing = name
      end
    end
  end

  term.clear()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  print("StarDar control closed.")
end

main()
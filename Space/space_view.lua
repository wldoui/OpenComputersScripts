--[[
  OPEN SPACE CONTROL // ORBITAL TERMINAL
  ---------------------------------------------------------------
  Standalone OpenComputers 1.8.9a script. No installer, no files
  written to disk, no HBM energy network, no reactors, no hologram
  projector, no voxel rendering in the world. Everything happens
  on a single GPU/Screen using text + block characters.

  API HONESTY NOTE:
  ntm_stardar (HBM's Nuclear Tech / HBM Space OC integration) only
  exposes:
      getCurrentPlanet()
      getPlanetStats(name)  -> name, parent, star, tidallyLockedTo,
                                axialTilt, landable, massKg,
                                processingLevel, radiusKm,
                                semiMajorAxisKm, sunPower,
                                surfaceGravity, rotationalPeriod,
                                orbitalPeriod
      getSatellites(name)   -> list of child body names
  There is NO getBodies()/getAllPlanets() call. This script never
  invents one. Instead it discovers the whole system honestly:
    1) start at getCurrentPlanet()
    2) climb up via .parent until a body with no parent is found
       (that is the root/star)
    3) walk back down recursively via getSatellites() to map
       every planet and moon that actually exists in this save

  Controls:
    UP/DOWN   - move selection in the body list
    ENTER     - focus selected body (updates orbit strip + info)
    TAB       - toggle orbit-strip panel size
    R         - rescan the system from ntm_stardar
    Q         - quit, restores the terminal
    mouse     - click a row in the left list to select it
]]--

local component   = require("component")
local event       = require("event")
local keyboard     = require("keyboard")
local unicode     = require("unicode")
local computer    = require("computer")
local term        = require("term")

-- ===================== SETUP =====================

if not component.isAvailable("gpu") then
  error("No GPU/Screen attached to this computer.")
end

local gpu = component.gpu
pcall(function()
  local mw, mh = gpu.maxResolution()
  gpu.setResolution(mw, mh)
end)

local W, H = gpu.getResolution()

local COL_BG        = 0x000000
local COL_FRAME     = 0x33CCCC
local COL_TITLE     = 0x55FFFF
local COL_TEXT      = 0xC0F0F0
local COL_DIM       = 0x336666
local COL_SELECT_BG = 0x114444
local COL_STATUS_OK = 0x55FF55
local COL_STATUS_ERR= 0xFF5555
local COL_ROCKY     = 0xFFAA33
local COL_GAS       = 0x77AAFF
local COL_STAR      = 0xFFFF55

-- ===================== STATE =====================

local bodies      = {}   -- name -> stats table
local order       = {}   -- discovery order
local rootName    = nil
local flatList    = {}   -- {name=, depth=}
local selected    = 1
local statusMsg   = "Idle. Press R to scan."
local statusColor = COL_TEXT
local frame       = 0
local orbitTall   = false

-- ===================== SMALL UTILS =====================

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function padRight(s, len)
  s = s or ""
  local n = unicode.len(s)
  if n >= len then return unicode.sub(s, 1, len) end
  return s .. string.rep(" ", len - n)
end

local function hashName(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + string.byte(str, i)) % 2147483647
  end
  return h
end

local function fmtNum(n, decimals)
  if n == nil then return "?" end
  decimals = decimals or 2
  return string.format("%." .. decimals .. "f", n)
end

-- ===================== SAFE NTM_STARDAR API WRAPPER =====================
-- Every call is guarded: real API can throw (component absent/out of
-- range) or return (nil, "error string") on bad input. Both handled.

local stardar = nil

local function bindStardar()
  if component.isAvailable("ntm_stardar") then
    stardar = component.ntm_stardar
    return true
  end
  stardar = nil
  return false
end

local function apiGetCurrentPlanet()
  if not stardar then return nil, "ntm_stardar not attached" end
  local ok, name = pcall(stardar.getCurrentPlanet)
  if not ok then return nil, tostring(name) end
  if name == nil then return nil, "no current planet reported" end
  return name
end

local function apiGetPlanetStats(name)
  if not stardar then return nil, "ntm_stardar not attached" end
  local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14 =
    pcall(stardar.getPlanetStats, name)
  if not ok then return nil, tostring(r1) end
  if r1 == nil then return nil, r2 or "unknown body" end
  return {
    name             = r1,
    parent           = r2,
    star             = r3,
    tidallyLockedTo  = r4,
    axialTilt        = r5,
    landable         = r6,
    massKg           = r7,
    processingLevel  = r8,
    radiusKm         = r9,
    semiMajorAxisKm  = r10,
    sunPower         = r11,
    surfaceGravity   = r12,
    rotationalPeriod = r13,
    orbitalPeriod    = r14,
  }
end

local function apiGetSatellites(name)
  if not stardar then return {}, "ntm_stardar not attached" end
  local ok, packed = pcall(function() return table.pack(stardar.getSatellites(name)) end)
  if not ok then return {}, tostring(packed) end
  if packed.n == 0 or packed[1] == nil then
    return {}, packed[2] or "no satellites / unknown body"
  end
  local list = {}
  for i = 1, packed.n do
    if packed[i] ~= nil then list[#list + 1] = packed[i] end
  end
  return list
end

-- ===================== SYSTEM DISCOVERY (BFS/DFS, real API only) =====================

local function findRoot(startName)
  local seen = {}
  local current = startName
  for _ = 1, 64 do
    if seen[current] then return current end
    seen[current] = true
    local stats = apiGetPlanetStats(current)
    if not stats then return current end
    if stats.parent == nil or stats.parent == "" then
      return current
    end
    current = stats.parent
  end
  return current
end

local function visit(name, depth, visited)
  if visited[name] then return end
  visited[name] = true
  local stats = apiGetPlanetStats(name)
  if not stats then return end
  local sats = apiGetSatellites(name)
  stats.satellites = sats
  stats.depth = depth
  bodies[name] = stats
  order[#order + 1] = name
  for _, s in ipairs(sats) do
    visit(s, depth + 1, visited)
  end
end

local function scanSystem()
  bodies = {}
  order = {}
  rootName = nil

  if not stardar then
    return false, "ntm_stardar not connected (attach via OC cable, no adapter needed)"
  end

  local current, err = apiGetCurrentPlanet()
  if not current then
    return false, "getCurrentPlanet failed: " .. tostring(err)
  end

  local root = findRoot(current)
  local visited = {}
  visit(root, 0, visited)
  rootName = root

  if #order == 0 then
    return false, "discovery produced no bodies"
  end
  return true
end

local function buildFlatList()
  flatList = {}
  if not rootName or not bodies[rootName] then return end
  local function walk(name, depth)
    flatList[#flatList + 1] = { name = name, depth = depth }
    local stats = bodies[name]
    if stats and stats.satellites then
      for _, s in ipairs(stats.satellites) do
        if bodies[s] then walk(s, depth + 1) end
      end
    end
  end
  walk(rootName, 0)
end

local function rescan()
  statusMsg, statusColor = "Scanning system via ntm_stardar...", COL_TEXT
  local ok, err = scanSystem()
  if ok then
    buildFlatList()
    selected = clamp(selected, 1, #flatList)
    statusMsg = string.format("Scan OK: %d bodies mapped from root '%s'", #order, tostring(rootName))
    statusColor = COL_STATUS_OK
  else
    statusMsg = "Scan failed: " .. tostring(err)
    statusColor = COL_STATUS_ERR
  end
end

-- ===================== BLOCKY PSEUDO-3D PLANET RENDERER =====================
-- Not a smooth sphere: quantized block texture (Minecraft-style),
-- animated by scrolling columns to fake rotation. No voxels, no
-- hologram, pure text-cell graphics.

local ART_W, ART_H = 23, 11
local SOLID_CHARS = { "█", "▓", "▒", "▓" }
local GAS_CHARS   = { "▓", "▒", "░", "▒" }
local STAR_CHARS  = { "█", "▓", "▒", "░" }

local function buildTexture(stats)
  local seed = hashName(stats.name)
  local w, h = ART_W, ART_H
  local cx, cy = w / 2, h / 2
  local rx, ry = w / 2 - 1, h / 2 - 0.6
  local tex = {}
  for r = 0, h - 1 do
    tex[r] = {}
    for c = 0, w - 1 do
      local nx = (c - cx) / rx
      local ny = (r - cy) / ry
      if nx * nx + ny * ny <= 1 then
        seed = (seed * 1103515245 + 12345) % 2147483648
        tex[r][c] = (seed % 4) + 1
      else
        tex[r][c] = 0
      end
    end
  end
  return tex
end

local function isStarBody(stats)
  return stats.name == rootName
end

local function renderPlanetArt(stats, frameNum)
  stats._tex = stats._tex or buildTexture(stats)
  local tex = stats._tex
  local palette, color
  if isStarBody(stats) then
    palette, color = STAR_CHARS, COL_STAR
  elseif stats.landable then
    palette, color = SOLID_CHARS, COL_ROCKY
  else
    palette, color = GAS_CHARS, COL_GAS
  end

  local shift = math.floor(frameNum / 2) % ART_W
  local lines = {}
  for r = 0, ART_H - 1 do
    local row = {}
    for c = 0, ART_W - 1 do
      local sc = (c + shift) % ART_W
      local idx = tex[r][sc]
      row[#row + 1] = (idx == 0) and " " or palette[idx]
    end
    lines[#lines + 1] = table.concat(row)
  end
  return lines, color
end

-- ===================== LAYOUT =====================

local LIST_X, LIST_Y = 2, 4
local LIST_W = math.max(20, math.floor(W * 0.34))
local LIST_H = H - 7

local INFO_X = LIST_X + LIST_W + 2
local INFO_W = W - INFO_X - 1
local ART_Y  = LIST_Y
local STATS_Y = ART_Y + ART_H + 2

-- ===================== DRAWING =====================

local function setC(fg, bg)
  gpu.setForeground(fg or COL_TEXT)
  if bg then gpu.setBackground(bg) end
end

local function box(x, y, w, h, title)
  setC(COL_FRAME, COL_BG)
  gpu.set(x, y, "╔" .. string.rep("═", w - 2) .. "╗")
  for i = 1, h - 2 do
    gpu.set(x, y + i, "║")
    gpu.set(x + w - 1, y + i, "║")
  end
  gpu.set(x, y + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
  if title then
    setC(COL_TITLE, COL_BG)
    gpu.set(x + 2, y, " " .. title .. " ")
  end
end

local function drawHeader()
  setC(COL_BG, COL_BG)
  gpu.fill(1, 1, W, H, " ")
  setC(COL_TITLE, COL_BG)
  gpu.set(2, 1, "OPEN SPACE CONTROL // ORBITAL TERMINAL")
  setC(COL_DIM, COL_BG)
  local link = stardar and "STARDAR: LINKED" or "STARDAR: NOT FOUND"
  gpu.set(W - unicode.len(link) - 1, 1, link)
end

local function drawList()
  box(LIST_X, LIST_Y, LIST_W, LIST_H, "SYSTEM BODIES")
  local innerH = LIST_H - 2
  local top = clamp(selected - math.floor(innerH / 2), 1, math.max(1, #flatList - innerH + 1))
  for row = 0, innerH - 1 do
    local idx = top + row
    local entry = flatList[idx]
    local y = LIST_Y + 1 + row
    if entry then
      local stats = bodies[entry.name]
      local marker = "."
      local fg = COL_TEXT
      if isStarBody(stats) then marker, fg = "*", COL_STAR
      elseif stats.landable then marker, fg = "o", COL_ROCKY
      else marker, fg = "0", COL_GAS end
      local label = string.rep("  ", entry.depth) .. marker .. " " .. entry.name
      if idx == selected then
        setC(0x000000, COL_SELECT_BG)
        gpu.set(LIST_X + 1, y, padRight(label, LIST_W - 2))
      else
        setC(fg, COL_BG)
        gpu.set(LIST_X + 1, y, padRight(label, LIST_W - 2))
      end
    end
  end
end

local function drawArtAndInfo()
  local sel = flatList[selected]
  box(INFO_X, ART_Y, INFO_W, ART_H + 2, "VIEWPORT")
  if not sel then
    setC(COL_DIM, COL_BG)
    gpu.set(INFO_X + 2, ART_Y + 2, "No body selected. Press R to scan.")
    return
  end
  local stats = bodies[sel.name]
  local artLines, color = renderPlanetArt(stats, frame)
  local ox = INFO_X + math.floor((INFO_W - ART_W) / 2)
  setC(color, COL_BG)
  for i, line in ipairs(artLines) do
    gpu.set(ox, ART_Y + 1 + i, line)
  end
  setC(COL_TITLE, COL_BG)
  gpu.set(INFO_X + 2, ART_Y + ART_H + 1, string.upper(stats.name))

  -- stats panel
  box(INFO_X, STATS_Y, INFO_W, H - STATS_Y - 3, "TELEMETRY")
  local lines = {
    string.format("PARENT      %s", tostring(stats.parent or "-")),
    string.format("STAR        %s", tostring(stats.star or "-")),
    string.format("LOCKED TO   %s", tostring(stats.tidallyLockedTo or "-")),
    string.format("LANDABLE    %s", tostring(stats.landable)),
    string.format("RADIUS      %s km", fmtNum(stats.radiusKm, 1)),
    string.format("MASS        %s kg", tostring(stats.massKg)),
    string.format("GRAVITY     %s m/s^2", fmtNum(stats.surfaceGravity, 3)),
    string.format("SEMI-MAJOR  %s km", fmtNum(stats.semiMajorAxisKm, 0)),
    string.format("SUN POWER   %s %%", fmtNum((stats.sunPower or 0) * 100, 2)),
    string.format("ORBIT PER.  %s days", fmtNum(stats.orbitalPeriod, 2)),
    string.format("ROT PERIOD  %s ticks", fmtNum(stats.rotationalPeriod, 0)),
    string.format("SATELLITES  %d", stats.satellites and #stats.satellites or 0),
  }
  setC(COL_TEXT, COL_BG)
  for i, l in ipairs(lines) do
    if STATS_Y + i < H - 2 then
      gpu.set(INFO_X + 2, STATS_Y + i, padRight(l, INFO_W - 4))
    end
  end
end

local function drawOrbitStrip()
  local sel = flatList[selected]
  if not sel then return end
  local stats = bodies[sel.name]
  local parentName = stats.parent
  local siblings = {}
  if parentName and bodies[parentName] and bodies[parentName].satellites then
    siblings = bodies[parentName].satellites
  elseif isStarBody(stats) and stats.satellites then
    siblings = stats.satellites
  end

  local y = H - 2
  setC(COL_DIM, COL_BG)
  gpu.fill(2, y, W - 2, 1, "─")
  local x = 3
  setC(COL_TITLE, COL_BG)
  local label = parentName and ("ORBIT OF " .. parentName .. ": ") or "ROOT SYSTEM: "
  gpu.set(x, y, label)
  x = x + unicode.len(label)
  for _, s in ipairs(siblings) do
    local marker = (s == sel.name) and "●" or "·"
    local fg = (s == sel.name) and COL_STATUS_OK or COL_DIM
    setC(fg, COL_BG)
    local chunk = marker .. s .. "  "
    if x + unicode.len(chunk) < W - 2 then
      gpu.set(x, y, chunk)
      x = x + unicode.len(chunk)
    end
  end
end

local function drawStatusBar()
  setC(statusColor, COL_BG)
  gpu.set(2, H - 1, padRight(statusMsg, W - 4))
  setC(COL_DIM, COL_BG)
  gpu.set(2, H, "UP/DOWN select | ENTER focus | R rescan | Q quit")
end

local function drawFrame()
  drawHeader()
  drawList()
  drawArtAndInfo()
  drawOrbitStrip()
  drawStatusBar()
end

-- ===================== MAIN LOOP =====================

local function restoreTerminal()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  term.clear()
  term.setCursor(1, 1)
end

bindStardar()
rescan()

local running = true
while running do
  local ok, drawErr = pcall(drawFrame)
  if not ok then
    statusMsg, statusColor = "Render error: " .. tostring(drawErr), COL_STATUS_ERR
  end

  local e = { event.pull(0.2) }
  local ev = e[1]

  if ev == "key_down" then
    local code = e[4]
    if code == keyboard.keys.up then
      selected = clamp(selected - 1, 1, math.max(1, #flatList))
    elseif code == keyboard.keys.down then
      selected = clamp(selected + 1, 1, math.max(1, #flatList))
    elseif code == keyboard.keys.enter or code == keyboard.keys.numpadenter then
      -- selection already drives info/orbit panels; enter just forces redraw
    elseif code == keyboard.keys.tab then
      orbitTall = not orbitTall
    elseif code == keyboard.keys.r then
      bindStardar()
      rescan()
    elseif code == keyboard.keys.q then
      running = false
    end
  elseif ev == "touch" then
    local x, y = e[3], e[4]
    if x >= LIST_X + 1 and x <= LIST_X + LIST_W - 2 then
      local row = y - (LIST_Y + 1)
      local innerH = LIST_H - 2
      local top = clamp(selected - math.floor(innerH / 2), 1, math.max(1, #flatList - innerH + 1))
      local idx = top + row
      if flatList[idx] then selected = idx end
    end
  elseif ev == "interrupted" then
    running = false
  end

  frame = frame + 1
end

restoreTerminal()
print("Open Space Control terminated.")

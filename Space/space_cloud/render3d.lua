-- render3d.lua
-- Minimal pseudo-3D engine for OpenComputers text screens:
-- orbit camera, perspective projection, and a blocky (Minecraft-style,
-- cube-not-sphere) planet mesh generator with simple directional shading.
-- Save to: /lib/render3d.lua

local Vector3 = require("vector3")

local Render3D = {}

--------------------------------------------------------------------------
-- Camera: an orbit camera that always looks at `target` from `distance`
-- away, controlled by yaw/pitch (radians).
--------------------------------------------------------------------------

local Camera = {}
Camera.__index = Camera
Render3D.Camera = Camera

function Camera.new()
  return setmetatable({
    yaw = 0.6,
    pitch = 0.5,
    distance = 26,
    target = Vector3.new(0, 0, 0),
    fov = 1.6,        -- projection scale
  }, Camera)
end

function Camera:eye()
  local x = self.distance * math.cos(self.pitch) * math.sin(self.yaw)
  local y = self.distance * math.sin(self.pitch)
  local z = self.distance * math.cos(self.pitch) * math.cos(self.yaw)
  return self.target + Vector3.new(x, y, z)
end

-- Projects a world-space point to screen space (character coordinates).
-- Returns sx, sy, depth  or  nil if the point is behind the camera.
function Camera:project(world, screenW, screenH)
  local eye = self:eye()
  local forward = (self.target - eye):normalize()
  local worldUp = Vector3.new(0, 1, 0)
  local right = forward:cross(worldUp):normalize()
  local up = right:cross(forward):normalize()

  local rel = world - eye
  local cx = rel:dot(right)
  local cy = rel:dot(up)
  local cz = rel:dot(forward)

  if cz <= 0.1 then return nil end

  local scale = self.fov * screenH
  -- terminal characters are roughly twice as tall as they are wide,
  -- so the vertical axis is compressed to keep things looking round.
  local sx = screenW / 2 + (cx / cz) * scale
  local sy = screenH / 2 - (cy / cz) * scale * 0.5

  return sx, sy, cz
end

--------------------------------------------------------------------------
-- Blocky planet mesh
--------------------------------------------------------------------------

-- Generates the surface cells of a cube-shaped (Minecraft-style) planet.
-- radius: half the cube's side length, in local render units.
-- res: subdivisions per face edge (higher = more detailed, more cost).
-- Returns a list of { pos = Vector3, normal = Vector3 } in local space.
function Render3D.generateBlockyPlanet(radius, res)
  local cells = {}
  local step = (2 * radius) / res

  local faces = {
    { normal = Vector3.new(0, 0, 1),  axis = "z", sign = 1 },
    { normal = Vector3.new(0, 0, -1), axis = "z", sign = -1 },
    { normal = Vector3.new(1, 0, 0),  axis = "x", sign = 1 },
    { normal = Vector3.new(-1, 0, 0), axis = "x", sign = -1 },
    { normal = Vector3.new(0, 1, 0),  axis = "y", sign = 1 },
    { normal = Vector3.new(0, -1, 0), axis = "y", sign = -1 },
  }

  for _, face in ipairs(faces) do
    for i = 0, res - 1 do
      for j = 0, res - 1 do
        local u = -radius + step * (i + 0.5)
        local v = -radius + step * (j + 0.5)
        local pos
        if face.axis == "z" then
          pos = Vector3.new(u, v, radius * face.sign)
        elseif face.axis == "x" then
          pos = Vector3.new(radius * face.sign, u, v)
        else
          pos = Vector3.new(u, radius * face.sign, v)
        end
        cells[#cells + 1] = { pos = pos, normal = face.normal }
      end
    end
  end

  return cells
end

--------------------------------------------------------------------------
-- Shading
--------------------------------------------------------------------------

local SHADE_RAMP = { " ", ".", ":", "-", "=", "+", "*", "#", "%", "@" }

-- brightness in [0,1] -> ASCII shading character
function Render3D.shadeChar(brightness)
  if brightness < 0 then brightness = 0 end
  if brightness > 1 then brightness = 1 end
  local idx = math.floor(brightness * (#SHADE_RAMP - 1)) + 1
  return SHADE_RAMP[idx]
end

-- Decorative colour gradient for the planet surface: dark teal -> lime ->
-- near-white highlight. Purely visual, has no bearing on real data.
local COLOR_STOPS = {
  { 0.00, 0x0A2A1E },
  { 0.25, 0x1F6B3A },
  { 0.55, 0x4FB84A },
  { 0.80, 0xB6E24D },
  { 1.00, 0xF2FFCC },
}

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpColor(c1, c2, t)
  local r1, g1, b1 = (c1 >> 16) & 0xFF, (c1 >> 8) & 0xFF, c1 & 0xFF
  local r2, g2, b2 = (c2 >> 16) & 0xFF, (c2 >> 8) & 0xFF, c2 & 0xFF
  local r = math.floor(lerp(r1, r2, t) + 0.5)
  local g = math.floor(lerp(g1, g2, t) + 0.5)
  local b = math.floor(lerp(b1, b2, t) + 0.5)
  return (r << 16) | (g << 8) | b
end

function Render3D.colorForBrightness(brightness)
  if brightness < 0 then brightness = 0 end
  if brightness > 1 then brightness = 1 end
  for i = 1, #COLOR_STOPS - 1 do
    local a, b = COLOR_STOPS[i], COLOR_STOPS[i + 1]
    if brightness >= a[1] and brightness <= b[1] then
      local t = (brightness - a[1]) / (b[1] - a[1])
      return lerpColor(a[2], b[2], t)
    end
  end
  return COLOR_STOPS[#COLOR_STOPS][2]
end

--------------------------------------------------------------------------
-- Decorative helpers: orbit rings and a static starfield.
-- Both are explicitly visual layout, not measured positions.
--------------------------------------------------------------------------

-- Returns a list of Vector3 points forming a ring in the XZ plane.
function Render3D.ringPoints(radius, segments, y)
  y = y or 0
  local pts = {}
  for i = 0, segments - 1 do
    local a = (i / segments) * 2 * math.pi
    pts[#pts + 1] = Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
  end
  return pts
end

-- Deterministic starfield: same stars every run (seeded), for a stable sky.
function Render3D.starfield(count, radius, seed)
  local rng = {}
  local state = seed or 1337
  local function rand()
    -- simple LCG so results don't depend on the host's math.random state
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end

  local pts = {}
  for _ = 1, count do
    local theta = rand() * 2 * math.pi
    local phi = math.acos(2 * rand() - 1)
    local x = radius * math.sin(phi) * math.cos(theta)
    local y = radius * math.cos(phi)
    local z = radius * math.sin(phi) * math.sin(theta)
    pts[#pts + 1] = Vector3.new(x, y, z)
  end
  return pts
end

return Render3D

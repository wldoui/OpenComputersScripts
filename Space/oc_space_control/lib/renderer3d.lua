-- ==================================================================
-- lib/renderer3d.lua
-- The actual "3D on a 2D text screen" engine. No hologram, no world
-- voxels -- everything here is characters drawn through gpu.set() by
-- whatever calls this module (see apps/space.lua / lib/gui.lua).
--
-- This module NEVER touches gpu directly. It returns a list of draw
-- commands: { x, y, char, fg } so the GUI layer decides how/when to
-- flush them to the screen (double buffering, dirty rects, etc).
-- ==================================================================

local Vector3 = require("vector3")

local Renderer3D = {}

-- Shading ramp from dark to bright, used for blocky-planet lighting.
local SHADE_RAMP = { " ", ".", ":", "*", "o", "O", "#", "@" }

local function shadeChar(brightness)
  -- brightness expected in [0, 1]
  if brightness < 0 then brightness = 0 end
  if brightness > 1 then brightness = 1 end
  local idx = math.floor(brightness * (#SHADE_RAMP - 1)) + 1
  return SHADE_RAMP[idx]
end

-- ------------------------------------------------------------------
-- Blocky planet mesh generation
-- ------------------------------------------------------------------
-- Builds a subdivided cube: 6 faces, each an NxN grid of quads. Each
-- quad center + face normal is what we actually render as one
-- character cell -- this IS the "blocky" look, not a smoothed sphere.
--
-- subdivisions: how many quads per face edge (e.g. 4 -> 4x4 grid per
-- face = 96 quads total). Keep this small (3-6) for OpenComputers
-- performance; each quad is one render + depth-sort entry per frame.
function Renderer3D.buildBlockyPlanet(radius, subdivisions)
  subdivisions = subdivisions or 4
  local quads = {}

  -- Six face definitions: origin corner + two edge vectors on the
  -- cube surface (unit cube, scaled by radius after normalize-ish
  -- projection so the "planet" bulges slightly like Minecraft
  -- terrain rather than being a perfect box -- but kept blocky by
  -- NOT fully normalizing to a sphere, only lightly rounding).
  local faces = {
    { normal = Vector3.new(0, 0, -1), u = Vector3.new(1, 0, 0), v = Vector3.new(0, 1, 0), origin = Vector3.new(-1, -1, -1) },
    { normal = Vector3.new(0, 0, 1),  u = Vector3.new(1, 0, 0), v = Vector3.new(0, 1, 0), origin = Vector3.new(-1, -1, 1) },
    { normal = Vector3.new(-1, 0, 0), u = Vector3.new(0, 0, 1), v = Vector3.new(0, 1, 0), origin = Vector3.new(-1, -1, -1) },
    { normal = Vector3.new(1, 0, 0),  u = Vector3.new(0, 0, 1), v = Vector3.new(0, 1, 0), origin = Vector3.new(1, -1, -1) },
    { normal = Vector3.new(0, -1, 0), u = Vector3.new(1, 0, 0), v = Vector3.new(0, 0, 1), origin = Vector3.new(-1, -1, -1) },
    { normal = Vector3.new(0, 1, 0),  u = Vector3.new(1, 0, 0), v = Vector3.new(0, 0, 1), origin = Vector3.new(-1, 1, -1) },
  }

  local BULGE = 0.25 -- 0 = perfect cube, 1 = perfect sphere; low = blocky-but-round like Minecraft planets

  for _, face in ipairs(faces) do
    for i = 0, subdivisions - 1 do
      for j = 0, subdivisions - 1 do
        local fu = (i + 0.5) / subdivisions * 2 -- 0..2
        local fv = (j + 0.5) / subdivisions * 2

        local p = face.origin + (face.u * fu) + (face.v * fv)
        -- lightly round the cube toward a sphere so it doesn't read
        -- as a plain box, while keeping the blocky facets visible
        local rounded = p:normalized()
        local blended = Vector3.new(
          p.x * (1 - BULGE) + rounded.x * BULGE,
          p.y * (1 - BULGE) + rounded.y * BULGE,
          p.z * (1 - BULGE) + rounded.z * BULGE
        )

        table.insert(quads, {
          position = blended * radius,
          normal = face.normal,
        })
      end
    end
  end

  return quads
end

-- ------------------------------------------------------------------
-- Scene rendering
-- ------------------------------------------------------------------
-- lightDir: Vector3, direction the "sun" shines FROM (normalized)
-- Returns an array of draw commands sorted back-to-front (so nearer
-- fragments overwrite farther ones when the caller blits them).
function Renderer3D.renderBlockyPlanet(quads, worldOffset, camera, screenWidth, screenHeight, lightDir)
  local commands = {}

  for _, quad in ipairs(quads) do
    local worldPos = quad.position + worldOffset
    local camPoint = camera:toCameraSpace(worldPos)
    local sx, sy, depth = camera:project(camPoint, screenWidth, screenHeight)

    if sx and sy and sx >= 0 and sx < screenWidth and sy >= 0 and sy < screenHeight then
      local brightness = quad.normal:dot(lightDir)
      if brightness < 0.08 then brightness = 0.08 end -- ambient floor, nothing fully black
      table.insert(commands, {
        x = sx, y = sy,
        char = shadeChar(brightness),
        depth = depth,
      })
    end
  end

  table.sort(commands, function(a, b) return a.depth > b.depth end)
  return commands
end

-- Renders a single point-object (rocket, satellite, station marker)
-- and returns its screen position + whether it's visible, so the
-- caller can also draw a label/selection box next to it.
function Renderer3D.projectMarker(worldPos, camera, screenWidth, screenHeight)
  local camPoint = camera:toCameraSpace(worldPos)
  local sx, sy, depth = camera:project(camPoint, screenWidth, screenHeight)
  if not sx then return nil end
  if sx < 0 or sx >= screenWidth or sy < 0 or sy >= screenHeight then return nil end
  return { x = sx, y = sy, depth = depth }
end

Renderer3D.shadeChar = shadeChar

return Renderer3D

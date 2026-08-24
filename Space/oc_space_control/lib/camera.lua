-- ==================================================================
-- lib/camera.lua
-- Camera position/rotation/zoom + perspective projection to screen
-- space. Pure math module -- the renderer feeds it viewport size.
-- ==================================================================

local Vector3 = require("vector3")
local Matrix3 = require("matrix3")

local Camera = {}
Camera.__index = Camera

function Camera.new(config)
  config = config or {}
  return setmetatable({
    position = config.position or Vector3.new(0, 0, -40),
    pitch = config.pitch or 0,      -- radians
    yaw = config.yaw or 0,          -- radians
    roll = config.roll or 0,        -- radians
    fov = config.fov or 60,         -- degrees
    zoom = config.zoom or 1.0,
  }, Camera)
end

function Camera:rotate(dPitch, dYaw, dRoll)
  self.pitch = self.pitch + dPitch
  self.yaw = self.yaw + dYaw
  self.roll = self.roll + (dRoll or 0)
  -- clamp pitch so camera can't flip over (gimbal-lock avoidance for
  -- a simple free-look cam)
  local limit = math.pi / 2 - 0.05
  if self.pitch > limit then self.pitch = limit end
  if self.pitch < -limit then self.pitch = -limit end
end

function Camera:moveLocal(dx, dy, dz)
  -- Move relative to current yaw (ground-plane style WASD + QE up/down)
  local sinY, cosY = math.sin(self.yaw), math.cos(self.yaw)
  local forward = Vector3.new(sinY, 0, cosY)
  local right = Vector3.new(cosY, 0, -sinY)
  local up = Vector3.new(0, 1, 0)

  self.position = self.position
    + forward * dz
    + right * dx
    + up * dy
end

function Camera:addZoom(delta)
  self.zoom = self.zoom + delta
  if self.zoom < 0.1 then self.zoom = 0.1 end
  if self.zoom > 10 then self.zoom = 10 end
end

-- Transforms a world-space point into camera space (relative,
-- rotated by the inverse of the camera's orientation).
function Camera:toCameraSpace(worldPoint)
  local relative = worldPoint - self.position
  -- Inverse rotation = negate angles, apply in reverse order.
  local invRot = Matrix3.fromEuler(-self.pitch, -self.yaw, -self.roll)
  return Matrix3.apply(invRot, relative)
end

-- Projects a camera-space point to screen pixel coordinates.
-- Returns screenX, screenY, depth (camera-space Z, for sorting),
-- or nil if the point is behind the camera (cannot be projected).
function Camera:project(camPoint, screenWidth, screenHeight)
  if camPoint.z <= 0.01 then
    return nil
  end

  local fovRad = math.rad(self.fov)
  local scale = (screenHeight / 2) / math.tan(fovRad / 2) * self.zoom

  local sx = (camPoint.x * scale) / camPoint.z
  local sy = (camPoint.y * scale) / camPoint.z

  -- Screen origin top-left, Y grows downward, X grows rightward.
  -- Character cells are roughly 2x taller than wide, so we squash Y
  -- by ~0.5 to keep circles/cubes looking proportionate on a text
  -- terminal.
  local screenX = math.floor(screenWidth / 2 + sx)
  local screenY = math.floor(screenHeight / 2 - sy * 0.5)

  return screenX, screenY, camPoint.z
end

return Camera

-- ==================================================================
-- lib/vector3.lua
-- Minimal Vector3 for the OPEN SPACE CONTROL 3D engine.
-- Pure math, no OpenComputers-specific calls -- testable standalone.
-- ==================================================================

local Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x, y, z)
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vector3)
end

function Vector3.__add(a, b)
  return Vector3.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vector3.__sub(a, b)
  return Vector3.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vector3.__mul(a, s)
  -- supports vector * scalar
  if type(s) == "number" then
    return Vector3.new(a.x * s, a.y * s, a.z * s)
  end
  error("Vector3 can only be multiplied by a scalar")
end

function Vector3:length()
  return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

function Vector3:normalized()
  local len = self:length()
  if len == 0 then return Vector3.new(0, 0, 0) end
  return Vector3.new(self.x / len, self.y / len, self.z / len)
end

function Vector3:dot(other)
  return self.x * other.x + self.y * other.y + self.z * other.z
end

function Vector3:cross(other)
  return Vector3.new(
    self.y * other.z - self.z * other.y,
    self.z * other.x - self.x * other.z,
    self.x * other.y - self.y * other.x
  )
end

function Vector3:clone()
  return Vector3.new(self.x, self.y, self.z)
end

function Vector3.__tostring(v)
  return string.format("(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
end

return Vector3

-- vector3.lua
-- Minimal 3D vector math for the OpenOS space renderer.
-- Save to: /lib/vector3.lua  (so `require("vector3")` finds it)

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

function Vector3.__mul(a, b)
  if type(a) == "number" then
    return Vector3.new(b.x * a, b.y * a, b.z * a)
  else
    return Vector3.new(a.x * b, a.y * b, a.z * b)
  end
end

function Vector3.__unm(a)
  return Vector3.new(-a.x, -a.y, -a.z)
end

function Vector3.__tostring(v)
  return string.format("(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
end

function Vector3:dot(o)
  return self.x * o.x + self.y * o.y + self.z * o.z
end

function Vector3:cross(o)
  return Vector3.new(
    self.y * o.z - self.z * o.y,
    self.z * o.x - self.x * o.z,
    self.x * o.y - self.y * o.x
  )
end

function Vector3:length()
  return math.sqrt(self:dot(self))
end

function Vector3:normalize()
  local l = self:length()
  if l < 1e-9 then
    return Vector3.new(0, 0, 0)
  end
  return Vector3.new(self.x / l, self.y / l, self.z / l)
end

function Vector3:rotateY(angle)
  local c, s = math.cos(angle), math.sin(angle)
  return Vector3.new(
    self.x * c + self.z * s,
    self.y,
    -self.x * s + self.z * c
  )
end

function Vector3:rotateX(angle)
  local c, s = math.cos(angle), math.sin(angle)
  return Vector3.new(
    self.x,
    self.y * c - self.z * s,
    self.y * s + self.z * c
  )
end

return Vector3

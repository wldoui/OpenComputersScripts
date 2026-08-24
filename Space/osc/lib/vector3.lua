local Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x, y, z)
  return setmetatable({x=x or 0, y=y or 0, z=z or 0}, Vector3)
end

function Vector3:clone()
  return Vector3.new(self.x, self.y, self.z)
end

function Vector3:add(v)
  return Vector3.new(self.x+v.x, self.y+v.y, self.z+v.z)
end

function Vector3:sub(v)
  return Vector3.new(self.x-v.x, self.y-v.y, self.z-v.z)
end

function Vector3:mul(s)
  return Vector3.new(self.x*s, self.y*s, self.z*s)
end

function Vector3:dot(v)
  return self.x*v.x + self.y*v.y + self.z*v.z
end

function Vector3:length()
  return math.sqrt(self:dot(self))
end

function Vector3:normalize()
  local l=self:length()
  if l == 0 then return Vector3.new(0,0,0) end
  return self:mul(1/l)
end

return Vector3

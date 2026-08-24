local V = require("lib.vector3")
local Mat = require("lib.matrix3")

local Camera={}
Camera.__index=Camera

function Camera.new()
  return setmetatable({
    position=V.new(0,0,8),
    rx=-0.18, ry=0.35, rz=0,
    zoom=1.0,
    fov=70
  },Camera)
end

function Camera:rotate(dx,dy)
  self.ry=self.ry+dx
  self.rx=self.rx+dy
  if self.rx > 1.45 then self.rx=1.45 end
  if self.rx < -1.45 then self.rx=-1.45 end
end

function Camera:dolly(amount)
  self.position.z=self.position.z+amount
  if self.position.z < 2 then self.position.z=2 end
  if self.position.z > 80 then self.position.z=80 end
end

function Camera:project(point,cx,cy,scale)
  local p=point:sub(self.position)
  local R=Mat.rotationXYZ(-self.rx,-self.ry,-self.rz)
  p=Mat.apply(R,p)
  if p.z >= -0.1 then return nil end
  local f=scale/math.tan(math.rad(self.fov)*0.5)
  local sx=cx+(p.x/(-p.z))*f
  local sy=cy-(p.y/(-p.z))*f*0.52
  return sx,sy,-p.z
end

return Camera

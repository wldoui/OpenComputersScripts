local V=require("lib.vector3")
local Math=require("lib.math3d")

local R={}
R.__index=R

function R.new(gpu)
  return setmetatable({gpu=gpu, light=V.new(-0.4,0.7,-1):normalize()},R)
end

function R:line(x1,y1,x2,y2,ch)
  local dx=math.abs(x2-x1)
  local dy=math.abs(y2-y1)
  local sx=x1<x2 and 1 or -1
  local sy=y1<y2 and 1 or -1
  local err=dx-dy
  while true do
    if x1>=1 and y1>=1 then self.gpu.set(x1,y1,ch or "*") end
    if x1==x2 and y1==y2 then break end
    local e2=2*err
    if e2>-dy then err=err-dy; x1=x1+sx end
    if e2<dx then err=err+dx; y1=y1+sy end
  end
end

function R:project(v,camera,cx,cy,scale)
  return camera:project(v,cx,cy,scale)
end

function R:drawCubePlanet(camera,cx,cy,scale,size,spin)
  local s=size
  local pts={
    V.new(-s,-s,-s),V.new(s,-s,-s),V.new(s,s,-s),V.new(-s,s,-s),
    V.new(-s,-s,s),V.new(s,-s,s),V.new(s,s,s),V.new(-s,s,s)
  }
  local projected={}
  for i,p in ipairs(pts) do
    local x=p.x*math.cos(spin)-p.z*math.sin(spin)
    local z=p.x*math.sin(spin)+p.z*math.cos(spin)
    projected[i]=self:project(V.new(x,p.y,z),camera,cx,cy,scale)
  end
  local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
  for _,e in ipairs(edges) do
    local a,b=projected[e[1]],projected[e[2]]
    if a and b then self:line(Math.round(a),Math.round(b),Math.round(b),Math.round(b),"#") end
  end
  -- blocky face texture: deterministic grid points on front-facing cube faces
  local chars={".",":","*","o","O","#","@"}
  for gx=-4,4 do
    for gy=-4,4 do
      local x=gx*s/4
      local y=gy*s/4
      local z=-s
      local p=V.new(x*math.cos(spin)-z*math.sin(spin),y,x*math.sin(spin)+z*math.cos(spin))
      local sx,sy,depth=self:project(p,camera,cx,cy,scale)
      if sx and depth then
        local brightness=Math.clamp(((-1)+(gx+gy)%7)/5,0,1)
        local idx=Math.clamp(math.floor(brightness*6)+1,1,7)
        local ix,iy=Math.round(sx),Math.round(sy)
        if ix>=1 and iy>=1 then self.gpu.set(ix,iy,chars[idx]) end
      end
    end
  end
end

function R:drawOrbit(camera,cx,cy,scale,radius,segments)
  local prev=nil
  for i=0,segments do
    local a=(i/segments)*math.pi*2
    local p=V.new(math.cos(a)*radius,0,math.sin(a)*radius)
    local q=camera:project(p,cx,cy,scale)
    if q and prev then self:line(Math.round(prev[1]),Math.round(prev[2]),Math.round(q),Math.round(select(2,camera:project(p,cx,cy,scale))),".") end
    if q then prev={q} end
  end
end

return R

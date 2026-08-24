local M = {}

function M.identity()
  return {
    {1,0,0},
    {0,1,0},
    {0,0,1}
  }
end

function M.mul(a,b)
  local r={{0,0,0},{0,0,0},{0,0,0}}
  for i=1,3 do
    for j=1,3 do
      r[i][j]=a[i][1]*b[1][j]+a[i][2]*b[2][j]+a[i][3]*b[3][j]
    end
  end
  return r
end

function M.apply(a,v)
  return {
    x=a[1][1]*v.x+a[1][2]*v.y+a[1][3]*v.z,
    y=a[2][1]*v.x+a[2][2]*v.y+a[2][3]*v.z,
    z=a[3][1]*v.x+a[3][2]*v.y+a[3][3]*v.z
  }
end

function M.rotationXYZ(rx,ry,rz)
  local cx,sx=math.cos(rx),math.sin(rx)
  local cy,sy=math.cos(ry),math.sin(ry)
  local cz,sz=math.cos(rz),math.sin(rz)
  local Rx={{1,0,0},{0,cx,-sx},{0,sx,cx}}
  local Ry={{cy,0,sy},{0,1,0},{-sy,0,cy}}
  local Rz={{cz,-sz,0},{sz,cz,0},{0,0,1}}
  return M.mul(M.mul(Rz,Ry),Rx)
end

return M

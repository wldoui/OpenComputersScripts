local M={}

function M.clamp(x,a,b)
  if x<a then return a end
  if x>b then return b end
  return x
end

function M.lerp(a,b,t)
  return a+(b-a)*t
end

function M.round(x)
  if x>=0 then return math.floor(x+0.5) end
  return math.ceil(x-0.5)
end

return M

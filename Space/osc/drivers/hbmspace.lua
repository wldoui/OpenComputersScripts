local component=require("component")

local M={}
M.__index=M

function M.new()
  local self=setmetatable({component=nil,address=nil,lastError=nil},M)
  self:discover()
  return self
end

function M:discover()
  self.component=nil
  self.address=nil
  if component.isAvailable("ntm_stardar") then
    local ok,proxy=pcall(component.getPrimary,"ntm_stardar")
    if ok and proxy then
      self.component=proxy
      self.address=proxy.address
      return true
    end
    local ok2,addr=pcall(function()
      for a,t in component.list("ntm_stardar",true) do return a end
    end)
    if ok2 and addr then
      self.component=component.proxy(addr)
      self.address=addr
      return true
    end
  end
  self.lastError="ntm_stardar unavailable"
  return false
end

function M:available()
  return self.component~=nil
end

function M:currentPlanet()
  if not self.component then return nil,"UNAVAILABLE" end
  local ok,a=pcall(self.component.getCurrentPlanet)
  if ok then return a end
  return nil,a
end

function M:planetStats(name)
  if not self.component then return nil,"UNAVAILABLE" end
  local ok,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o=pcall(self.component.getPlanetStats,name)
  if not ok then return nil,a end
  if a==nil then return nil,b or "UNKNOWN BODY" end
  return {
    name=a,parent=b,star=c,tidallyLockedTo=d,axialTilt=e,landable=f,
    massKg=g,processingLevel=h,radiusKm=i,semiMajorAxisKm=j,
    sunPower=k,surfaceGravity=l,rotationalPeriod=m,orbitalPeriod=n
  }
end

function M:satellites(name)
  if not self.component then return nil,"UNAVAILABLE" end
  local ok,packed=pcall(function()
    local r={self.component.getSatellites(name)}
    return r
  end)
  if not ok then return nil,packed end
  return packed
end


function M:rocketPads()
  local result={}
  for addr in component.list("ntm_rocket_pad", true) do
    local p=component.proxy(addr)
    local r={address=addr}
    local ok,can=pcall(p.canLaunch); r.canLaunch=ok and can or nil
    local ok2,stats=pcall(p.getRocketStats); r.stats=ok2 and stats or nil
    local ok3,dest=pcall(p.getDestination); r.destination=ok3 and dest or nil
    result[#result+1]=r
  end
  return result
end

return M

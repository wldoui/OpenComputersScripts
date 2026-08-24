local component=require("component")
local computer=require("computer")
local event=require("event")
local term=require("term")

local Settings=require("config.settings")
local Camera=require("lib.camera")
local Renderer=require("lib.renderer3d")
local V=require("lib.vector3")
local HBM=require("drivers.hbmspace")

local M={}

local function safeCall(f,...)
  local ok,a,b,c=pcall(f,...)
  if ok then return a,b,c end
  return nil,a
end

local function drawHeader(gpu,w,title)
  gpu.setBackground(0x111111)
  gpu.setForeground(0x66FFAA)
  gpu.fill(1,1,w,1," ")
  gpu.set(2,1,title)
  gpu.setForeground(0xAAAAAA)
  gpu.set(w-17,1,"SPACE CONTROL")
end

local function drawFooter(gpu,w,h,text)
  gpu.setForeground(0x777777)
  gpu.fill(1,h,w,1," ")
  gpu.set(2,h,text)
end

local function drawPanel(gpu,x,y,w,h,title)
  gpu.setForeground(0x444444)
  gpu.fill(x,y,w,h," ")
  gpu.setForeground(0x66FFAA)
  gpu.set(x,y,"+"..string.rep("-",math.max(0,w-2)).."+")
  for yy=y+1,y+h-2 do
    gpu.set(x,yy,"|")
    gpu.set(x+w-1,yy,"|")
  end
  gpu.set(x,y+h-1,"+"..string.rep("-",math.max(0,w-2)).."+")
  gpu.set(x+2,y,title)
end

local function main()
  local gpu=component.gpu
  local screen=component.screen
  if not gpu or not screen then error("GPU and Screen are required") end
  local w,h=gpu.getResolution()
  local cam=Camera.new()
  local renderer=Renderer.new(gpu)
  local hbm=HBM.new()
  local selected=Settings.default_planet
  local spin=0
  local dragging=false
  local lastX,lastY=nil,nil

  while true do
    local t0=computer.uptime()
    local current=hbm:currentPlanet()
    if current then selected=current end
    local stats=hbm:planetStats(selected)
    local sats=hbm:satellites(selected)

    gpu.setBackground(0x05080A)
    gpu.setForeground(0xCCCCCC)
    gpu.fill(1,1,w,h," ")
    drawHeader(gpu,w,Settings.app_name.." v"..Settings.version)
    drawPanel(gpu,2,3,math.floor(w*0.72),h-6,"3D SPACE VIEW")
    drawPanel(gpu,math.floor(w*0.72)+3,3,w-math.floor(w*0.72)-5,h-6,"TELEMETRY")

    local vx=3, vy=4, vw=math.floor(w*0.72)-2, vh=h-8
    local cx=math.floor(vx+vw/2)
    local cy=math.floor(vy+vh/2)
    local size=stats and math.max(2,math.min(4,math.log((stats.radiusKm or 1000)+1)/2)) or 3

    renderer:drawCubePlanet(cam,cx,cy,12,size,spin)

    gpu.setForeground(0x66FFAA)
    gpu.set(cx-5,vy+1,"BLOCKY 3D")
    gpu.set(cx-6,vy+2,selected or "N/A")

    local tx=math.floor(w*0.72)+5
    local y=5
    gpu.setForeground(0xFFFFFF)
    gpu.set(tx,y,"SOURCE: HBM SPACE")
    y=y+2
    gpu.setForeground(0x66FFAA)
    gpu.set(tx,y,"COMPONENT")
    y=y+1
    gpu.setForeground(0xAAAAAA,string.sub(hbm.address or "UNAVAILABLE",1,18))
    y=y+2
    gpu.setForeground(0x66FFAA)
    gpu.set(tx,y,"CURRENT BODY")
    y=y+1
    gpu.setForeground(0xFFFFFF,string.sub(tostring(current or "N/A"),1,24))
    y=y+2

    if stats then
      gpu.setForeground(0x66FFAA); gpu.set(tx,y,"BODY DATA"); y=y+1
      local rows={
        {"radius km",stats.radiusKm},
        {"gravity",stats.surfaceGravity},
        {"mass kg",stats.massKg},
        {"axis km",stats.semiMajorAxisKm},
        {"orbit days",stats.orbitalPeriod},
        {"landable",stats.landable},
      }
      for _,r in ipairs(rows) do
        gpu.setForeground(0xAAAAAA); gpu.set(tx,y,string.sub(r[1],1,12))
        gpu.setForeground(0xFFFFFF); gpu.set(tx+13,y,string.sub(tostring(r[2]),1,12)); y=y+1
      end
    else
      gpu.setForeground(0xFFAA66); gpu.set(tx,y,"BODY DATA: N/A"); y=y+1
    end

    y=y+2
    local pads=hbm:rocketPads()
    gpu.setForeground(0x66FFAA); gpu.set(tx,y,"ROCKET PADS"); y=y+1
    if #pads==0 then
      gpu.setForeground(0x777777); gpu.set(tx,y,"NONE"); y=y+1
    else
      for i=1,math.min(#pads,2) do
        local rp=pads[i]
        gpu.setForeground(0xFFFFFF)
        gpu.set(tx,y,string.format("PAD %02d  %s",i,rp.canLaunch and "READY" or "LOCKED")); y=y+1
        if rp.destination then
          gpu.setForeground(0xAAAAAA); gpu.set(tx,y,"DST "..string.sub(tostring(rp.destination),1,15)); y=y+1
        end
      end
    end
    y=y+1
    gpu.setForeground(0x66FFAA); gpu.set(tx,y,"SATELLITES"); y=y+1
    if sats and #sats>0 then
      for i=1,math.min(#sats,h-y-5) do
        gpu.setForeground(0xFFFFFF)
        gpu.set(tx,y,string.format("%02d  %s",i,tostring(sats[i]))); y=y+1
      end
    else
      gpu.setForeground(0x777777)
      gpu.set(tx,y,"NONE / N/A")
    end

    drawFooter(gpu,w,h,"LMB select  RMB orbit  wheel zoom  Q/E zoom  I inspector  ESC exit")

    local dt=computer.uptime()-t0
    local wait=math.max(0,1/Settings.render_fps-dt)
    local ev={event.pull(wait)}
    if ev[1]=="key_down" then
      local code=ev[4]
      local char=ev[3]
      if code==1 then break end
      if char==113 or char==81 then cam:dolly(-1) end -- Q
      if char==101 or char==69 then cam:dolly(1) end  -- E
      if char==114 or char==82 then cam=Camera.new() end -- R
      if char==112 or char==80 then
        term.clear()
        io.write("BODY NAME> ")
        local name=io.read()
        if name and #name>0 then selected=name end
      end
    elseif ev[1]=="mouse_drag" then
      local button,x,y=ev[3],ev[4],ev[5]
      if button==1 then
        if lastX then cam:rotate((x-lastX)*0.03,(y-lastY)*0.03) end
        lastX,lastY=x,y
      end
    elseif ev[1]=="mouse_up" then
      lastX,lastY=nil,nil
    elseif ev[1]=="scroll" then
      cam:dolly(-(ev[5] or 0)*0.8)
    elseif ev[1]=="touch" then
      local x,y=ev[3],ev[4]
      if stats then
        local px,py=cam:project(V.new(0,0,0),cam,cx,cy,12)
        if px and math.abs(x-px)<=8 and math.abs(y-py)<=8 then
          selected=stats.name
        end
      end
    end
    spin=spin+0.02
  end
end

function M.run()
  main()
end

return M

local component=require("component")
local term=require("term")

local M={}

local SAFE_GETTERS={
  getComponentName=true,getName=true,getLabel=true,getAddress=true,
  getResolution=true,getViewport=true,getDepth=true,getForeground=true,
  getBackground=true,getActiveBuffer=true,buffers=true,
  maxResolution=true,maxDepth=true,totalMemory=true,freeMemory=true,
  getScreen=true
}

local function sortedKeys(t)
  local r={}
  for k in pairs(t) do r[#r+1]=k end
  table.sort(r)
  return r
end

function M.run()
  term.clear()
  print("OPEN SPACE CONTROL :: API INSPECTOR")
  print("Read-only scan. No setter/free/buffer mutation is executed.")
  print("")
  for addr,typ in component.list() do
    print("DEVICE")
    print("UUID: "..tostring(addr))
    print("TYPE: "..tostring(typ))
    local p=component.proxy(addr)
    local methods={}
    for k,v in pairs(p) do
      if type(v)=="function" then methods[#methods+1]=k end
    end
    table.sort(methods)
    print("METHODS:")
    for _,name in ipairs(methods) do
      local marker=SAFE_GETTERS[name] and " [SAFE]" or " [NOT CALLED]"
      print("  "..name..marker)
    end
    print("")
  end
  print("Press any key.")
  while true do
    local e={computer.pullSignal()}
    if e[1]=="key_down" then break end
  end
end

return M

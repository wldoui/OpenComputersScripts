local component=require("component")
local term=require("term")
local shell=require("shell")

local function ensureDir(path)
  local fs=component.filesystem
  if not fs then return false end
  local ok=fs.makeDirectory(path)
  return ok~=false
end

local function ensure()
  ensureDir("/apps")
  ensureDir("/drivers")
  ensureDir("/lib")
  ensureDir("/system")
  ensureDir("/data")
  ensureDir("/config")
end

local M={}
function M.run()
  ensure()
  term.clear()
  print("OPEN SPACE CONTROL")
  print("Initializing...")
  if not component.gpu then error("GPU missing") end
  if not component.screen then error("Screen missing") end
  if component.isAvailable("ntm_stardar") then
    print("HBM SPACE: ntm_stardar ONLINE")
  else
    print("HBM SPACE: ntm_stardar OFFLINE")
  end
  print("Ready.")
  os.sleep(1)
end
return M

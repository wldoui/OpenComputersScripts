local component=require("component")
local shell=require("shell")
local fs=require("filesystem")

local args=shell.parse(...)
local source=args[1] or shell.getWorkingDirectory()
if source=="--autorun" or source=="--remove" then source=shell.getWorkingDirectory() end
source=fs.canonical(source)
local root="/"
local files={
  "boot.lua","space.lua","osc_inspect.lua",
  "apps","drivers","lib","system","config","docs"
}
local function copyTree(src,dst)
  if fs.isDirectory(src) then
    fs.makeDirectory(dst)
    for name in fs.list(src) do
      local clean=name:gsub("/$","")
      copyTree(fs.concat(src,clean),fs.concat(dst,clean))
    end
  else
    fs.copy(src,dst)
  end
end

if args[1]=="--remove" then
  local targets={"/boot.lua","/space.lua","/osc_inspect.lua","/apps","/drivers","/lib","/system","/config","/docs","/etc/rc.d/99_open_space_control.lua"}
  for _,p in ipairs(targets) do pcall(fs.remove,p) end
  print("Open Space Control removed.")
  return
end

for _,name in ipairs(files) do
  local src=fs.concat(source,name)
  local dst=fs.concat(root,name)
  if fs.exists(src) then
    if fs.isDirectory(src) then
      fs.makeDirectory(dst)
      copyTree(src,dst)
    else
      fs.copy(src,dst)
    end
  end
end

if args.autorun or args[1]=="--autorun" then
  fs.makeDirectory("/etc/rc.d")
  local f=io.open("/etc/rc.d/99_open_space_control.lua","w")
  f:write('local shell=require("shell")\nlocal ok,err=pcall(shell.execute,"/boot.lua")\nif not ok then print(err) end\n')
  f:close()
end

print("Open Space Control installed.")
print("Run: space")
if args[1]=="--autorun" then print("Autorun enabled.") end

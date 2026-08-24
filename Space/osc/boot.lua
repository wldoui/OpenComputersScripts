local component=require("component")
local computer=require("computer")
local term=require("term")
local shell=require("shell")

local ok,init=pcall(require,"system.init")
if ok and init then pcall(init.run) end

while true do
  term.clear()
  print("+--------------------------------------------------------------+")
  print("|                    OPEN SPACE CONTROL                        |")
  print("+--------------------------------------------------------------+")
  print("| 1  SPACE CONTROL    2  API INSPECTOR    3  TERMINAL         |")
  print("| 4  COMPONENTS       5  REBOOT            6  SHUTDOWN        |")
  print("+--------------------------------------------------------------+")
  io.write("SELECT> ")
  local c=io.read()
  if c=="1" then shell.execute("space")
  elseif c=="2" then shell.execute("osc_inspect")
  elseif c=="3" then local t=require("apps.terminal"); t.run()
  elseif c=="4" then
    term.clear()
    for a,t in component.list() do print(a.."  "..t) end
    print("Press Enter.")
    io.read()
  elseif c=="5" then computer.shutdown(true)
  elseif c=="6" then computer.shutdown(false)
  end
end

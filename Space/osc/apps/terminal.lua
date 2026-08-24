local shell=require("shell")
local term=require("term")
local computer=require("computer")

local M={}
function M.run()
  term.clear()
  print("OPEN SPACE CONTROL TERMINAL")
  print("Type 'exit' to return.")
  while true do
    term.write("osc> ")
    local line=term.read()
    if not line then break end
    line=line:gsub("\n","")
    if line=="exit" or line=="quit" then break end
    if line=="" then
    elseif line=="space" then shell.execute("space")
    elseif line=="inspect" then shell.execute("osc_inspect")
    elseif line=="reboot" then computer.shutdown(true)
    elseif line=="shutdown" then computer.shutdown(false)
    elseif line=="help" then print("space  inspect  reboot  shutdown  exit")
    else print("unknown command: "..line) end
  end
end
return M

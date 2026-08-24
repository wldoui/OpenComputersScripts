-- ==================================================================
-- boot.lua
-- OPEN SPACE CONTROL entry point.
--
-- Expects this layout on the computer's filesystem (root of the
-- disk this file lives on):
--   /boot.lua
--   /lib/*.lua
--   /drivers/*.lua
--   /apps/*.lua
--   /data/*.lua
--   /data/*.log, *.dat   (written at runtime by api_inspector etc.)
--
-- Run with:  boot.lua
-- (or set as autorun -- see install notes in the chat response)
-- ==================================================================

package.path = package.path
  .. ";/lib/?.lua"
  .. ";/drivers/?.lua"
  .. ";/apps/?.lua"
  .. ";/data/?.lua"

local component = require("component")
local term = require("term")

local function checkRequirements()
  local missing = {}
  if not component.isAvailable("gpu") then table.insert(missing, "gpu") end
  if not component.isAvailable("screen") then table.insert(missing, "screen") end
  return missing
end

local function mainMenu()
  term.clear()
  print("+--------------------------------------+")
  print("|        OPEN SPACE CONTROL             |")
  print("+--------------------------------------+")
  print("")
  print("[1] SPACE CONTROL")
  print("[2] ENERGY CONTROL      (not built yet -- no HBM CE API confirmed)")
  print("[3] API INSPECTOR       (run /api_inspector.lua directly)")
  print("[6] TERMINAL / exit to shell")
  print("")
  term.write("> ")
  local choice = term.read()
  if not choice then return end
  choice = choice:gsub("%s+", "")

  if choice == "1" then
    local ok, err = pcall(function()
      local SpaceApp = require("space")
      SpaceApp.run()
    end)
    if not ok then
      term.clear()
      print("SPACE CONTROL crashed:")
      print(tostring(err))
    end
    mainMenu()
  elseif choice == "2" then
    print("")
    print("ENERGY CONTROL is intentionally not implemented yet.")
    print("Reason: no HBM CE energy-storage component has been confirmed")
    print("via api_inspector.lua on this world. Scan a real battery/core")
    print("first (place an OC Adapter next to it), then this gets built")
    print("the same way SPACE was: real methods only, no guessing.")
    print("")
    os.sleep(3)
    mainMenu()
  elseif choice == "3" then
    print("Run:  api_inspector.lua   (from the OpenOS shell, not from here)")
    os.sleep(2)
    mainMenu()
  elseif choice == "6" then
    term.clear()
    return
  else
    mainMenu()
  end
end

local missing = checkRequirements()
if #missing > 0 then
  print("Cannot start OPEN SPACE CONTROL -- missing components: " .. table.concat(missing, ", "))
  print("Attach a GPU and Screen to this computer and rerun boot.lua.")
  return
end

mainMenu()

-- ==================================================================
-- drivers/discovery.lua
--
-- Generic, honest device discovery. This is deliberately NOT
-- "drivers/hbmspace.lua" from the original spec, because we do not
-- yet know a single real HBM Space method name on this world (your
-- last scan found 9 components and ALL of them were base
-- OpenComputers: gpu, keyboard, filesystem, and presumably
-- screen/computer/eeprom/etc for the rest).
--
-- That means one of two things, and this module cannot tell you
-- which without more info from you:
--   (a) no OC Adapter is currently placed next to any HBM Space /
--       NTM CE block, or
--   (b) HBM Space 0.9.2 on this build does not expose OpenComputers
--       components at all.
--
-- What this module DOES do, honestly:
--   - lists every component NOT in data/known_base_components.lua
--     as a "candidate" device
--   - for each candidate, safely probes its getters exactly like
--     api_inspector.lua does (get*/is*/has*, zero-arg, pcall'd)
--   - returns structured data apps/space.lua can render as
--     "UNAVAILABLE" until real fields are confirmed
--
-- Nothing below invents a method name that hasn't been seen via
-- component.methods() on your actual machine.
-- ==================================================================

local component = require("component")

local knownBase = require("known_base_components")

local UNSAFE_PREFIXES = {
  "set", "launch", "start", "stop", "shutdown", "reboot", "write",
  "remove", "delete", "clear", "load", "move", "open", "close",
  "drop", "send", "transfer", "execute", "run", "eject", "insert",
  "place", "break", "activate", "deactivate", "kill", "destroy",
  "fire", "detonate", "ignite", "unlink", "link", "connect",
  "disconnect", "format", "flash"
}

local Discovery = {}

local function isUnsafe(name)
  local lower = name:lower()
  for _, prefix in ipairs(UNSAFE_PREFIXES) do
    if lower:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Returns:
--   base = { {address, ctype}, ... }       -- known vanilla OC components
--   candidates = { {address, ctype, fields = {name=value,...}}, ... }
--     -- unknown-type components, with any zero-arg getters resolved
function Discovery.scan()
  local base, candidates = {}, {}

  for address, ctype in component.list() do
    if knownBase[ctype] then
      table.insert(base, { address = address, ctype = ctype })
    else
      local proxyOk, proxy = pcall(component.proxy, address)
      local methodsOk, methods = pcall(component.methods, address)
      local fields = {}

      if methodsOk and methods then
        for methodName, _ in pairs(methods) do
          if not isUnsafe(methodName) and proxyOk and proxy[methodName] then
            local callOk, result = pcall(proxy[methodName])
            fields[methodName] = {
              ok = callOk,
              value = result,
            }
          end
        end
      end

      table.insert(candidates, {
        address = address,
        ctype = ctype,
        fields = fields,
      })
    end
  end

  return base, candidates
end

-- Human-readable one-liner per candidate, for the OBJECTS tab in
-- apps/space.lua, e.g.:
--   "ntm_something (a1b2c3..)  3 getters resolved"
function Discovery.summarize(candidate)
  local resolvedCount = 0
  for _, f in pairs(candidate.fields) do
    if f.ok then resolvedCount = resolvedCount + 1 end
  end
  local shortAddr = candidate.address:sub(1, 8)
  return string.format("%s (%s..) - %d getter(s) resolved",
    candidate.ctype, shortAddr, resolvedCount)
end

return Discovery

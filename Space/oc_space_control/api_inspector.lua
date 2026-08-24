-- ==================================================================
-- api_inspector.lua
-- OPEN SPACE CONTROL — STAGE 1: API INSPECTOR
--
-- Minecraft 1.12.2 / Forge 14.23.5.2860
-- OpenComputers 1.8.9a
-- HBM's Nuclear Tech CE 2.5.0.5 + HBM Space 0.9.2
--
-- PURPOSE:
--   Discover REAL components, REAL method names and REAL return
--   values on this specific world/save. Nothing here is guessed.
--   Everything printed comes from component.list()/component.methods()
--   and actual pcall()'d invocations of safe (read-only) methods.
--
-- SAFETY:
--   This tool NEVER calls a method whose name looks like it changes
--   world/machine state (set*, launch, start, stop, shutdown, reboot,
--   write, remove, delete, clear, load, move, open, close, drop,
--   send, transfer, execute, run, eject, insert, place, break).
--   Those methods are only LISTED, never invoked.
--   Everything else (get*, is*, has*, list, name, address, count,
--   type) is treated as a getter and safely pcall()'d.
--
-- USAGE (in OpenOS):
--   api_inspector.lua                 -- scan everything, print + log
--   api_inspector.lua <componentType> -- scan only one type
--   api_inspector.lua --list-types    -- just print discovered types
--
-- OUTPUT:
--   Printed to the terminal (paged) AND written to:
--     /data/api_scan_<timestamp>.log   (human readable)
--     /data/api_scan_<timestamp>.dat   (serialized table, if the
--                                       `serialization` library is
--                                       present, for later drivers
--                                       to consume programmatically)
-- ==================================================================

local component = require("component")
local computer   = require("computer")
local term       = require("term")
local event      = require("event")
local filesystem = require("filesystem")

-- serialization is a library component/API in OpenComputers, present
-- on virtually all installs (it's part of the base OS), but we
-- pcall the require just in case, per rule "never assume a
-- component/library exists".
local okSerial, serialization = pcall(require, "serialization")
if not okSerial then serialization = nil end

-- ------------------------------------------------------------------
-- Config
-- ------------------------------------------------------------------

local DATA_DIR = "/data"
local UNSAFE_PREFIXES = {
  "set", "launch", "start", "stop", "shutdown", "reboot", "write",
  "remove", "delete", "clear", "load", "move", "open", "close",
  "drop", "send", "transfer", "execute", "run", "eject", "insert",
  "place", "break", "activate", "deactivate", "kill", "destroy",
  "fire", "detonate", "ignite", "unlink", "link", "connect",
  "disconnect", "format", "flash"
}

local args = { ... }

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------

local function isUnsafe(methodName)
  local lower = methodName:lower()
  for _, prefix in ipairs(UNSAFE_PREFIXES) do
    if lower:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

-- Best-effort human readable dump of a Lua value without assuming
-- serialization exists.
local function dump(value, depth)
  depth = depth or 0
  if depth > 3 then return "..." end
  local t = type(value)
  if t == "nil" then
    return "nil"
  elseif t == "boolean" or t == "number" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local parts = {}
    local isArray = true
    local n = 0
    for k, _ in pairs(value) do
      n = n + 1
      if type(k) ~= "number" then isArray = false end
    end
    if n == 0 then return "{}" end
    for k, v in pairs(value) do
      if isArray then
        table.insert(parts, dump(v, depth + 1))
      else
        table.insert(parts, tostring(k) .. "=" .. dump(v, depth + 1))
      end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  else
    -- functions, userdata, threads: can't serialize, just tag type
    return "<" .. t .. ">"
  end
end

local function ensureDataDir()
  if not filesystem.exists(DATA_DIR) then
    filesystem.makeDirectory(DATA_DIR)
  end
end

local function timestamp()
  -- os.date is available in OpenOS
  return os.date("%Y%m%d_%H%M%S")
end

-- Collects method names for an address into a sorted array.
-- component.methods(address) returns a table keyed by method name;
-- values are metadata tables (fields such as `direct`/`doc` vary by
-- component, so we do not rely on their shape here — only on the
-- keys, which are the actual callable method names).
local function listMethods(address)
  local ok, methods = pcall(component.methods, address)
  if not ok or not methods then return {} end
  local names = {}
  for name, _ in pairs(methods) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function getDoc(address, methodName)
  local ok, doc = pcall(component.doc, address, methodName)
  if ok and doc then return doc end
  return nil
end

-- ------------------------------------------------------------------
-- Core scan
-- ------------------------------------------------------------------

-- Returns an array of records:
-- { address=..., ctype=..., slot=..., methods = {
--      { name=..., unsafe=bool, doc=..., tested=bool, ok=bool, result=... }
--   }}
local function scanComponents(filterType)
  local records = {}

  for address, ctype in component.list(filterType) do
    local record = {
      address = address,
      ctype = ctype,
      slot = select(1, pcall(component.slot, address)) and component.slot(address) or -1,
      methods = {}
    }

    local proxyOk, proxy = pcall(component.proxy, address)

    for _, methodName in ipairs(listMethods(address)) do
      local entry = {
        name = methodName,
        unsafe = isUnsafe(methodName),
        doc = getDoc(address, methodName),
        tested = false,
        ok = nil,
        result = nil,
      }

      if not entry.unsafe and proxyOk and proxy[methodName] then
        entry.tested = true
        -- Call with ZERO arguments only. Any method that requires
        -- arguments will simply error out here, which is fine and
        -- expected — we record the error message so it's visible
        -- that the method needs parameters, without guessing what
        -- they are.
        local callOk, result = pcall(proxy[methodName])
        entry.ok = callOk
        entry.result = result
      end

      table.insert(record.methods, entry)
    end

    table.insert(records, record)
  end

  return records
end

-- ------------------------------------------------------------------
-- Output
-- ------------------------------------------------------------------

local function writeAndPrint(lines, logHandle)
  for _, line in ipairs(lines) do
    print(line)
    if logHandle then
      logHandle:write(line .. "\n")
    end
  end
end

local function formatRecord(record)
  local lines = {}
  table.insert(lines, "==================================================")
  table.insert(lines, "DEVICE:      " .. record.ctype)
  table.insert(lines, "UUID:        " .. record.address)
  table.insert(lines, "SLOT:        " .. tostring(record.slot))
  table.insert(lines, "METHODS:")

  if #record.methods == 0 then
    table.insert(lines, "  (none reported by component.methods — component may")
    table.insert(lines, "   only expose fields via primitives, or scan failed)")
  end

  for _, m in ipairs(record.methods) do
    local tag
    if m.unsafe then
      tag = "[UNSAFE - listed only, not invoked]"
    elseif not m.tested then
      tag = "[not invoked]"
    elseif m.ok then
      tag = "[OK] -> " .. dump(m.result)
    else
      tag = "[ERROR] -> " .. dump(m.result) .. "  (likely needs arguments)"
    end
    table.insert(lines, "  " .. m.name .. "()  " .. tag)
    if m.doc then
      table.insert(lines, "      doc: " .. tostring(m.doc))
    end
  end

  return lines
end

-- Simple pager: prints N lines, waits for keypress, continues.
local function pagedPrint(allLines, logHandle, pageSize)
  pageSize = pageSize or 18
  local count = 0
  for _, line in ipairs(allLines) do
    print(line)
    if logHandle then logHandle:write(line .. "\n") end
    count = count + 1
    if count % pageSize == 0 then
      term.write("-- press any key for more, q to stop paging --\n")
      local _, _, _, code = event.pull("key_down")
      if code == 16 then -- 'q'
        pageSize = math.huge -- stop pausing, dump the rest
      end
    end
  end
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------

local function main()
  ensureDataDir()

  if args[1] == "--list-types" then
    print("Discovered component types on this machine/network:")
    local seen = {}
    for address, ctype in component.list() do
      if not seen[ctype] then
        seen[ctype] = true
        print("  " .. ctype)
      end
    end
    return
  end

  local filterType = args[1] -- nil = scan everything

  print("OPEN SPACE CONTROL - API INSPECTOR (Stage 1)")
  print("Scanning components" .. (filterType and (" matching: " .. filterType) or "") .. " ...")
  print("")

  local records = scanComponents(filterType)

  if #records == 0 then
    print("No matching components found on this OpenComputers network.")
    print("Check cabling / adapters, or run with --list-types to see what IS present.")
    return
  end

  local ts = timestamp()
  local logPath = DATA_DIR .. "/api_scan_" .. ts .. ".log"
  local logHandle = io.open(logPath, "w")

  local header = {
    "OPEN SPACE CONTROL - API SCAN",
    "Timestamp: " .. ts,
    "Components found: " .. #records,
    ""
  }
  writeAndPrint(header, logHandle)

  local allLines = {}
  for _, record in ipairs(records) do
    for _, line in ipairs(formatRecord(record)) do
      table.insert(allLines, line)
    end
  end

  pagedPrint(allLines, logHandle, 18)

  if logHandle then logHandle:close() end

  -- Also dump a machine-readable version for future drivers to load,
  -- if the serialization library is actually present on this system.
  if serialization then
    local datPath = DATA_DIR .. "/api_scan_" .. ts .. ".dat"
    local datHandle = io.open(datPath, "w")
    if datHandle then
      -- Strip function-shaped fields before serializing; proxies/
      -- functions can't be serialized and we don't need them here,
      -- only the discovered names/results.
      local safeRecords = {}
      for _, r in ipairs(records) do
        local safeMethods = {}
        for _, m in ipairs(r.methods) do
          table.insert(safeMethods, {
            name = m.name,
            unsafe = m.unsafe,
            tested = m.tested,
            ok = m.ok,
            doc = m.doc,
          })
        end
        table.insert(safeRecords, {
          address = r.address,
          ctype = r.ctype,
          slot = r.slot,
          methods = safeMethods,
        })
      end
      local ok, serialized = pcall(serialization.serialize, safeRecords)
      if ok then
        datHandle:write(serialized)
      end
      datHandle:close()
      print("")
      print("Machine-readable scan saved to: " .. datPath)
    end
  end

  print("")
  print("Full log saved to: " .. logPath)
  print("Done.")
end

main()

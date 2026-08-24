-- ==================================================================
-- apps/space.lua
-- SPACE CONTROL application.
--
-- Independent from any energy app (per spec: Space and Energy are
-- architecturally separate). This file only imports lib/* and
-- drivers/discovery.lua -- never anything HBM-specific, because no
-- real HBM Space component has been confirmed on this world yet.
--
-- Screen view: pseudo-3D blocky planet in a Viewport, rendered via
-- lib/renderer3d.lua onto lib/screenutil.lua's double buffer.
-- Camera: WASD move, QE up/down, mouse-drag to rotate, scroll to zoom.
-- OBJECTS tab: real discovery.lua results (candidate devices found
-- on the network right now), never fabricated telemetry.
-- ==================================================================

local event = require("event")
local keyboard = require("keyboard")

local ScreenUtil = require("screenutil")
local GUI = require("gui")
local Vector3 = require("vector3")
local Camera = require("camera")
local Renderer3D = require("renderer3d")
local Discovery = require("discovery")

local TAB_NAMES = { "SPACE", "OBJECTS", "ROCKETS", "SATELLITES", "TELEMETRY", "ORBIT", "MISSIONS", "LOG" }

local SpaceApp = {}

function SpaceApp.run()
  local screen = ScreenUtil.new()
  local w, h = screen:size()

  -- ---- root layout -------------------------------------------------
  local root = GUI.newPanelClass and GUI.newPanel(0, 0, w, h, nil) or GUI.newPanel(0, 0, w, h, nil)
  root.title = nil

  local header = GUI.newLabel(2, 0, "SPACE CONTROL", GUI.COLOR.SELECTED)
  local clock = GUI.newLabel(w - 10, 0, os.date("%H:%M:%S"), GUI.COLOR.TEXT_DIM)

  local tabs = GUI.newTabs(2, 1, w - 4, TAB_NAMES)

  local viewport = GUI.newViewport(1, 3, w - 22, h - 5)
  local sidePanel = GUI.newPanel(w - 20, 3, 19, h - 5, "OBJECTS")
  local objectList = GUI.newList(w - 19, 5, 17, h - 8)
  local statusLine = GUI.newLabel(2, h - 1, "WASD move | QE up/down | drag=rotate | wheel=zoom | Q app: ESC quit", GUI.COLOR.TEXT_DIM)

  sidePanel:addChild(objectList)

  root:addChild(header)
  root:addChild(clock)
  root:addChild(tabs)
  root:addChild(viewport)
  root:addChild(sidePanel)
  root:addChild(statusLine)

  -- ---- 3D scene state ------------------------------------------------
  local camera = Camera.new({
    position = Vector3.new(0, 8, -30),
    pitch = 0.15,
    yaw = 0,
    fov = 60,
    zoom = 1.0,
  })
  local planetMesh = Renderer3D.buildBlockyPlanet(10, 5)
  local planetOffset = Vector3.new(0, 0, 0)
  local lightDir = Vector3.new(-0.5, 0.7, -0.5):normalized()
  local autoSpin = 0

  -- ---- discovery state ------------------------------------------------
  local candidates = {}
  local function refreshObjects()
    local _, found = Discovery.scan()
    candidates = found
    local labels = {}
    if #found == 0 then
      labels = { "(no non-OC devices", " found on network)", "", "Place an Adapter", "next to an HBM", "Space block and", "reopen this tab." }
    else
      for _, c in ipairs(found) do
        table.insert(labels, Discovery.summarize(c))
      end
    end
    objectList:setItems(labels)
  end
  refreshObjects()

  objectList.onSelect = function(index, label)
    local candidate = candidates[index]
    if not candidate then return end
    statusLine.text = "Selected: " .. candidate.ctype .. " -- see OBJECTS tab detail (not yet a known HBM device)"
  end

  -- ---- input state ------------------------------------------------
  local dragging = false
  local lastDragX, lastDragY = 0, 0
  local running = true

  local function handleKey(char, code)
    -- WASDQE via keyboard.keys table (real OpenComputers keyboard API)
    if code == keyboard.keys.w then camera:moveLocal(0, 0, 1)
    elseif code == keyboard.keys.s then camera:moveLocal(0, 0, -1)
    elseif code == keyboard.keys.a then camera:moveLocal(-1, 0, 0)
    elseif code == keyboard.keys.d then camera:moveLocal(1, 0, 0)
    elseif code == keyboard.keys.q then camera:moveLocal(0, -1, 0)
    elseif code == keyboard.keys.e then camera:moveLocal(0, 1, 0)
    elseif code == keyboard.keys.escape then running = false
    end
  end

  -- ---- frame render ------------------------------------------------
  local function renderFrame()
    autoSpin = autoSpin + 0.01
    local spinOffset = Vector3.new(0, 0, 0)

    -- gentle auto-rotation of the planet mesh itself (rotate the
    -- offset camera looks at is simpler than rotating every quad
    -- every frame on limited hardware, so we rotate the LIGHT
    -- instead -- cheap, and still reads as "the planet is alive")
    local spinLight = Vector3.new(
      lightDir.x * math.cos(autoSpin) - lightDir.z * math.sin(autoSpin),
      lightDir.y,
      lightDir.x * math.sin(autoSpin) + lightDir.z * math.cos(autoSpin)
    )

    local commands = Renderer3D.renderBlockyPlanet(
      planetMesh, planetOffset, camera, viewport.w, viewport.h, spinLight
    )
    viewport:setCommands(commands)

    clock.text = os.date("%H:%M:%S")

    screen:frame(function()
      root:draw(screen, 0, 0)
    end)
  end

  tabs.onChange = function(i, name)
    statusLine.text = "Tab: " .. name .. (name == "SPACE" and " (live)" or " (stub -- wire up once HBM Space API is confirmed)")
    if name == "OBJECTS" then refreshObjects() end
  end

  -- ---- main loop ------------------------------------------------
  while running do
    renderFrame()

    local e, a1, a2, a3, a4 = event.pull(0.05)

    if e == "key_down" then
      handleKey(a2, a3)
    elseif e == "touch" then
      local lx, ly = a1 - 1, a2 - 1 -- OC touch coords are 1-based
      dragging = true
      lastDragX, lastDragY = lx, ly
      root:onTouch(lx, ly, a4)
    elseif e == "drag" then
      local lx, ly = a1 - 1, a2 - 1
      if dragging then
        local dx = lx - lastDragX
        local dy = ly - lastDragY
        camera:rotate(-dy * 0.05, dx * 0.05, 0)
        lastDragX, lastDragY = lx, ly
      end
    elseif e == "drop" then
      dragging = false
    elseif e == "scroll" then
      local direction = a3
      camera:addZoom(direction * 0.1)
    elseif e == "interrupted" then
      running = false
    end
  end

  screen:destroy()
  require("term").clear()
  print("SPACE CONTROL closed.")
end

return SpaceApp

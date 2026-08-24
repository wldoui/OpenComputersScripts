-- ==================================================================
-- lib/screenutil.lua
-- Thin wrapper around the real `gpu` component confirmed by your
-- api_inspector.lua scan (allocateBuffer, setActiveBuffer, bitblt,
-- fill, set, getResolution, freeBuffer -- all present and OK in
-- your scan output). Nothing here calls a method your scan didn't
-- confirm exists.
--
-- Gives the rest of the system flicker-free double buffering:
-- draw everything to an off-screen buffer, then bitblt it to the
-- screen (page 0) in one shot.
-- ==================================================================

local component = require("component")
local gpu = component.gpu

local ScreenUtil = {}
ScreenUtil.__index = ScreenUtil

function ScreenUtil.new()
  local self = setmetatable({}, ScreenUtil)

  local w, h = gpu.getResolution()
  self.width = w
  self.height = h

  -- allocate one off-screen back buffer matching current resolution
  local index, err = gpu.allocateBuffer(w, h)
  if not index then
    error("screenutil: failed to allocate back buffer: " .. tostring(err))
  end
  self.backBuffer = index

  return self
end

function ScreenUtil:size()
  return self.width, self.height
end

-- Runs `drawFn(gpu)` with the active page set to the back buffer,
-- then blits the whole thing to the screen in one call and restores
-- the active page to the screen (0). This is the "don't redraw the
-- whole screen constantly" / dirty-rect-lite approach from the spec:
-- we still only push ONE bitblt per frame, not per element.
function ScreenUtil:frame(drawFn)
  local previousPage = gpu.getActiveBuffer()

  gpu.setActiveBuffer(self.backBuffer)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, self.width, self.height, " ")

  drawFn(gpu, self.width, self.height)

  gpu.setActiveBuffer(previousPage)
  gpu.bitblt(0, 1, 1, self.width, self.height, self.backBuffer, 1, 1)
end

function ScreenUtil:setChar(x, y, char, fg, bg)
  -- gpu.set expects 1-based coordinates
  if x < 0 or y < 0 or x >= self.width or y >= self.height then return end
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.set(x + 1, y + 1, char)
end

function ScreenUtil:fillRect(x, y, w, h, char, fg, bg)
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.fill(x + 1, y + 1, w, h, char or " ")
end

function ScreenUtil:text(x, y, str, fg, bg)
  if fg then gpu.setForeground(fg) end
  if bg then gpu.setBackground(bg) end
  gpu.set(x + 1, y + 1, str)
end

function ScreenUtil:destroy()
  if self.backBuffer then
    gpu.freeBuffer(self.backBuffer)
    self.backBuffer = nil
  end
end

return ScreenUtil

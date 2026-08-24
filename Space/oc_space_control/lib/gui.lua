-- ==================================================================
-- lib/gui.lua
-- Minimal retained-mode GUI framework for OPEN SPACE CONTROL.
-- Draws through lib/screenutil.lua (which itself only calls gpu
-- methods confirmed present in your real component scan).
--
-- Widgets: Panel, Label, Button, List, Tabs, Viewport (hosts a 3D
-- scene's draw commands from lib/renderer3d.lua).
--
-- Real OpenComputers events used: "touch", "scroll", "key_down".
-- (These are documented OC input events; if your build's input
-- device reports something different, that will show up plainly as
-- "no widget reacts to clicks" and is worth re-checking with
-- event.pull() by itself -- this framework does not invent event
-- names beyond these three standard ones.)
-- ==================================================================

local GUI = {}

-- Colors (24-bit, matches gpu.setForeground/Background which your
-- scan confirmed take numeric values)
GUI.COLOR = {
  BORDER    = 0x00FF66,
  BORDER_DIM = 0x006622,
  TEXT      = 0xFFFFFF,
  TEXT_DIM  = 0x888888,
  BG        = 0x000000,
  SELECTED  = 0xFFAA00,
  ALERT     = 0xFF3333,
}

-- ------------------------------------------------------------------
-- Base widget
-- ------------------------------------------------------------------
local Widget = {}
Widget.__index = Widget

function Widget.new(x, y, w, h)
  return setmetatable({
    x = x, y = y, w = w, h = h,
    children = {},
    visible = true,
  }, Widget)
end

function Widget:addChild(child)
  table.insert(self.children, child)
  return child
end

function Widget:draw(screen, ox, oy)
  if not self.visible then return end
  for _, child in ipairs(self.children) do
    child:draw(screen, ox + self.x, oy + self.y)
  end
end

-- returns true if handled (stops propagation)
function Widget:onTouch(localX, localY, button)
  if not self.visible then return false end
  for i = #self.children, 1, -1 do
    local child = self.children[i]
    local cx, cy = localX - child.x, localY - child.y
    if cx >= 0 and cx < child.w and cy >= 0 and cy < child.h then
      if child:onTouch(cx, cy, button) then return true end
    end
  end
  return false
end

GUI.Widget = Widget

-- ------------------------------------------------------------------
-- Panel: bordered box, optional title
-- ------------------------------------------------------------------
local Panel = setmetatable({}, { __index = Widget })
Panel.__index = Panel

function GUI.newPanel(x, y, w, h, title)
  local self = setmetatable(Widget.new(x, y, w, h), Panel)
  self.title = title
  return self
end

function Panel:draw(screen, ox, oy)
  if not self.visible then return end
  local x, y = ox + self.x, oy + self.y

  screen:fillRect(x, y, self.w, self.h, " ", GUI.COLOR.TEXT, GUI.COLOR.BG)

  -- border
  screen:text(x, y, "+" .. string.rep("-", self.w - 2) .. "+", GUI.COLOR.BORDER)
  for row = 1, self.h - 2 do
    screen:setChar(x, y + row, "|", GUI.COLOR.BORDER)
    screen:setChar(x + self.w - 1, y + row, "|", GUI.COLOR.BORDER)
  end
  screen:text(x, y + self.h - 1, "+" .. string.rep("-", self.w - 2) .. "+", GUI.COLOR.BORDER)

  if self.title then
    local label = " " .. self.title .. " "
    screen:text(x + 2, y, label, GUI.COLOR.TEXT)
  end

  Widget.draw(self, screen, ox, oy)
end

-- ------------------------------------------------------------------
-- Label
-- ------------------------------------------------------------------
local Label = setmetatable({}, { __index = Widget })
Label.__index = Label

function GUI.newLabel(x, y, text, color)
  local self = setmetatable(Widget.new(x, y, #text, 1), Label)
  self.text = text
  self.color = color or GUI.COLOR.TEXT
  return self
end

function Label:setText(text)
  self.text = text
  self.w = #text
end

function Label:draw(screen, ox, oy)
  if not self.visible then return end
  screen:text(ox + self.x, oy + self.y, self.text, self.color)
end

-- ------------------------------------------------------------------
-- Button
-- ------------------------------------------------------------------
local Button = setmetatable({}, { __index = Widget })
Button.__index = Button

function GUI.newButton(x, y, w, h, text, onClick)
  local self = setmetatable(Widget.new(x, y, w, h), Button)
  self.text = text
  self.onClick = onClick
  self.pressed = false
  return self
end

function Button:draw(screen, ox, oy)
  if not self.visible then return end
  local x, y = ox + self.x, oy + self.y
  local bg = self.pressed and GUI.COLOR.SELECTED or GUI.COLOR.BORDER_DIM
  screen:fillRect(x, y, self.w, self.h, " ", GUI.COLOR.TEXT, bg)
  local label = self.text
  if #label > self.w - 2 then label = label:sub(1, self.w - 2) end
  local textX = x + math.floor((self.w - #label) / 2)
  local textY = y + math.floor(self.h / 2)
  screen:text(textX, textY, label, GUI.COLOR.TEXT, bg)
end

function Button:onTouch(localX, localY, button)
  if localX >= 0 and localX < self.w and localY >= 0 and localY < self.h then
    if self.onClick then self.onClick(button) end
    return true
  end
  return false
end

-- ------------------------------------------------------------------
-- List: scrollable list of string items, single selection
-- ------------------------------------------------------------------
local List = setmetatable({}, { __index = Widget })
List.__index = List

function GUI.newList(x, y, w, h)
  local self = setmetatable(Widget.new(x, y, w, h), List)
  self.items = {}
  self.selectedIndex = nil
  self.scrollOffset = 0
  self.onSelect = nil
  return self
end

function List:setItems(items)
  self.items = items
  if self.selectedIndex and self.selectedIndex > #items then
    self.selectedIndex = nil
  end
end

function List:draw(screen, ox, oy)
  if not self.visible then return end
  local x, y = ox + self.x, oy + self.y
  screen:fillRect(x, y, self.w, self.h, " ", GUI.COLOR.TEXT, GUI.COLOR.BG)

  for row = 0, self.h - 1 do
    local index = row + self.scrollOffset + 1
    local item = self.items[index]
    if item then
      local selected = (index == self.selectedIndex)
      local fg = selected and GUI.COLOR.SELECTED or GUI.COLOR.TEXT
      local prefix = selected and "> " or "  "
      local line = prefix .. tostring(item)
      if #line > self.w then line = line:sub(1, self.w) end
      screen:text(x, y + row, line, fg)
    end
  end
end

function List:onTouch(localX, localY, button)
  if localX < 0 or localX >= self.w or localY < 0 or localY >= self.h then
    return false
  end
  local index = localY + self.scrollOffset + 1
  if self.items[index] then
    self.selectedIndex = index
    if self.onSelect then self.onSelect(index, self.items[index]) end
  end
  return true
end

function List:scroll(delta)
  self.scrollOffset = self.scrollOffset + delta
  if self.scrollOffset < 0 then self.scrollOffset = 0 end
  local maxOffset = math.max(0, #self.items - self.h)
  if self.scrollOffset > maxOffset then self.scrollOffset = maxOffset end
end

-- ------------------------------------------------------------------
-- Tabs: row of buttons that switch a visible child index
-- ------------------------------------------------------------------
local Tabs = setmetatable({}, { __index = Widget })
Tabs.__index = Tabs

function GUI.newTabs(x, y, w, names)
  local self = setmetatable(Widget.new(x, y, w, 1), Tabs)
  self.names = names
  self.activeIndex = 1
  self.onChange = nil
  return self
end

function Tabs:draw(screen, ox, oy)
  if not self.visible then return end
  local x, y = ox + self.x, oy + self.y
  local cursor = x
  for i, name in ipairs(self.names) do
    local label = "[" .. name .. "]"
    local fg = (i == self.activeIndex) and GUI.COLOR.SELECTED or GUI.COLOR.TEXT_DIM
    screen:text(cursor, y, label, fg)
    self["_tabend" .. i] = cursor + #label
    cursor = cursor + #label + 1
  end
end

function Tabs:onTouch(localX, localY, button)
  if localY ~= 0 then return false end
  local cursor = 0
  for i, name in ipairs(self.names) do
    local label = "[" .. name .. "]"
    if localX >= cursor and localX < cursor + #label then
      self.activeIndex = i
      if self.onChange then self.onChange(i, name) end
      return true
    end
    cursor = cursor + #label + 1
  end
  return false
end

-- ------------------------------------------------------------------
-- Viewport: hosts pre-computed 3D draw commands (from renderer3d)
-- ------------------------------------------------------------------
local Viewport = setmetatable({}, { __index = Widget })
Viewport.__index = Viewport

function GUI.newViewport(x, y, w, h)
  local self = setmetatable(Widget.new(x, y, w, h), Viewport)
  self.commands = {}
  return self
end

-- commands: array of { x, y, char, fg }
function Viewport:setCommands(commands)
  self.commands = commands
end

function Viewport:draw(screen, ox, oy)
  if not self.visible then return end
  local x, y = ox + self.x, oy + self.y
  for _, cmd in ipairs(self.commands) do
    if cmd.x >= 0 and cmd.x < self.w and cmd.y >= 0 and cmd.y < self.h then
      screen:setChar(x + cmd.x, y + cmd.y, cmd.char, cmd.fg or GUI.COLOR.TEXT)
    end
  end
end

GUI.newPanelClass = Panel
GUI.newLabelClass = Label
GUI.newButtonClass = Button
GUI.newListClass = List
GUI.newTabsClass = Tabs
GUI.newViewportClass = Viewport

return GUI

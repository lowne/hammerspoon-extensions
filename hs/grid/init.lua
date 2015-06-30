--- === hs.grid ===
---
--- Move/resize windows within a grid
---
--- The grid partitions of your screen for the purposes of window management. The default layout of the grid is 3 columns and 3 rows.
---
--- Windows that are aligned with the grid have their location and size described as a `cell`. Each cell is a table which contains the keys:
---  * x - A number containing the column of the left edge of the window
---  * y - A number containing the row of the top edge of the window
---  * w - A number containing the number of columns the window occupies
---  * h - A number containing the number of rows the window occupies
---
--- For a grid of 2x2:
---  * a cell {x = 0, y = 0, w = 1, h = 1} will be in the upper-left corner
---  * a cell {x = 1, y = 0, w = 1, h = 1} will be in the upper-right corner
---  * and so on...


local fnutils = require "hs.fnutils"
local window = require "hs.window"
local screen = require 'hs.screen'
local drawing = require'hs.drawing'
local newmodal = require'hs.hotkey'.modal.new
local log = require'hs.logger'.new('grid')

local ipairs,pairs,min,max,floor,fmod = ipairs,pairs,math.min,math.max,math.floor,math.fmod
local sformat,smatch,type,tonumber,tostring = string.format,string.match,type,tonumber,tostring
local setmetatable,rawget,rawset=setmetatable,rawget,rawset


local gridSizes = {{w=3,h=3}} -- user-defined grid sizes for each screen or geometry, default ([1]) is 3x3
local margins = {w=0,h=0}

local grid = setmetatable({},{
  __index = function(t,k)
    if k=='GRIDWIDTH' then return gridSizes[1].w
    elseif k=='GRIDHEIGTH' then return gridSizes[1].h
    elseif k=='MARGINX' then return margins.w
    elseif k=='MARGINY' then return margins.h
    else return rawget(t,k) end
  end,
  __newindex = function(t,k,v)
    if k=='GRIDWIDTH' then gridSizes[1].w=v
    elseif k=='GRIDHEIGTH' then gridSizes[1].h=v
    elseif k=='MARGINX' then margins.w=v
    elseif k=='MARGINY' then margins.h=v
    else rawset(t,k,v) end
  end,
}) -- module; metatable for legacy variables
grid.setLogLevel = log.setLogLevel



local function toRect(screen)
  local typ,rect=type(screen)
  if typ=='userdata' and screen.fullFrame then
    rect=screen:fullFrame()
  elseif typ=='table' then
    if screen.w and screen.h then rect=screen
    elseif #screen>=2 then rect={w=screen[1],h=screen[2]}
    elseif screen.x and screen.y then rect={w=screen.x,h=screen.y} -- sneaky addition for setMargins
    end
  elseif typ=='string' then
    local w,h
    w,h=smatch(screen,'(%d+)[x,-](%d+)')
    if w and h then rect={w=tonumber(w),h=tonumber(h)} end
  end
  return rect
end

local function toKey(rect) return sformat('%dx%d',rect.w,rect.h) end


--- hs.grid.setGrid(grid,screen) -> hs.grid
--- Function
--- Sets the grid size for a given screen or screen geometry
---
--- Parameters:
---  * grid - the number of columns and rows for the grid; it can be:
---    * a string in the format `CxR` (columns and rows respectively)
---    * a table in the format `{C,R}` or `{w=C,h=R}`
---    * an `hs.geometry.rect` or `hs.geometry.size` object
---  * screen - the screen or screen geometry to apply the grid to; it can be:
---    * an `hs.screen` object
---    * a number identifying the screen, as returned by `myscreen:id()`
---    * a string in the format `WWWWxHHHH` where WWWW and HHHH are the screen width and heigth in screen points
---    * a table in the format `{WWWW,HHHH}` or `{w=WWWW,h=HHHH}`
---    * an `hs.geometry.rect` or `hs.geometry.size` object describing the screen width and heigth in screen points
---    * if omitted or nil, sets the default grid, which is used when no specific grid is found for any given screen/geometry
---
--- Returns:
---   * hs.grid for method chaining
---
--- Usage:
--- hs.grid.setGrid('5x3','1920x1080') -- sets the grid to 5x3 for all screens with a 1920x1080 resolution
--- hs.grid.setGrid{4,4} -- sets the default grid to 4x4

function grid.setGrid(grid,scr)
  grid = toRect(grid)
  if not grid then error('Invalid grid',2) return end
  if scr~=nil then
    if type(scr)=='userdata' and scr.id then scr=scr:id() end
    if type(scr)~='number' then scr=toRect(scr) end
    if not scr then error('Invalid screen or geometry',2) return end
  else scr=1 end
  if type(scr)~='number' then scr=toKey(scr) end
  --    grid.w=min(grid.w,#HINTS[1]) grid.h=min(grid.h,#HINTS)
  grid.w=min(grid.w,50) grid.h=min(grid.h,50) -- cap grid to 50x50, just in case
  gridSizes[scr]=grid
  log.f('Grid for %s set to %d by %d',tostring(scr),grid.w,grid.h)
  return grid
end

--- hs.grid.setMargins(margins) -> hs.grid
--- Function
--- Sets the margins between windows
---
--- Parameters:
---  * margins - the desired margins between windows, in screen points; it can be:
---    * a string in the format `XXxYY` (horizontal and vertical margin respectively)
---    * a table in the format `{XX,YY}` or `{w=XX,h=YY}`
---    * an `hs.geometry.rect` or `hs.geometry.size` object
---
--- Returns:
---   * hs.grid for method chaining
function grid.setMargins(mar)
  mar=toRect(mar)
  if not mar then error('Invalid margins',2) return end
  margins=mar
end


























local function round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

--- hs.grid.get(win) -> cell
--- Function
--- Gets the cell describing a window
---
--- Parameters:
--- * An `hs.window` object to get the cell of
---
--- Returns:
--- * A cell object, or nil if an error occurred
function grid.get(win)
  local winframe = win:frame()
  local winscreen = win:screen()
  if not winscreen then
    return nil
  end
  local screenrect = win:screen():frame()
  local thirdscreenwidth = screenrect.w / grid.GRIDWIDTH
  local halfscreenheight = screenrect.h / grid.GRIDHEIGHT
  return {
    x = round((winframe.x - screenrect.x) / thirdscreenwidth),
    y = round((winframe.y - screenrect.y) / halfscreenheight),
    w = math.max(1, round(winframe.w / thirdscreenwidth)),
    h = math.max(1, round(winframe.h / halfscreenheight)),
  }
end

--- hs.grid.set(win, cell, screen)
--- Function
--- Sets the cell for a window, on a particular screen
---
--- Parameters:
---  * win - An `hs.window` object representing the window to operate on
---  * cell - A cell-table to apply to the window
---  * screen - An `hs.screen` object representing the screen to place the window on
---
--- Returns:
---  * None
function grid.set(win, cell, screen)
  local screenrect = screen:frame()
  local thirdscreenwidth = screenrect.w / grid.GRIDWIDTH
  local halfscreenheight = screenrect.h / grid.GRIDHEIGHT
  local newframe = {
    x = (cell.x * thirdscreenwidth) + screenrect.x,
    y = (cell.y * halfscreenheight) + screenrect.y,
    w = cell.w * thirdscreenwidth,
    h = cell.h * halfscreenheight,
  }

  newframe.x = newframe.x + grid.MARGINX
  newframe.y = newframe.y + grid.MARGINY
  newframe.w = newframe.w - (grid.MARGINX * 2)
  newframe.h = newframe.h - (grid.MARGINY * 2)

  win:setFrame(newframe)
end

--- hs.grid.snap(win)
--- Function
--- Snaps a window into alignment with the nearest grid lines
---
--- Parameters:
---  * win - A `hs.window` object to snap
---
--- Returns:
---  * None
function grid.snap(win)
  if win:isStandard() then
    local gridframe = grid.get(win)
    if gridframe then
      grid.set(win, gridframe, win:screen())
    end
  end
end

--- hs.grid.adjustNumberOfRows(delta) -> number
--- Function
--- Increases or decreases the number of rows in the grid
---
--- Parameters:
---  * delta - A number to increase or decrease the rows of the grid by. Positive to increase the number of rows, negative to decrease it
---
--- Returns:
---  * None
function grid.adjustNumberOfRows(delta)
  grid.GRIDHEIGHT = math.max(1, grid.GRIDHEIGHT + delta)
  fnutils.map(window.visibleWindows(), grid.snap)
end
-- This is for legacy purposes
grid.adjustHeight = grid.adjustNumberOfRows

--- hs.grid.adjustNumberOfColumns(delta)
--- Function
--- Increases or decreases the number of columns in the grid
---
--- Parameters:
---  * delta - A number to increase or decrease the columns of the grid by. Positive to increase the number of columns, negative to decrease it
---
--- Returns:
---  * None
function grid.adjustWidth(delta)
  grid.GRIDWIDTH = math.max(1, grid.GRIDWIDTH + delta)
  fnutils.map(window.visibleWindows(), grid.snap)
end
grid.adjustWidth = grid.adjustNumberOfColumns

--- hs.grid.adjustFocusedWindow(fn)
--- Function
--- Calls a user specified function to adjust the currently focused window's cell
---
--- Parameters:
---  * fn - A function that accepts a cell-table as its only argument. The function should modify the cell-table as needed and return nothing
---
--- Returns:
---  * None
function grid.adjustFocusedWindow(fn)
  local win = window.focusedWindow()
  local f = grid.get(win)
  if f then
    fn(f)
    grid.set(win, f, win:screen())
  end
end

--- hs.grid.maximizeWindow()
--- Function
--- Moves and resizes the currently focused window to fill the entire grid
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.maximizeWindow()
  local win = window.focusedWindow()
  local f = {x = 0, y = 0, w = grid.GRIDWIDTH, h = grid.GRIDHEIGHT}
  local winscreen = win:screen()
  if winscreen then
    grid.set(win, f, winscreen)
  end
end

--- hs.grid.pushWindowNextScreen()
--- Function
--- Moves the focused window to the next screen, retaining its cell
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowNextScreen()
  local win = window.focusedWindow()
  local gridframe = grid.get(win)
  if gridframe then
    grid.set(win, gridframe, win:screen():next())
  end
end

--- hs.grid.pushWindowPrevScreen()
--- Function
--- Moves the focused window to the previous screen, retaining its cell
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowPrevScreen()
  local win = window.focusedWindow()
  local gridframe = grid.get(win)
  if gridframe then
    grid.set(win, gridframe, win:screen():previous())
  end
end

--- hs.grid.pushWindowLeft()
--- Function
--- Moves the focused window one grid cell to the left
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowLeft()
  grid.adjustFocusedWindow(function(f) f.x = math.max(f.x - 1, 0) end)
end

--- hs.grid.pushWindowRight()
--- Function
--- Moves the focused window one cell to the right
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowRight()
  grid.adjustFocusedWindow(function(f) f.x = math.min(f.x + 1, grid.GRIDWIDTH - f.w) end)
end

--- hs.grid.resizeWindowWider()
--- Function
--- Resizes the focused window to be one cell wider
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
---
--- Notes:
---  * If the window hits the right edge of the screen and is asked to become wider, its left edge will shift further left
function grid.resizeWindowWider()
  grid.adjustFocusedWindow(function(f)
    if f.w + f.x >= grid.GRIDWIDTH and f.x > 0 then
      f.x = f.x - 1
    end
    f.w = math.min(f.w + 1, grid.GRIDWIDTH - f.x)
  end)
end

--- hs.grid.resizeWindowThinner()
--- Function
--- Resizes the focused window to be one cell thinner
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.resizeWindowThinner()
  grid.adjustFocusedWindow(function(f) f.w = math.max(f.w - 1, 1) end)
end

--- hs.grid.pushWindowDown()
--- Function
--- Moves the focused window one grid cell down the screen
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowDown()
  grid.adjustFocusedWindow(function(f) f.y = math.min(f.y + 1, grid.GRIDHEIGHT - f.h) end)
end

--- hs.grid.pushWindowUp()
--- Function
--- Moves the focused window one grid cell up the screen
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.pushWindowUp()
  grid.adjustFocusedWindow(function(f) f.y = math.max(f.y - 1, 0) end)
end

--- hs.grid.resizeWindowShorter()
--- Function
--- Resizes the focused window so its bottom edge moves one grid cell higher
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grid.resizeWindowShorter()
  grid.adjustFocusedWindow(function(f) f.y = f.y - 0; f.h = math.max(f.h - 1, 1) end)
end

--- hs.grid.resizeWindowTaller()
--- Function
--- Resizes the focused window so its bottom edge moves one grid cell lower
---
--- Parameters:
---  * If the window hits the bottom edge of the screen and is asked to become taller, its top edge will shift further up
---
--- Returns:
---  * None
---
--- Notes:
function grid.resizeWindowTaller()
  grid.adjustFocusedWindow(function(f)
    if f.y + f.h >= grid.GRIDHEIGHT and f.y > 0 then
      f.y = f.y -1
    end
    f.h = math.min(f.h + 1, grid.GRIDHEIGHT - f.y)
  end)
end

return grid





--- hs.grid.MARGINX = 5
--- Variable
--- The margin between each window horizontally, measured in screen points (typically a point is a pixel on a non-retina screen, or two pixels on a retina screen
--- 
--- Notes:
---   * Legacy variable; use `setMargins` instead
--grid.MARGINX = 5

--- hs.grid.MARGINY = 5
--- Variable
--- The margin between each window vertically, measured in screen points (typically a point is a pixel on a non-retina screen, or two pixels on a retina screen)
--- 
--- Notes:
---   * Legacy variable; use `setMargins` instead
--grid.MARGINY = 5

--- hs.grid.GRIDHEIGHT = 3
--- Variable
--- The number of rows in the grid
--- 
--- Notes:
---   * Legacy variable; use `setGrid` instead
--grid.GRIDHEIGHT = 3

--- hs.grid.GRIDWIDTH = 3
--- Variable
--- The number of columns in the grid
--- 
--- Notes:
---   * Legacy variable; use `setGrid` instead
--grid.GRIDWIDTH = 3

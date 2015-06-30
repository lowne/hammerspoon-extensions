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
    elseif k=='GRIDHEIGHT' then return gridSizes[1].h
    elseif k=='MARGINX' then return margins.w
    elseif k=='MARGINY' then return margins.h
    else return rawget(t,k) end
  end,
  __newindex = function(t,k,v)
    if k=='GRIDWIDTH' then gridSizes[1].w=v log.f('Default grid set to %d by %d',gridSizes[1].w,gridSizes[1].h)
    elseif k=='GRIDHEIGHT' then gridSizes[1].h=v log.f('Default grid set to %d by %d',gridSizes[1].w,gridSizes[1].h)
    elseif k=='MARGINX' then margins.w=v log.f('Window margin set to %d,%d',margins.w,margins.h)
    elseif k=='MARGINY' then margins.h=v log.f('Window margin set to %d,%d',margins.w,margins.h)
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
  if scr==1 then log.f('Default grid set to %d by %d',grid.w,grid.h)
  else log.f('Grid for %s set to %d by %d',tostring(scr),grid.w,grid.h) end
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
  log.f('Window margin set to %d,%d',margins.w,margins.h)
end


--- hs.grid.getGrid(screen) -> ncolumns, nrows
--- Function
--- Gets the defined grid size for a given screen or screen geometry
---
--- Parameters:
---  * screen - the screen or screen geometry to get the grid of; it can be:
---    * an `hs.screen` object
---    * a number identifying the screen, as returned by `myscreen:id()`
---    * a string in the format `WWWWxHHHH` where WWWW and HHHH are the screen width and heigth in screen points
---    * a table in the format `{WWWW,HHHH}` or `{w=WWWW,h=HHHH}`
---    * an `hs.geometry.rect` or `hs.geometry.size` object describing the screen width and heigth in screen points
---    * if omitted or nil, gets the default grid, which is used when no specific grid is found for any given screen/geometry
---
--- Returns:
---   * the number of columns in the grid
---   * the number of rows in the grid
---
--- Notes:
---   * if a grid was not set for the specified screen or geometry, the default grid will be returned
---
--- Usage:
--- local w,h = hs.grid.getGrid('1920x1080') -- gets the defined grid for all screens with a 1920x1080 resolution
--- local w,h=hs.grid.getGrid() hs.grid.setGrid{w+2,h} -- increases the number of columns in the default grid by 2

function grid.getGrid(scr)
  if scr~=nil then
    local scrobj
    if type(scr)=='userdata' and scr.id then scrobj=scr scr=scr:id() end
    if type(scr)~='number' then scr=toRect(scr) end
    if not scr then error('Invalid screen or geometry',2) return end
    if type(scr)=='number' then
      -- test with screen id
      if gridSizes[scr] then return gridSizes[scr].w,gridSizes[scr].h end
      -- check if there's a geometry matching the current resolution
      if not scrobj then
        local screens=screen.allScreens()
        for _,s in ipairs(screens) do
          if s:id()==scr then scrobj=s break end
        end
      end
      if scrobj then
        local screenframe=scrobj:fullFrame()
        scr=toKey(screenframe)
      end
    else
      scr=toKey(scr)
    end
    if gridSizes[scr] then return gridSizes[scr].w,gridSizes[scr].h end
  end
  return gridSizes[1].w,gridSizes[1].h
end




local function round(num, idp)
  local mult = 10^(idp or 0)
  return floor(num * mult + 0.5) / mult
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
  local gridw,gridh = grid.getGrid(winscreen)
  local screenrect = win:screen():frame()
  local cellw, cellh = screenrect.w/gridw, screenrect.h/gridh
  return {
    x = round((winframe.x - screenrect.x) / cellw),
    y = round((winframe.y - screenrect.y) / cellh),
    w = max(1, round(winframe.w / cellw)),
    h = max(1, round(winframe.h / cellh)),
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
  local gridw,gridh = grid.getGrid(screen)
  -- sanitize, because why not
  cell.x=max(0,min(cell.x,gridw-1)) cell.y=max(0,min(cell.y,gridh-1))
  cell.w=max(1,min(cell.w,gridw-cell.x)) cell.h=max(1,min(cell.h,gridh-cell.y))
  local cellw, cellh = screenrect.w/gridw, screenrect.h/gridh
  local newframe = {
    x = (cell.x * cellw) + screenrect.x + margins.w,
    y = (cell.y * cellh) + screenrect.y + margins.h,
    w = cell.w * cellw - (margins.w * 2),
    h = cell.h * cellh - (margins.h * 2),
  }

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


--- hs.grid.adjustWindow(fn, window) -> hs.grid
--- Function
--- Calls a user specified function to adjust a window's cell
---
--- Parameters:
---  * fn - A function that accepts a cell-table as its only argument. The function should modify the cell-table as needed and return nothing
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.adjustWindow(fn,win)
  if not win then win = window.focusedWindow() end
  local f = grid.get(win)
  if f then
    fn(f)
    grid.set(win, f, win:screen())
  end
  return grid
end

--- hs.grid.adjustFocusedWindow(fn) -> hs.grid
--- Function
--- Calls a user specified function to adjust the currently focused window's cell
---
--- Parameters:
---  * fn - A function that accepts a cell-table as its only argument. The function should modify the cell-table as needed and return nothing
---
--- Returns:
---  * The `hs.grid` module for method chaining
---
--- Notes:
---  * Legacy function, use `adjustWindow` instead
grid.adjustFocusedWindow=grid.adjustWindow

--- hs.grid.maximizeWindow(window) -> hs.grid
--- Function
--- Moves and resizes a window to fill the entire grid
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.maximizeWindow(win)
  if not win then win = window.focusedWindow() end
  local winscreen = win:screen()
  if winscreen then
    local w,h = grid.getGrid(winscreen)
    local f = {x = 0, y = 0, w = w, h = h}
    grid.set(win, f, winscreen)
  end
  return grid
end

--- hs.grid.pushWindowNextScreen(window) -> hs.grid
--- Function
--- Moves a window to the next screen, snapping it to the screen's grid
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowNextScreen(win)
  if not win then win = window.focusedWindow() end
  local winscreen=win:screen()
  if winscreen then
    win:moveToScreen(winscreen:next())
    grid.snap(win)
  end
  return grid
    --  local win = window.focusedWindow()
    --  local gridframe = grid.get(win)
    --  if gridframe then
    --    grid.set(win, gridframe, win:screen():next())
    --  end
end

--- hs.grid.pushWindowPrevScreen(window) -> hs.grid
--- Function
--- Moves a window to the previous screen, snapping it to the screen's grid
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowPrevScreen(win)
  if not win then win = window.focusedWindow() end
  local winscreen=win:screen()
  if winscreen then
    win:moveToScreen(winscreen:previous())
    grid.snap(win)
  end
  return grid
    --  local win = window.focusedWindow()
    --  local gridframe = grid.get(win)
    --  if gridframe then
    --    grid.set(win, gridframe, win:screen():previous())
    --  end
end

--- hs.grid.pushWindowLeft(window) -> hs.grid
--- Function
--- Moves a window one grid cell to the left
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowLeft(win)
  --  grid.adjustWindow(function(f) f.x = max(f.x - 1, 0) end, win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  local f = grid.get(win)
  local nx = f.x-1
  if nx<0 then
    -- go to left screen
    local newscreen=win:screen():toWest()
    if newscreen then
      local neww = grid.getGrid(newscreen)
      f.x = neww-f.w
      grid.set(win,f,newscreen)
    end
  else grid.adjustWindow(function(f)f.x=nx end, win) end
  return grid
end

--- hs.grid.pushWindowRight(window) -> hs.grid
--- Function
--- Moves a window one cell to the right
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowRight(win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  --  grid.adjustWindow(function(f) f.x = min(f.x + 1, w - f.w) end, win)
  local f = grid.get(win)
  local nx = f.x+1
  if nx+f.w>w then
    -- go to right screen
    local newscreen=win:screen():toEast()
    if newscreen then
      f.x = 0
      grid.set(win,f,newscreen)
    end
  else grid.adjustWindow(function(f)f.x=nx end, win) end
  return grid
end

--- hs.grid.resizeWindowWider(window) -> hs.grid
--- Function
--- Resizes a window to be one cell wider
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
---
--- Notes:
---  * If the window hits the right edge of the screen and is asked to become wider, its left edge will shift further left
function grid.resizeWindowWider(win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  grid.adjustWindow(function(f)
    if f.w + f.x >= w and f.x > 0 then
      f.x = f.x - 1
    end
    f.w = min(f.w + 1, w - f.x)
  end, win)
  return grid
end

--- hs.grid.resizeWindowThinner(window) -> hs.grid
--- Function
--- Resizes a window to be one cell thinner
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.resizeWindowThinner(win)
  grid.adjustWindow(function(f) f.w = max(f.w - 1, 1) end, win)
  return grid
end

--- hs.grid.pushWindowDown(window) -> hs.grid
--- Function
--- Moves a window one grid cell down the screen
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowDown(win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  --  grid.adjustWindow(function(f) f.y = min(f.y + 1, h - f.h) end, win)
  local f = grid.get(win)
  local ny = f.y+1
  if ny+f.h>h then
    -- go to screen below
    local newscreen=win:screen():toSouth()
    if newscreen then
      f.y = 0
      grid.set(win,f,newscreen)
    end
  else grid.adjustWindow(function(f)f.y=ny end, win) end
  return grid
end

--- hs.grid.pushWindowUp(window) -> hs.grid
--- Function
--- Moves a window one grid cell up the screen
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.pushWindowUp(win)
  --  grid.adjustWindow(function(f) f.y = max(f.y - 1, 0) end, win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  local f = grid.get(win)
  local ny = f.y-1
  if ny<0 then
    -- go to screen above
    local newscreen=win:screen():toNorth()
    if newscreen then
      local _,newh = grid.getGrid(newscreen)
      f.y = newh-f.h
      grid.set(win,f,newscreen)
    end
  else grid.adjustWindow(function(f)f.y=ny end, win) end
  return grid
end

--- hs.grid.resizeWindowShorter(window) -> hs.grid
--- Function
--- Resizes a window so its bottom edge moves one grid cell higher
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
function grid.resizeWindowShorter(win)
  grid.adjustWindow(function(f) f.y = f.y - 0; f.h = max(f.h - 1, 1) end, win)
end

--- hs.grid.resizeWindowTaller(window) -> hs.grid
--- Function
--- Resizes a window so its bottom edge moves one grid cell lower
---
--- Parameters:
---  * window - An `hs.window` object to act on; if omitted, the focused window will be used
---
--- Returns:
---  * The `hs.grid` module for method chaining
---
--- Notes:
---  * If the window hits the bottom edge of the screen and is asked to become taller, its top edge will shift further up
function grid.resizeWindowTaller(win)
  if not win then win = window.focusedWindow() end
  local w,h = grid.getGrid(win:screen())
  grid.adjustWindow(function(f)
    if f.y + f.h >= h and f.y > 0 then
      f.y = f.y -1
    end
    f.h = min(f.h + 1, h - f.y)
  end, win)
end






































-- Legacy stuff below


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

--- hs.grid.adjustNumberOfRows(delta) -> number
--- Function
--- Increases or decreases the number of rows in the default grid, then snaps all windows to the new grid
---
--- Parameters:
---  * delta - A number to increase or decrease the rows of the default grid by. Positive to increase the number of rows, negative to decrease it
---
--- Returns:
---  * None
---
--- Notes:
---  * Legacy function; use `getGrid` and `setGrid` instead
---  * Screens with a specified grid (via `setGrid`) won't be affected, as this function only alters the default grid
function grid.adjustNumberOfRows(delta)
  grid.GRIDHEIGHT = max(1, grid.GRIDHEIGHT + delta)
  fnutils.map(window.visibleWindows(), grid.snap)
end
-- This is for legacy purposes
grid.adjustHeight = grid.adjustNumberOfRows

--- hs.grid.adjustNumberOfColumns(delta)
--- Function
--- Increases or decreases the number of columns in the default grid, then snaps all windows to the new grid
---
--- Parameters:
---  * delta - A number to increase or decrease the columns of the default grid by. Positive to increase the number of columns, negative to decrease it
---
--- Returns:
---  * None
---
--- Notes:
---  * Legacy function; use `getGrid` and `setGrid` instead
---  * Screens with a specified grid (via `setGrid`) won't be affected, as this function only alters the default grid
function grid.adjustWidth(delta)
  grid.GRIDWIDTH = max(1, grid.GRIDWIDTH + delta)
  fnutils.map(window.visibleWindows(), grid.snap)
end
grid.adjustWidth = grid.adjustNumberOfColumns

return grid

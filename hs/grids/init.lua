--- === hs.grids ===
---
--- Modal hotkey window resize on per-screen grids
--- Currently, only QWERTY layouts are supported and the maximum grid size is 8x5 (and that uses the function keys, so set
--- System Preferences/Keyboard accordingly)

-- TODO allow passing custom keyboard map for non-qwerty layouts

local ipairs,pairs,min,max,floor,fmod = ipairs,pairs,math.min,math.max,math.floor,math.fmod
local sformat,smatch,type,tonumber = string.format,string.match,type,tonumber
local dr = require'hs.drawing'
local screenwatcher=require'hs.screenwatcher'
local focusedWindow=require'hs.window'.focusedWindow
local newmodal=require'hs.hotkey'.modal.new
local log = require'hs.logger'.new('grids')
local grids = {setLogLevel = function(lvl) log.setLogLevel(lvl)end} -- module

local screens, currentScreen, currentWindow, highlight = {}
local HINTS={{'f1','f2','f3','f4','f5','f6','f7','f8'},
  {'1','2','3','4','5','6','7','8'},
  {'Q','W','E','R','T','Y','U','I'},
  {'A','S','D','F','G','H','J','K'},
  {'Z','X','C','V','B','N','M',','}
}

local HINTS_ROWS = {{4},{3,4},{3,4,5},{2,3,4,5},{1,2,3,4,5}}

local COLOR_BLACK={red=0,green=0,blue=0,alpha=1}
local COLOR_WHITE={red=1,green=1,blue=1,alpha=1}
local COLOR_DARKOVERLAY={red=0,green=0,blue=0,alpha=0.25}
local COLOR_HIGHLIGHT={red=0.8,green=0.75,blue=0,alpha=0.55}
local COLOR_SELECTED={red=0.2,green=0.75,blue=0,alpha=0.4}
local COLOR_YELLOW={red=0.8,green=0.75,blue=0,alpha=1}

local function toRect(screen,cap)
  local typ,rect=type(screen)
  if typ=='userdata' and screen.fullFrame then
    rect=screen:fullFrame()
  elseif typ=='table' then
    if screen.w and screen.h then rect=screen
    elseif #screen>=2 then rect={w=screen[1],h=screen[2]}
    end
  elseif typ=='string' then
    local w,h
    w,h=smatch(screen,'(%d+)[x,-](%d+)')
    if w and h then rect={w=tonumber(w),h=tonumber(h)} end
  end
  if cap and rect then rect.w=min(rect.w,#HINTS[1]) rect.h=min(rect.h,#HINTS) end
  return rect
end

local function toKey(rect) return sformat('%dx%d',rect.w,rect.h) end

local gridSizes = {} -- user-defined grid sizes for each screen geometry

--- hs.grids.setGrid(screen, grid) -> hs.grids
--- Function
--- Sets the grid size for a given screen geometry
---
--- Parameters:
---  * screen - the screen geometry to apply the grid to; it can be:
---    * an `hs.screen` object
---    * an `hs.geometry.rect` object
---    * a string in the format `WWWWxHHHH` where WWWW and HHHH are the screen width and heigth in pixels
--     * if omitted, the current resolution of the main screen will be used
--- * grid - a string in the format `CxR` where C and R are the desired number of columns and rows
---
--- Returns:
---   * hs.grids for method chaining
---
--- Usage:
--- hs.grids.setGrid('1920x1080','5x3') -- sets the resizing grid to 5x3 for any screens with a 1920x1080 resolution
--- hs.grids.setGrid(hs.screens.mainScreen(),'4x4') -- sets the grid to 4x4 for the main screen (at its current resolution)
function grids.setGrid(screen,grid)
  if (not grid and type(screen)=='string') then
    grid=screen
    screen=nil
  end
  if screen==nil then
    screen=require'hs.screen'.mainScreen()
  end
  local screenFrame = toRect(screen)
  local grid = toRect(grid,true)
  if not screenFrame or not grid then error('Invalid screen/frame or grid',2)return end
  local key=toKey(screenFrame)
  grid.w=min(grid.w,#HINTS[1]) grid.h=min(grid.h,#HINTS)
  gridSizes[key]=grid
  log.f('Grid for %s set to %d by %d',key,grid.w,grid.h)
  return grids
end
local elements = {} -- rects

local function getScreenKey(screen)
  local frame=screen:frame()
  return frame.x..'x'..frame.y
end


local resizing-- modal hotkey
local function setGrids(screens)
  if resizing then resizing:exit() end
  for i,screen in ipairs(screens) do
    local key = getScreenKey(screen)
    local frame = screen:frame()
    local gridsize = gridSizes[toKey(screen:fullFrame())] or (frame.h>frame.w and {w=3,h=4} or {w=4,h=3})
    local xstep = frame.w/gridsize.w
    local ystep = frame.h/gridsize.h
    log.f('Screen #%d (%s) -> grid %d by %d (%dx%d cells)',i,key,gridsize.w,gridsize.h,xstep,ystep)
    local htf={w=500,h=100}
    htf.x=frame.x+frame.w/2-htf.w/2 htf.y=frame.y+frame.h/2-htf.h/2
    if fmod(gridsize.h,2)==1 then htf.y=htf.y-ystep/2 end
    local howtorect=dr.rectangle(htf)
    howtorect:setFill(true) howtorect:setFillColor(COLOR_DARKOVERLAY) howtorect:setStrokeWidth(5)
    local howtotext=dr.text(htf,'    ←→↑↓:select screen\n  space:fullscreen esc:exit')
    howtotext:setTextSize(40) howtotext:setTextColor(COLOR_WHITE)
    elements[key] = {left=getScreenKey(screen:toWest() or screen),
      up=getScreenKey(screen:toNorth() or screen),
      right=getScreenKey(screen:toEast() or screen),
      down=getScreenKey(screen:toSouth() or screen),
      screen=screen, frame=frame,
      howto={rect=howtorect,text=howtotext},
      hints={}}
    local ix=0
    for x=frame.x,frame.x+frame.w-2,xstep do
      ix=ix+1
      local iy=0
      for y=frame.y,frame.y+frame.h-2,ystep do
        iy=iy+1
        local elem = {x=x,y=y,w=xstep,h=ystep}
        local rect=dr.rectangle(elem)
        rect:setFill(true) rect:setFillColor(COLOR_DARKOVERLAY)
        rect:setStroke(true) rect:setStrokeColor(COLOR_BLACK) rect:setStrokeWidth(5)
        elem.rect = rect
        elem.hint = HINTS[HINTS_ROWS[gridsize.h][iy]][ix]
        local text=dr.text({x=x+xstep/2-100,y=y+ystep/2-100,w=200,h=200},elem.hint)
        text:setTextSize(200)--ystep/3*2)
        text:setTextColor(COLOR_WHITE)
        elem.text=text
        log.vf('[%d] %s %d,%dx%d,%d',i,elem.hint,elem.x,elem.y,elem.x+elem.w,elem.y+elem.h)
        elements[key].hints[elem.hint] = elem
      end
    end
  end
end



local function showGrid(screen)
  if not screen or not elements[screen] then log.e('Cannot obtain current screen: '..screen) return end
  local e = elements[screen].hints
  for _,elem in pairs(e) do elem.rect:show() elem.text:show() end
  elements[screen].howto.rect:show() elements[screen].howto.text:show()
end
local function hideGrid(screen)
  if not screen or not elements[screen] then --[[log.e('Cannot obtain current screen') --]] return end
  elements[screen].howto.rect:hide() elements[screen].howto.text:hide()
  local e = elements[screen].hints
  for _,elem in pairs(e) do elem.rect:hide() elem.text:hide() end
end


local initialized
local function _start()
  if initialized then return end
  screenwatcher.subscribe(setGrids)
  resizing=newmodal()
  local function showHighlight()
    if highlight then highlight:delete() end
    highlight = dr.rectangle(currentWindow:frame())
    highlight:setFill(true) highlight:setFillColor(COLOR_HIGHLIGHT)
    highlight:setStroke(true) highlight:setStrokeColor(COLOR_YELLOW) highlight:setStrokeWidth(30)
    highlight:show()
  end
  function resizing:entered()
    currentWindow=focusedWindow()
    if not currentWindow then log.w('Cannot get current window, aborting') resizing:exit() return end
    log.df('Start moving %s [%s]',currentWindow:subrole(),currentWindow:application():title())

    --  if window:isFullScreen() then resizing:exit() alert('(')return end
    --TODO check fullscreen
    currentScreen = getScreenKey(currentWindow:screen())
    showHighlight()
    showGrid(currentScreen)
  end
  local selectedElem
  local function clearSelection()
    if selectedElem then
      selectedElem.rect:setFillColor(COLOR_DARKOVERLAY)
      selectedElem = nil
    end
  end
  function resizing:exited()
    if highlight then highlight:delete() highlight=nil end
    clearSelection()
    hideGrid(currentScreen)
  end
  resizing:bind({},'escape',function()log.d('abort move')resizing:exit()end)
  resizing:bind({},'space',function()
    --    local wasfs=currentWindow:isFullScreen()
    log.d('toggle fullscreen')currentWindow:toggleFullScreen()
    if currentWindow:isFullScreen() then resizing:exit()
      --    elseif not wasfs then currentWindow:setFrame(currentWindow:screen():frame(),0) resizing:exit()
    end
  end)
  for _,dir in ipairs({'left','right','up','down'}) do
    resizing:bind({},dir,function()
      log.d('select screen '..dir)
      clearSelection() hideGrid(currentScreen)
      currentScreen=elements[currentScreen][dir]
      currentWindow:moveToScreen(elements[currentScreen].screen,0)
      showHighlight()
      showGrid(currentScreen)
    end)
  end
  local function hintPressed(c)
    local elem = elements[currentScreen].hints[c]
    if not elem then return end
    if not selectedElem then
      selectedElem = elem
      elem.rect:setFillColor(COLOR_SELECTED)
    else
      local x1,x2,y1,y2
      x1,x2 = min(selectedElem.x,elem.x),max(selectedElem.x,elem.x)
      y1,y2 = min(selectedElem.y,elem.y),max(selectedElem.y,elem.y)
      local frame={x=x1,y=y1,w=x2-x1+elem.w,h=y2-y1+elem.h}
      currentWindow:setFrame(frame,0)
      log.f('move to %d,%d[%dx%d]',frame.x,frame.y,frame.w,frame.h)
      resizing:exit()
    end
  end
  for _,row in ipairs(HINTS) do
    for _,c in ipairs(row) do
      resizing:bind({},c,function()hintPressed(c) end)
    end
  end
  initialized=true
end

--- hs.grids.show()
--- Function
--- Shows the resizing grid and starts the modal resizing process for the focused window.
--- In most cases this function should be invoked via `hs.hotkey.bind` with some keyboard shortcut.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grids.show()
  if not initialized then _start()
  else resizing:exit() end
  resizing:enter()
end

--- hs.grids.stop()
--- Function
--- Cleanup when you're done (no need to call this in most cases)
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function grids.stop()
  if resizing then resizing:exit() end
  screenwatcher.unsubscribe(setGrids)
  initialized=nil
end

return grids

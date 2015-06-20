local log=require'hs.logger'.new('wtiling',5)

-- focus left/right/up/down
local intersectionRect=require'hs.geometry'.intersectionRect
local contains, indexOf = require'hs.fnutils'.contains, require'hs.fnutils'.indexOf
local tremove,tsort,ipairs,pairs,min = table.remove,table.sort,ipairs,pairs,math.min
local focusedWindow=require'hs.window'.focusedWindow
local orderedWindows=require'hs.window'.orderedWindows
local sleep=require'hs.timer'.usleep
local function intersects(rect1,rect2)
  local r = intersectionRect(rect1,rect2)
  return (r.w*r.h)>0
end

local windowtiling={}

local function closestWindows(w,dir,wins)
  local f=w:frame()
  local c={x=f.x+f.w/2,y=f.y+f.h/2}
  local res={}
  for _,wt in ipairs(wins) do
    if w~=wt then
      local ft=wt:frame()
      local ct={x=ft.x+ft.w/2,y=ft.y+ft.h/2}
      local dx,dy=c.x-ct.x,c.y-ct.y
      local d=dx*dx+dy*dy
      --      print(dir,ct.x,c.x)
      if dir=='North' and ct.y<c.y then res[#res+1]={w=wt,d=d}
      elseif dir=='South' and ct.y>c.y then res[#res+1]={w=wt,d=d}
      elseif dir=='East' and ct.x>c.x then res[#res+1]={w=wt,d=d}
      elseif dir=='West' and ct.x<c.x then res[#res+1]={w=wt,d=d} end
    end
  end
  tsort(res,function(a,b) return a.d<b.d end)
  local r={}
  for _,e in ipairs(res) do r[#r+1]=e.w hs.alert('distance '..e.d/100)end
  return r
end

function windowtiling:focus(dir,excludeIntersectingWindows,closest)
  local win = focusedWindow()
  if not win then win=orderedWindows()[1] end
  if not win then log.w('Cannot obtain focused window') return end
  local frame=win:frame()
  local allwins = self.ww and self.ww:getWindows() or self.wf:filterWindows(orderedWindows())
  --  local targets = (all or not self.ww) and win['windowsTo'..dir](win) or closestWindows(win,dir,allwins)
  local targets = closestWindows(win,dir,allwins)

  log.vf('find windows %s, %d candidates of %d total',dir,#targets,#allwins)
  --remove intersecting windows from the candidates
  if excludeIntersectingWindows then
    for i = #targets,1,-1 do
      if intersects(frame,targets[i]:frame()) then
        tremove(targets,i)
      end
    end
    log.vf('removed intersections, %d candidates remaining',#targets)
  end
  -- go through each candidate, stop when the frontmost is found
  local found
  if closest then found = targets[1]
  else
    -- find frontmost window among candidates
    for i,candidate in ipairs(targets) do
      local zorder = indexOf(allwins,candidate)
      if not zorder then log.e('no zorder') break end
      -- see if there's any competition
      local competition
      for i=1,zorder-1 do
        competition=contains(targets,allwins[i]) and intersects(candidate:frame(),allwins[i]:frame())
        if competition then break end
      end
      if not competition then
        found=candidate
        break
      end
    end
  end
  if found then
    log.df('Focusing frontmost %swindow in direction %s',excludeIntersectingWindows and 'non-intersecting ' or '',dir)
    found:focus()
  else
    log.d('No suitable windows in direction '..dir)
  end
end

function windowtiling.sendToBack()
  log.d('Sending focused window to back')
  local win = focusedWindow()
  if not win then win=orderedWindows()[1] end
  local frame=win:frame()
  local allwins = orderedWindows()
  local zorder = indexOf(allwins,win)
  --  for i=#allwins,zorder+1,-1 do
  for i=#allwins,1,-1 do
    if i~=zorder then
      --bring forward if it intersects
      if intersects(frame,allwins[i]:frame()) then
        allwins[i]:focus()
        sleep(20)
      end
    end
  end
end

local function slice(t,s,e)
  local r={}
  for i=s,e do
    local e=t[i]
    if e then r[#r+1]=e end
  end
  return r
end
local function relToAbs(rect,screenFrame)
  return{ x = screenFrame.x+(rect.x*screenFrame.w),
    y = screenFrame.y+(rect.y*screenFrame.h),
    w = rect.w*screenFrame.w,
    h = rect.h*screenFrame.h}
end

local function makeRow(wins,rectToFill,isVertical)
  if #wins==0 then return {},0,0 end
  local layoutSide = isVertical and rectToFill.h or rectToFill.w
  local aspect = 1
  local row = {}
  local totalArea = 0
  for _, win in ipairs(wins) do
    totalArea = totalArea + win.area
  end
  local orthoSide = totalArea/layoutSide
  local x,y = rectToFill.x, rectToFill.y
  for i,win in ipairs(wins) do
    local side = win.area/orthoSide--totalArea * side
    local frame={window = win.window, x=x, y=y}
    if isVertical then
      frame.w=orthoSide frame.h=side y=y+side
    else
      frame.w=side frame.h=orthoSide x=x+side
    end
    row[i] = frame
    aspect = min(aspect, orthoSide<side and orthoSide/side or side/orthoSide)
  end
  return row,orthoSide,aspect
end
local function tileWindows(windows)
  local isVertical = windows.isVertical
  local irow = 1
  local toFill = {w=1,h=1,x=0,y=0}
  local row, orthoSide,aspect = makeRow(slice(windows,1,1),toFill,isVertical)
  for i=2,#windows do
    local testRow,testOrthoSide,testAspect = makeRow(slice(windows,irow,i),toFill,isVertical)
    if testAspect>=aspect then
      --good, let's keep it
      row,orthoSide,aspect = testRow,testOrthoSide,testAspect
    else
      --time to switch, save the row
      for i,win in ipairs(row) do windows[i+irow-1].newFrame = relToAbs(win,windows.screenFrame) end
      if isVertical then
        toFill.x=toFill.x+orthoSide
        toFill.w=toFill.w-orthoSide
      else
        toFill.y=toFill.y+orthoSide
        toFill.h=toFill.h-orthoSide
      end
      isVertical = not isVertical
      irow = i
      row,orthoSide,aspect = makeRow(slice(windows,irow,i),toFill,isVertical)
    end
  end
  -- save the last row
  for i,win in ipairs(row) do windows[i+irow-1].newFrame = relToAbs(win,windows.screenFrame) end
  for i,win in ipairs(windows) do
    log.vf('%d: [%s]%s %d,%d-%dx%d to %d,%d-%dx%d',i,win.window:application():title(),win.window:title(),
      win.originalFrame.x,win.originalFrame.y,win.originalFrame.w,win.originalFrame.h,
      win.newFrame.x,win.newFrame.y,win.newFrame.w,win.newFrame.h)
    win.window:setFrame(win.newFrame,0)
  end
end


local screens={}
function windowtiling:tileWindows()
  log.d('tile windows')
  screens={}
  local wins = self.ww and self.ww:getWindows() or self.wf:filterWindows(orderedWindows())
  for _,w in ipairs(wins) do
    local id=w:screen():id()
    if not screens[id] then
      local frame=w:screen():frame()
      screens[id]={screenFrame=frame,area=0,isVertical=frame.w>=frame.h}--??
    end
    local frame=w:frame()
    screens[id][#screens[id]+1]={window=w,originalFrame=frame,area=frame.w*frame.h}
    screens[id].area=screens[id].area+frame.w*frame.h
  end
  local function sort(r1,r2)
    local x1,x2,y1,y2 = r1.originalFrame.x,r2.originalFrame.x,r1.originalFrame.y,r2.originalFrame.y
    if x1<x2 then return true
    elseif x1==x2 then
      if y1<y2 then return true
      elseif y1==y2 then
        return r1.area>r2.area
      else return false end
    else return false end
  end
  for _,windows in pairs(screens) do
    tsort(windows,sort)
    for _,win in ipairs(windows) do win.area = win.area/windows.area end
    tileWindows(windows)
  end
end



function windowtiling.new(windowfilter)
  local windowwatcher
  if windowfilter==nil then
    windowfilter=hs.windowfilter.default
  elseif type(windowfilter)=='table' then
    if windowfilter.isWindowAllowed then
    elseif windowfilter.getWindows then
      windowwatcher=windowfilter windowfilter=nil
    else windowfilter=nil end
  end
  if not windowfilter and not windowwatcher then error('windowfilter must be nil, a hs.windowfilter object, or a hs.windowwatcher object') end
  return setmetatable({wf=windowfilter,ww=windowwatcher},{__index=windowtiling})
end

for _,d in ipairs{'North','South','East','West'}do
  windowtiling['focus'..d]=function(self,excludeintersecting,closest) self:focus(d,excludeintersecting,closest)end
end

--function windowtiling:focusNorth(all)self:focus('North',all)end
--function windowtiling:focusSouth(all)self:focus('South',all)end
--function windowtiling:focusEast(all)self:focus('East',all)end
--function windowtiling:focusWest(all)self:focus('West',all)end

return windowtiling

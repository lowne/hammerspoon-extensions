local log=hs.logger.new('wtiling',5)

-- focus left/right/up/down
local intersectionRect=hs.geometry.intersectionRect
local contains, indexOf = hs.fnutils.contains, hs.fnutils.indexOf
local tremove, ipairs = table.remove, ipairs
local focusedWindow=hs.window.focusedWindow
local orderedWindows=hs.window.orderedWindows

local function intersects(rect1,rect2)
  local r = intersectionRect(rect1,rect2)
  return (r.w*r.h)>0
end

local windowtiling={}
function windowtiling:focus(dir,excludeIntersectingWindows)
  local win = focusedWindow()
  if not win then win=orderedWindows()[1] end
  local frame=win:frame()
  local allwins = self.ww and self.ww:getWindows() or self.wf:filterWindows(orderedWindows())
  local targets = win['windowsTo'..dir](win)
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
  if found then
    log.df('Focusing frontmost %swindow in direction %s',excludeIntersectingWindows and 'non-intersecting ' or '',dir)
    found:focus()
  else
    log.d('No suitable windows in direction '..dir)
  end
end

local sleep=hs.timer.usleep
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

function windowtiling:focusNorth(all)self:focus('North',all)end
function windowtiling:focusSouth(all)self:focus('South',all)end
function windowtiling:focusEast(all)self:focus('East',all)end
function windowtiling:focusWest(all)self:focus('West',all)end

return windowtiling

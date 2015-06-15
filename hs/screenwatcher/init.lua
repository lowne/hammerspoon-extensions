--- === hs.screenwatcher ===
---
--- A singleton hs.screen.watcher (and companion hs.caffeinate.watcher) for multiple consumption

local log=hs.logger.new('swatcher',5)
local screenwatcher={delay=3}

local swinstance,pwinstance
local substarted,subdone={},{}
local sformat,pairs,ipairs,doAfter,allScreens=string.format,pairs,ipairs,hs.delayed.doAfter,hs.screen.allScreens

local screensChangedDelayed
local function screensChanged()
  local function sframe(frame)
    return sformat('[%d,%d %dx%d] ',frame.x,frame.y,frame.w,frame.h)
  end
  screensChangedDelayed=nil
  local screens=allScreens()
  local ss='Screen change completed: '
  for _,s in ipairs(screens) do
    ss=ss..sframe(s:fullFrame())
  end
  log.i(ss)
  for fn in pairs(subdone) do
    fn(screens)
  end
end
local function startScreensChanged()
  local screens=allScreens()
  log.i('Screen change detected')
  for fn in pairs(substarted) do
    fn(screens)
  end
  screensChangedDelayed=doAfter(screensChangedDelayed,screenwatcher.delay,screensChanged)
end

local running

local function start()
  if running then return end
  if not swinstance then
    log.i('Instance created')
    swinstance=hs.screen.watcher.new(startScreensChanged)
    swinstance:start()
    pwinstance = hs.caffeinate.watcher.new(function(ev)
      if ev==hs.caffeinate.watcher.screensDidWake then
        startScreensChanged()
      end
    end)
  end
  log.i('Instance started')
  swinstance:start() pwinstance:start() running=true
  --  startScreensChanged()
end

local function stop()
  if not running then return
  elseif next(subdone) or next(substarted) then return end
  hs.delayed.cancel(screensChangedDelayed)
  log.i('Instance stopped')
  swinstance:stop() pwinstance:stop() running=nil
end

function screenwatcher.subscribe(fn,fnDelayed)
  log.d('Adding subscription')
  if type(fn)~='function' or (fnDelayed~=nil and type(fnDelayed)~='function') then error('fn and fnDelayed must be functions',2) end
  start()
  substarted[fn]=true
  if fnDelayed then subdone[fnDelayed]=true end
  fn(allScreens())
  if not screensChangedDelayed and fnDelayed then fnDelayed(allScreens()) end
end

function screenwatcher.unsubscribe(fns)
  if not fns then return
  elseif type(fns)=='function' then fns={fns}
  elseif type(fns)~='table' then error('fns must be a function or table of functions',2) end
  for _,fn in ipairs(fns) do
    if subdone[fn] or substarted[fn] then
      log.d('Removing subscription')
      subdone[fn]=nil substarted[fn]=nil
    end
  end
  stop()
end

return screenwatcher

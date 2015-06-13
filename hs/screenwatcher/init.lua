--- === hs.screenwatcher ===
---
--- A singleton hs.screen.watcher (and companion hs.caffeinate.watcher) for multiple consumption

local log=hs.logger.new('swatcher',5)
local screenwatcher={delay=5}

local swinstance,pwinstance
local substarted,subdone={},{}
local sformat,pairs,ipairs,doAfter,allScreens=string.format,pairs,ipairs,hs.delayed.doAfter,hs.screen.allScreens
local function screensChanged()
  local function sframe(frame)
    return sformat('[%d,%d %dx%d] ',frame.x,frame.y,frame.w,frame.h)
  end
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
local screensChangedDelayed
local function startScreensChanged()
  log.i('Screen change detected')
  for fn in pairs(substarted) do
    fn()
  end
  doAfter(screensChangedDelayed,screenwatcher.delay,screensChanged)
end

local function makeinstance()
  log.i('Screen watcher instantiated')
  swinstance=hs.screen.watcher.new(startScreensChanged)
  swinstance:start()

  pwinstance = hs.caffeinate.watcher.new(function(ev)
    if ev==hs.caffeinate.watcher.screensDidWake then
      startScreensChanged()
    end
    pwinstance:start()
  end)

end

function screenwatcher.subscribe(fnDone,fnStarted)
  log.d('Adding subscription')
  subdone[fnDone]=true
  if fnStarted then substarted[fnStarted]=true end
  if not swinstance then makeinstance() end
  swinstance:start() pwinstance:start()
  fnDone(allScreens())
  return fnDone
end

function screenwatcher.unsubscribe(fn)
  log.d('Removing subscription')
  subdone[fn]=nil substarted[fn]=nil
  if not next(subdone) and not next(substarted) and swinstance then
    log.i('Instance stopped')
    swinstance:stop() pwinstance:stop()
  end
end





return screenwatcher

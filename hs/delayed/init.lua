hs = require'hs._inject_extensions'
local delayed = {}
local log = hs.logger.new('delayed','info')
delayed.setLogLevel=function(lvl)log.setLogLevel(lvl) return delayed end
local pairs,next,type,tinsert,tunpack,max,min = pairs,next,type,table.insert,table.unpack,math.max,math.min
local newtimer=hs.timer.new
local gettime = require'socket'.gettime --FIXME need a native hook

local TOLERANCE=0.05

local pending = {}
local toAdd = {}
--local globalPrecision = 1 -- in seconds
local timer
local timetick,lasttime = 3600,0
local timerfn

timerfn=function()
  for d in pairs(toAdd) do
    pending[d] = true
  end
  toAdd = {}
  local ctime = gettime()
  --  log.vf('timerfn at %.3f',math.fmod(ctime,10))
  local dtime = ctime-lasttime
  lasttime=ctime
  local mindelta = 3600
  local pendingTotal=0
  for d in pairs(pending) do
    --      d.time = d.time - globalPrecision
    d.time = d.time - dtime
    if d.time<=TOLERANCE then
      pending[d] = nil
      log.vf('Running pending callback, %.2fs late',-d.time)
      d.fn(tunpack(d.args))
      return timerfn()
        --        if not pending[d] then break end
    else
      mindelta=min(mindelta,d.time)
      pendingTotal=pendingTotal+1
    end
  end
  if not next(pending) and not next(toAdd) then
    timer:stop()
    log.d('No more pending callbacks; stopping timer')
  else
    for d in pairs(toAdd) do
      mindelta=min(mindelta,d.time)
      pendingTotal=pendingTotal+1
    end
    log.vf('%d callbacks still pending',pendingTotal)
    local dtick = mindelta-timetick
    if dtick<-TOLERANCE or dtick>0.5 then
      log.df('Adjusting timer tick from %.2f to %.2f',timetick,mindelta)
      timer:stop()
      timetick=mindelta
      timer=newtimer(timetick,timerfn)
      lasttime = gettime()
      timer:start()
    end
  end
end

function delayed.doAfter(prev,delay,fn,...)
  local args = {...}
  if type(prev)=='number' then
    tinsert(args,1,fn)
    fn=delay
    delay=prev
  elseif type(prev)=='table' then pending[prev] = nil toAdd[prev] = nil
  end
  if type(fn)~='function' then error('fn must be a function',2) end
  if type(delay)~='number' then error('delay must be a number',2)end

  delay=max(delay,0)
  local d = {time = delay, fn = fn, args = args}
  local ctime=gettime()
  --  log.vf('doAfter at %.3f',math.fmod(ctime,10))
  log.vf('Adding callback with %.2f delay',delay)
  if not next(pending) and not next(toAdd) then
    log.vf('Starting timer, tick %.2f',delay)
    if timer then timer:stop() end
    lasttime=ctime
    timetick=delay
    timer=newtimer(timetick,timerfn)
    timer:start()
  elseif lasttime+timetick>ctime+delay+TOLERANCE then
    log.df('Adjusting timer tick from %.2f to %.2f',timetick,delay)
    timer:stop()
    timetick=delay
    timer=newtimer(timetick,timerfn)
    timer:start()
  end
  toAdd[d] = true
  return d
end

function delayed.cancel(prev)
  if not prev or (not pending[prev] and not toAdd[prev]) then return end
  log.d('Cancelling callback')
  pending[prev] = nil toAdd[prev] = nil
  if not next(pending) and not next(toAdd) then
    if timer then timer:stop() timer=nil end
    log.d('No more pending callbacks; stopping timer')
  end
end

function delayed.stop()
  if timer then timer:stop() end
  pending = {} toAdd = {}
  log.i('Stopped')
end

return delayed

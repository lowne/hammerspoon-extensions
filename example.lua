-- contrived hs.delayed example:
-- say hello 2 seconds after hitting ctrl-alt-cmd-h, discarding multiple presses; unless ctrl-alt-cmd-g is also pressed
local delayedcb
hs.hotkey.bind({'ctrl','alt','cmd'},'h',function()
  delayedcb = hs.delayed.doAfter(delayedcb,2,function()delayedcb=nil hs.alert('Hello!')end)
end)
hs.hotkey.bind({'ctrl','alt','cmd'},'g',function()
  hs.delayed.cancel(delayedcb) -- can be nil
  if not delayedcb then return end
  hs.delayed.doAfter(1,hs.alert.show,'Hi and bye!')
  delayedcb=nil
end)


-- contrived windowfilter/windowwatcher example:
-- whenever I interact with Safari, tell me how many windows there are, disregarding the preferences
local safariwf=hs.windowfilter.new(false) --reject everything...
  :setAppFilter('Safari',nil,
    {'^General$','^Tabs$','^AutoFill$','^Passwords$','^Search$','^Security$','^Privacy$','^Notifications$','^Extensions$','^Advanced$'},
    'AXStandardWindow',nil,true)
-- ...except Safari; but reject the preferences window; only accept standard windows; allow fullscreen, reject invisible windows
local safariww=hs.windowwatcher.new(safariwf)
safariww:subscribe({hs.windowwatcher.windowFocused,hs.windowwatcher.windowShown,hs.windowwatcher.windowHidden},
  function()hs.alert('You have '..#safariww:getWindows()..' Safari windows')end):start()

-- uncomment these to see tons of logger action
--hs.windowfilter.setLogLevel('verbose')
--hs.windowwatcher.setLogLevel('verbose')
--hs.delayed.setLogLevel('verbose')


-- another more general logger/delayed/windowfilter/windowwatcher example
local log=hs.logger.new('example','verbose')
local wf=hs.windowfilter.new(nil,true,true) -- use default windowfilter; allow fullscreen and invisible windows
wf:setAppFilter('Hammerspoon',1,nil,{'AXStandardWindow','AXDialog'}) -- reject all Hammerspoon windows except the console and prefs

local drrect = hs.drawing.rectangle
local sf=hs.screen.allScreens()[1]:frame()
local rect,rt,rl,rb,rr
local frames={} -- cached
local framecolor,bgcolor={red=0,green=0,blue=1,alpha=1},{red=0,green=0,blue=1,alpha=0.1}
local function drawFrame(w) -- draw a frame around a window
  local f=w:frame() frames[w:id()]=f
  rect=drrect(f) rect:setFill(false) rect:setStrokeWidth(10) rect:setStrokeColor(framecolor) rect:show()
  rt=drrect({x=sf.x,y=sf.y,w=f.x+f.w,h=f.y-sf.y})
  rl=drrect({x=sf.x,y=f.y,w=f.x,h=sf.h-f.y+sf.y})
  rb=drrect({x=f.x,y=f.y+f.h,w=sf.w-f.x,h=sf.h-f.y-f.h+sf.y})
  rr=drrect({x=f.x+f.w,y=sf.y,w=sf.w-f.x-f.w,h=f.y+f.h-sf.y})
  for _,r in ipairs{rt,rl,rb,rr} do
    r:setFill(true) r:setFillColor(bgcolor) r:setStroke(false) r:show()
  end
end
local function deleteFrame()
  if rect then rect:delete() rect=nil end
  for _,r in ipairs{rt,rl,rb,rr} do r:delete()  end
end
local FLASH_DURATION=0.3
local function flash(w,r,g,b,a)
  local f=frames[w:id()] or w:frame() frames[w:id()]=f
  local re=drrect(f)
  re:setFill(true) re:setStroke(false) re:setFillColor({red=r,green=g,blue=b,alpha=a}) re:show()
  hs.delayed.doAfter(FLASH_DURATION,re.delete,re)
end

-- draw a frame around the focused window
local ww=hs.windowwatcher.new(wf)
ww:subscribe(ww.windowFocused,function(w)
  drawFrame(w) log.f('%s %d focused: (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
end)
  :subscribe(ww.windowUnfocused,function(w)
    deleteFrame() log.f('%s %d unfocused: (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
  end)

  -- adjust the frame after moving the window (this assumes the moved window has focus, which actually isn't always the case)
  :subscribe(ww.windowMoved,function(w) deleteFrame() drawFrame(w) end)

  -- flash newly visible windows green
  :subscribe({ww.windowCreated,ww.windowShown,--[[ww.windowUnminimized]]},function(w)
    log.f('%s %d shown (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
    flash(w,0,1,0,0.5)
  end)
  -- flash windows going away red
  :subscribe({ww.windowDestroyed,ww.windowHidden,--[[ww.windowMinimized]]},function(w)
    log.f('%s %d hidden (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
    flash(w,1,0,0,0.5)
  end)
  -- visual feedback also when toggling fullscreen
  :subscribe(ww.windowFullscreened,function(w)
    log.f('%s %d fullscreened (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
    flash(w,0,1,1,0.5)
  end)
  :subscribe(ww.windowUnfullscreened,function(w)
    log.f('%s %d unfullscreened (%s) %s',w:subrole(),w:id(),w:application():title(),w:title())
    flash(w,0,1,1,0.5)
  end)
  :start()

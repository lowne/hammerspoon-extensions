--- === expose ===
---
--- Keyboard-driven expose replacement/enhancement

--- Needs native window grabbing to be proper
--
--TODO /// hs.drawing:setClickCallback(fn) -> drawingObject

local expose={} --module

----------------------------------------------------
-- this stuff should go away, in favour of a native windowgrabber+hs.drawing from RAM
local glog=hs.logger.new('grab')
local grab_windows = {} -- module
function grab_windows.setLogLevel(lvl) glog.setLogLevel(lvl)end

local ramdriveName='hsgrab'
local ramdriveDir='/Volumes/'..ramdriveName
-- prepare ramdrive after reboot


local function exec(cmd)
  local f = io.popen(cmd, 'r')
  local res = f:read('*a')
  local ok = f:close()
  return res,ok
end

local function capture(w)
  local id=w.id and w:id()
  if not id then return end
  local res,ok=exec('/usr/sbin/screencapture -xao -t jpg -l'..id..' '..ramdriveDir..'/'..id)
  if not ok then glog.wf('Cannot capture window %d: %s',id,res)
  else glog.v('Captured window '..id) end
end



local spacesDone = {}
--- let me know that we switched to another space, and should refresh the windows
function grab_windows.switchedToSpace(space,cb)
  if spacesDone[space] then glog.v('Switched to space #'..space) return cb and cb() end
  glog.i('Entered space #'..space..', refreshing all windows')
  hs.windowwatcher.switchedToSpace(space,function()
    grab_windows.grabAll()
    spacesDone[space] = true
    return cb and cb()
  end)
end



local ww=hs.windowwatcher.default
  :subscribe({hs.windowwatcher.windowShown,hs.windowwatcher.windowUnfocused},capture)

function grab_windows.grabAll()
  local windows = ww:getWindows()
  for _,w in ipairs(windows) do
    capture(w)
  end
end

function grab_windows.stop()
  --  ww:stop()
  ww:unsubscribe(capture)
end

function grab_windows.start()
  local res,ok=exec('ls '..ramdriveDir)
  if not ok then
    local res,ok =exec("diskutil erasevolume HFS+ '"..ramdriveName.."' `hdiutil attach -nomount ram://204800`")
    if ok then glog.i('Created RAMdrive at '..ramdriveDir)
    else error('Cannot create RAMdrive: '..res) end
  end
  --  ww:start()
  grab_windows.grabAll()
  return grab_windows
end

--local grab=require'grab_windows'.start()
grab_windows.start()
expose.stop=function()grab_windows.stop()end
-- end of stuff that should go away
-------------------------------------------------------------

local drawing=require'hs.drawing'
local log=require'hs.logger'.new('expose')
function expose.setLogLevel(lvl)log.setLogLevel(lvl)end
local newmodal=require'hs.hotkey'.modal.new
local tinsert,tremove,min,max,ceil,abs,fmod,floor=table.insert,table.remove,math.min,math.max,math.ceil,math.abs,math.fmod,math.floor
local next,type,ipairs,pairs,setmetatable,sformat,supper,ssub,tostring=next,type,ipairs,pairs,setmetatable,string.format,string.upper,string.sub,tostring

local rect = {} -- a centered rect class (more handy for our use case)
rect.new = function(r)
  local o = setmetatable({},{__index=rect})
  o.x=r.x+r.w/2
  o.y=r.y+r.h/2
  o.w=r.w o.h=r.h
  return o
end
function rect:scale(factor)
  self.w=self.w*factor self.h=self.h*factor
end
function rect:move(dx,dy)
  self.x=self.x+dx self.y=self.y+dy
end
function rect:tohs()
  return {x=self.x-self.w/2,y=self.y-self.h/2,w=self.w,h=self.h}
end
function rect:intersect(r2)
  local x,y,w,h
  local r1=self
  if r1.x<r2.x then
    x=r2.x-r2.w/2
    w=r1.x+r1.w/2-x
  else
    x=r1.x-r1.w/2
    --    print('xelse',x)
    w=r2.x+r2.w/2-x
  end
  if r1.y<r2.y then
    y=r2.y-r2.h/2
    h=r1.y+r1.h/2-y
  else
    y=r1.y-r1.h/2
    h=r2.y+r2.h/2-y
  end
  return rect.new({x=x,y=y,w=w,h=h})
end
function rect:fit(frame)
  self.x=max(self.x,frame.x+self.w/2)
  self.x=min(self.x,frame.x+frame.w-self.w/2)
  self.y=max(self.y,frame.y+self.h/2)
  self.y=min(self.y,frame.y+frame.h-self.h/2)
end
function rect:toString()
  return sformat('%d,%d %dx%d',self.x,self.y,self.w,self.h)
end



local function checkEmpty(rect,windows,screenFrame)
  if rect.x-rect.w/2<screenFrame.x or rect.x+rect.w/2>screenFrame.w+screenFrame.x
    or rect.y-rect.h/2<screenFrame.y or rect.y+rect.h/2>screenFrame.h+screenFrame.y then return end
  for i,win in ipairs(windows) do
    local i = win.frame:intersect(rect)
    if i.w>0 and i.h>0 then return end
  end
  return true
end

---------------------------
-- these two are only used when animate==true
-- ofc performance is horrible, so they're useless in production
-- a native way to scale/move drawings might fix that
local function showFrame(win,r,g,b,a)
  if win.rect then win.rect:delete() end
  local rect=drawing.rectangle(win.frame:tohs())
  rect:setStroke(true) rect:setStrokeWidth(5)
  rect:setFillColor({red=r,blue=b,green=g,alpha=a}) rect:setFill(true)
  --  rect:show()
  if win.rect then win.rect:delete() end
  --        hs.timer.usleep(200)
  win.rect=rect
end
local function showThumb(win)
  if win.thumb then win.thumb:delete() end
  local thumb=drawing.image(win.frame:tohs(),ramdriveDir..'/'..win.id)
  thumb:show()
  win.thumb=thumb
end
-------------------------------

local function fitWindows(windows,MAX_ITERATIONS,alt_algo,animate)
  local screenFrame = windows.frame
  local avgRatio = min(1,screenFrame.w*screenFrame.h/windows.area*2)
  log.df('shrink %d windows to %d%%',#windows,avgRatio*100)
  for i,win in ipairs(windows) do
    win.frame:scale(avgRatio)
  end
  local didwork = true
  local iterations = 0
  local screenArea=screenFrame.w*screenFrame.h
  local screenCenter=rect.new(screenFrame)

  while didwork and iterations<MAX_ITERATIONS do
    didwork=false
    iterations=iterations+1
    local thisAnimate=animate and math.floor(math.sqrt(iterations))
    local totalOverlaps = 0
    local totalRatio=0
    for i,win in ipairs(windows) do
      local winRatio = win.frame.w*win.frame.h/win.area
      totalRatio=totalRatio+winRatio
      -- log.vf('processing %s - %s',win.appname,win.frame:toString())
      local overlapAreaTotal = 0
      local overlaps={}
      for j,win2 in ipairs(windows) do
        if j~=i then
          --log.vf('vs %s %s',win2.appname,win2.frame:toString())
          local intersection = win.frame:intersect(win2.frame)
          local area = intersection.w*intersection.h
          --log.vf('intersection %s [%d]',intersection:toString(),area)
          if intersection.w>1 and intersection.h>1 then
            --log.vf('vs %s intersection %s [%d]',win2.appname,intersection:toString(),area)
            overlapAreaTotal=overlapAreaTotal+area
            overlaps[#overlaps+1] = intersection
            if area*0.9>win.frame.w*win.frame.h then
              overlaps[#overlaps].x=(win.frame.x+win2.frame.x)/2
              overlaps[#overlaps].y=(win.frame.y+win2.frame.y)/2
            end
          end
        end
      end

      totalOverlaps=totalOverlaps+#overlaps
      -- find the overlap regions center
      if #overlaps>0 then
        didwork=true
        local ax,ay=0,0
        for _,ov in ipairs(overlaps) do
          local weight = ov.w*ov.h/overlapAreaTotal
          ax=ax+ weight*(ov.x)
          ay=ay+ weight*(ov.y)
        end
        ax=(win.frame.x-ax)*overlapAreaTotal/screenArea*3 ay=(win.frame.y-ay)*overlapAreaTotal/screenArea*3
        win.frame:move(ax,ay)
        if winRatio/avgRatio>0.8 then win.frame:scale(alt_algo and 0.95 or 0.98) end
        win.frame:fit(screenFrame)
        if animate then showFrame(win,1,0,0,0.3)end
      elseif alt_algo then
        -- scale back up
        win.frame:scale(1.05)
        win.frame:fit(screenFrame)
      end
      if totalOverlaps>0 and avgRatio<0.9 and not alt_algo then
        local DISPLACE=5
        if not alt_algo then
          for dx = -DISPLACE,DISPLACE,DISPLACE*2 do
            if win.frame.x>screenCenter.x then dx=-dx end
            local r = {x=win.frame.x+win.frame.w/(dx<0 and -2 or 2)+dx,y=win.frame.y,w=abs(dx)*2-1,h=win.frame.h}
            if checkEmpty(r,windows,screenFrame) then
              win.frame:move(dx,0)
              if winRatio/avgRatio<1.33 and winRatio<1 then win.frame:scale(1.01)end
              didwork=true
              break
            end
          end
          for dy = -DISPLACE,DISPLACE,DISPLACE*2 do
            if win.frame.y>screenCenter.y then dy=-dy end
            local r = {y=win.frame.y+win.frame.h/(dy<0 and -2 or 2)+dy,x=win.frame.x,h=abs(dy)*2-1,w=win.frame.w}
            if checkEmpty(r,windows,screenFrame) then
              win.frame:move(0,dy)
              if winRatio/avgRatio<1.33 and winRatio<1 then win.frame:scale(1.01)end
              didwork=true
              break
            end
          end
        end
      end
      if thisAnimate and thisAnimate>animate then
        showThumb(win)
      end
    end
    avgRatio=totalRatio/#windows
    local totalArea=0
    for i,win in ipairs(windows) do
      totalArea=totalArea+win.frame.w*win.frame.h
    end
    local halting=iterations==MAX_ITERATIONS
    if not didwork or halting then
      log.df('%s (%d iterations): coverage %.2f%% (%d overlaps)',halting and 'halted' or 'optimal',iterations,totalArea/(screenFrame.w*screenFrame.h)*100,totalOverlaps)
    end
    animate=animate and thisAnimate
  end
  --  log.df('done - %d iterations %s',iterations,didwork and '(halted)' or '')
end


local MAXCHARS=2
local function getHints(screens)
  local function tlen(t)
    if not t then return 0 end
    local l=0
    for _ in pairs(t) do
      l=l+1
    end
    return l
  end
  local function hasSubHints(t)
    for k,v in pairs(t) do
      if type(k)=='string' and #k==1 then return true end
    end
  end
  local hints={apps={}}
  local RESERVED=1
  for _,screen in pairs(screens) do
    for _,w in ipairs(screen) do
      local appname=w.appname or ''
      while #appname<MAXCHARS do
        --TODO also fix short names (for whatever reason)
        appname=appname..tostring(RESERVED) RESERVED=RESERVED+1
      end
      hints[#hints+1]=w
      hints.apps[appname]=(hints.apps[appname] or 0)+1
      w.hint=''
    end
  end
  local function normalize(t,n) --change in place
    while #t>0 and tlen(t.apps)>0 do
      if n>MAXCHARS or (tlen(t.apps)==1 and n>1 and not hasSubHints(t))  then
        -- last app remaining for this hint; give it digits
        t.apps={}
        if #t>1 or t.total then
          --fix so that accumulation is possible
          t.total=t.total or 0
          local i=t.total
          for ir,w in ipairs(t) do
            t.total=t.total+1
            t[ir]=nil
            local fd=floor(t.total/10)
            local c=tostring(fd>0 and fd or fmod(t.total,10))
            t[c]=t[c] or {total=0}
            t[c].total=t[c].total+1
            tinsert(t[c],w)
            w.hint=w.hint..c
          end
        end
      else
        -- find the app with least #windows and add a hint to it
        local minfound,minapp=9999
        for appname,nwindows in pairs(t.apps) do
          if nwindows<minfound then minfound=nwindows minapp=appname end
        end
        t.apps[minapp]=nil
        local c=supper(ssub(minapp,n,n))
        --TODO what if not long enough
        t[c]=t[c] or {apps={}}
        t[c].apps[minapp]=minfound
        local i=1
        while i<=#t do
          if t[i].appname==minapp then
            local w=tremove(t,i)
            tinsert(t[c],w)
            w.hint=w.hint..c
          else i=i+1 end
        end
      end
  end
  for c,subt in pairs(t) do
    if type(c)=='string' and #c==1 then
      normalize(subt,n+1)
    end
  end
  end

  normalize(hints,1)
  return hints
end



local COLOR_BLACK={red=0,green=0,blue=0,alpha=1}
local COLOR_GREY={red=0.2,green=0.2,blue=0.2,alpha=0.95}
local COLOR_WHITE={red=1,green=1,blue=1,alpha=1}
local COLOR_DARKOVERLAY={red=0,green=0,blue=0,alpha=0.8}
local COLOR_HIGHLIGHT={red=0.8,green=0.5,blue=0,alpha=0.1}
local COLOR_HIGHLIGHT_STROKE={red=0.8,green=0.5,blue=0,alpha=0.8}
local COLOR_RED={red=1,green=0,blue=0,alpha=0.8}


local function updateHighlights(hints,subtree,show)
  for c,t in pairs(hints) do
    if t==subtree then
      updateHighlights(t,nil,true)
    elseif type(c)=='string' and #c==1 then
      if t[1] then local h=t[1].highlight h:setFillColor(show and COLOR_HIGHLIGHT or COLOR_DARKOVERLAY) h:setStrokeColor(show and COLOR_HIGHLIGHT_STROKE or COLOR_BLACK)
      else updateHighlights(t,subtree,show) end
    end
  end
end


local screens={}
local modals={}
local closemode,activeInstance,tap
local function exitAll()
  log.d('exiting')
  while modals[#modals] do log.vf('exit modal %d',#modals) tremove(modals).modal:exit() end
  --cleanup
  for _,s in pairs(screens) do
    for _,w in ipairs(s) do
      if w.thumb then w.thumb:delete() end
      if w.rect then w.rect:delete() end
      if w.ratio then w.ratio:delete() end
      w.highlight:delete()
      w.hinttext:delete() w.hintrect:delete()
    end
    s.bg:delete()
  end
  tap:stop()
  activeInstance=nil
end

local function setCloseMode(mode)
  closemode=mode
  for _,screen in pairs(screens) do
    screen.bg:setFillColor(closemode and COLOR_RED or COLOR_GREY)
  end
end

local enter

local function exit()
  log.vf('exit modal %d',#modals)
  tremove(modals).modal:exit()
  if #modals==0 then return exitAll() end
  return enter()
end

enter=function(hints)
  if not hints then updateHighlights(modals[#modals].hints,nil,true) modals[#modals].modal:enter()
  elseif hints[1] then
    --got a hint
    if closemode then
      local h=hints[1]
      local app,appname=h.window:application(),h.appname
      log.f('Closing window (%s)',appname)
      h.window:close()
      h.hintrect:delete() h.hinttext:delete() h.highlight:delete() h.thumb:delete()
      hints[1]=nil
      -- close app
      if app then
        if #app:allWindows()==0 then
          log.f('Quitting application %s',appname)
          app:kill()
        end
      end
      return enter()
    else
      log.f('Focusing window (%s)',hints[1].appname)
      hints[1].window:focus()
      return exitAll()
    end
  else
    if modals[#modals] then log.vf('exit modal %d',#modals) modals[#modals].modal:exit() end
    local modal=newmodal()
    modals[#modals+1]={modal=modal,hints=hints}
    modal:bind({},'escape',exitAll)
    --    modal:bind({},'space',function()setCloseMode(not closemode)end)
    modal:bind({},'delete',exit)
    for c,t in pairs(hints) do
      if type(c)=='string' and #c==1 then
        modal:bind({},c,function()updateHighlights(hints,t) enter(t) end)
        modal:bind({'shift'},c,function()updateHighlights(hints,t) enter(t) end)
      end
    end
    log.vf('enter modal %d',#modals)
    modal:enter()
  end
end
--[[
local function toggleClose(b)
  for _,screen in pairs(screens) do
    screen.bg:setFillColor(b and COLOR_RED or COLOR_GREY)
  end
  closemode=b
end
--]]

local HINTWIDTH,HINTHEIGTH= 30,45

function expose.switchedToSpace(space)
  local tempinstance=activeInstance
  if activeInstance then exitAll() end
  grab_windows.switchedToSpace(space,function()
    if not tempinstance then return end
    if tempinstance.ww then
      hs.windowwatcher.switchedToSpace(space,function()tempinstance:expose()end)
    else tempinstance:expose()
    end
  end)
end

--- hs.expose:expose()
--- Method
--- Shows an expose-like screen with keyboard hints for switching to or closing windows.
---
--- Notes:
---  * If `shift` is being held when a hint is completed (the background will be red), the selected
---    window will be closed. If it's the last window of an application, the application will be closed.
function expose:expose(alt_algo,animate)
  if activeInstance then exitAll() end
  log.d('activated')
  activeInstance=self
  screens={}
  local wins = self.ww and self.ww:getWindows() or self.wf:filterWindows(hs.window.orderedWindows())
  for i=#wins,1,-1 do
    local w = wins[i]
    local id=w:screen():id()
    if not screens[id] then
      local frame=w:screen():frame()
      local bg=drawing.rectangle(frame)
      bg:setFill(true) bg:setFillColor(COLOR_GREY)
      bg:show()
      screens[id]={frame=frame,bg=bg,area=0}
    end
    local frame=w:frame()
    screens[id].area=screens[id].area+frame.w*frame.h
    screens[id][#screens[id]+1] = {appname=w:application():title(),window=w,
      frame=rect.new(frame),originalFrame=frame,area=frame.w*frame.h,id=w:id()}
  end
  local hints=getHints(screens)
  for _,s in pairs(screens) do
    fitWindows(s,self.iterations,alt_algo,animate and 0 or nil)
    for _,w in ipairs(s) do
      if animate and w.thumb then w.thumb:delete() end
      w.thumb = drawing.image(w.frame:tohs(),ramdriveDir..'/'..w.window:id())
      w.thumb:show()
      --      local ratio=drawing.text(w.frame:tohs(),sformat('%d%%',w.frame.w*w.frame.h*100/w.area))
      --      ratio:setTextColor{red=1,green=0,blue=0,alpha=1}
      --      ratio:show()
      --      w.ratio=ratio
      w.highlight=drawing.rectangle(w.frame:tohs())
      w.highlight:setFill(true) w.highlight:setFillColor(COLOR_HIGHLIGHT)
      w.highlight:setStrokeWidth(10) w.highlight:setStrokeColor(COLOR_HIGHLIGHT_STROKE)
      w.highlight:show()
      local hwidth=#w.hint*HINTWIDTH
      local hr={x=w.frame.x-hwidth/2,y=w.frame.y-HINTHEIGTH/2,w=hwidth,h=HINTHEIGTH}
      w.hintrect=drawing.rectangle(hr)
      w.hintrect:setFill(true) w.hintrect:setFillColor(COLOR_DARKOVERLAY) w.hintrect:setStroke(false)
      w.hintrect:setRoundedRectRadii(10,10)
      w.hinttext=drawing.text(hr,w.hint)
      w.hinttext:setTextColor(COLOR_WHITE) w.hinttext:setTextSize(40)
      w.hintrect:show() w.hinttext:show()
    end
  end
  enter(hints)
  --[-[
  tap=hs.eventtap.new({hs.eventtap.event.types.flagschanged},function(e)
    local function hasOnlyShift(t)
      local n=next(t)
      if n~='shift' then return end
      if not next(t,n) then return true end
    end
    setCloseMode(hasOnlyShift(e:getFlags()))
  end)
  tap:start()
  --]]
end

--- hs.expose.new(windowfilter) -> hs.expose
--- Function
--- Creates a new hs.expose instance. It uses a windowfilter or windowwatcher object to determine which windows to show
---
--- Parameters:
---  * windowfilter - it can be:
---      * `nil`, the default windowfilter will be used
---      * an `hs.windowfilter` or `hs.windowwatcher` object
---
--- Returns:
---  * the new instance
---
--- Notes:
---   * using a windowwatcher will allow the expose instance to be populated with windows from all spaces
---     (unlike the OSX expose)
function expose.new(windowfilter,iterations)
  iterations = iterations or 200
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
  return setmetatable({wf=windowfilter,ww=windowwatcher,iterations=iterations},{__index=expose})
end

return expose
  
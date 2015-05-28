hs=require'hs._inject_extensions'
local log=hs.logger.new('wfilter','info')
local ipairs,type,smatch = ipairs,type,string.match

local windowfilter={}
windowfilter.setLogLevel=function(lvl)log.setLogLevel(lvl) return windowfilter end

local SKIP_APPS_NO_PID = {
  'universalaccessd','sharingd','Safari Networking','iTunes Helper','Safari Web Content',
  'App Store Web Content',
  'Google Chrome Helper','Spotify Helper','Karabiner_AXNotifier',
  'Little Snitch Agent','Little Snitch Network Monitor',
}

local SKIP_APPS_NO_PID_BUNDLE = {
  'com.apple.qtkitserver', -- QTKitServer-(%d) Safari Web Content
}

local SKIP_APPS_NO_WINDOWS = {
  'loginwindow', 'com.apple.internetaccounts', 'CoreServicesUIAgent', 'AirPlayUIAgent',
  'SystemUIServer', 'Dock', 'com.apple.dock.extra', 'storeuid',
  'Folder Actions Dispatcher', 'Keychain Circle Notification', 'Wi-Fi',
  'Image Capture Extensions', 'iCloud Photos', 'System Events',
  'Speech Synthesis Server', 'Dropbox Finder Integration', 'LaterAgent',
  'Karabiner_AXNotifier', 'Photos Agent', 'EscrowSecurityAlert',
  'Google Chrome Helper', 'com.apple.MailServiceAgent', 'Safari Web Content',
  'Safari Networking', 'nbagent',
}

local SKIP_APPS_TRANSIENT_WINDOWS = {
  'Spotlight', 'Notification Center',
  -- preferences etc
  'PopClip','Isolator', 'CheatSheet', 'CornerClickBG', 'Alfred 2', 'Moom', 'CursorSense Manager',
  -- menulets
  'Music Manager', 'Google Drive', 'Dropbox', '1Password mini', 'Colors for Hue', 'MacID',
  'CrashPlan menu bar', 'Flux', 'Jettison', 'Bartender', 'SystemPal', 'BetterSnapTool', 'Grandview', 'Radium',
}

local APPS_ALLOW_NONSTANDARD_WINDOWS = {
  'iTerm2', 'Lua Development Tools Product', 'SwitchResX Daemon',
}

local APPS_SKIP_NO_TITLE = {
  'Lua Development Tools Product'
}

local ALLOWED_NONSTANDARD_WINDOW_ROLES = {'AXStandardWindow','AXDialog','AXFloatingWindow','AXSystemDialog'}
local ALLOWED_WINDOW_ROLES = {'AXStandardWindow'}

--local ALLOWED_WINDOW_ROLES_INVISIBLE = {'AXStandardWindow','AXDialog'}

--[[
local function allowWindow(appname,windowrole,windowtitle)
  if type(appname)=='userdata' then
    -- passed a window object
    if not appname.id or not appname.frame then error('must pass a hs.window object',2) end
    windowtitle = appname:title()
    windowrole = appname:subrole()
    appname = appname:application():title()
  else
    if type(appname)~='string' then error('appname must be a string',2) end
    if type(windowrole)~='string' then error('windowrole must be a string',2) end
    if type(windowtitle)~='string' then error('windowtitle must be a string',2) end
  end
  if apps_skipNoTitle[appname] and #windowtitle<1 then
    log.vf('Skip window with no title for %s [%s]',windowrole,appname)
    return
  elseif apps_allowNonstandardWindows[appname] then
    if not ALLOWED_NONSTANDARD_WINDOW_ROLES[windowrole] then
      log.vf('Skip non allowed role for %s [%s]',windowrole,appname)
      return
    end
  elseif windowrole~='AXStandardWindow' then
    log.vf('Skip non allowed role for %s [%s]',windowrole,appname)
    return
  end
  log.vf('Allowed %s [%s]: %s',windowrole,appname,windowtitle)
  return true
end
local function filterWindows(windows)
  local res = {}
  for _,w in ipairs(windows) do
    if allowWindow(w) then res[#res+1]=w end
  end
  return res
end
local function allowApp(appname)
  if not apps_skip[appname] then return true end
end


--]]
local wf={}

function wf:isWindowAllowed(window,appname)--appname,windowrole,windowtitle)
  local function matchTitle(titles,t)
    for _,title in ipairs(titles) do
      if smatch(t,title) then return true end
    end
  end
  local function allowWindow(app,role,title,fullscreen,visible)
    if app.titles then
      if type(app.titles)=='number' then if #title<=app.titles then return end
      elseif not matchTitle(app.titles,title) then return end
    end
    if app.rtitles and matchTitle(app.rtitles,title) then return end
    if app.roles and not app.roles[role] then return end
    --    if visible and app.roles and not app.roles[role] then return end
    --    if not visible and app.invroles and not app.invroles[role] then return end
    if app.fullscreen~=nil and app.fullscreen~=fullscreen then return end
    if app.visible~=nil and app.visible~=visible then return end
    return true
  end
  local role = window.subrole and window:subrole() or '?'
  local title = window:title()
  local fullscreen = window:isFullScreen()
  local visible = window:isVisible()

  local app=self.apps[true]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then return false end
  appname = appname or window:application():title()
  app=self.apps[appname]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then return false end
  app=self.apps[false]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then
    --    print(role,window:id(),visible,app.invroles[''])
    return false
  end
  return true
end

function wf:isAppAllowed(appname)
  return self.apps[appname]~=false
end
function wf:filterWindows(windows)
  if not windows then windows=hs.window.allWindows() end
  local res={}
  for _,w in ipairs(windows) do
    if self:isWindowAllowed(w) then res[#res+1]=w end
  end
  return res
end

--local function setFilter(self,appname,allowTitles,rejectTitles,allowRoles,fullscreen,visible)
--end
function wf:rejectApp(appname)
  self:setAppFilter(appname,false)
end
function wf:setDefaultFilter(...)
  self:setAppFilter(false,...)
end
function wf:setOverrideFilter(...)
  self:setAppFilter(true,...)
end
function wf:setAppFilter(appname,allowTitles,rejectTitles,allowRoles,fullscreen,visible)
  if type(appname)~='string' and type(appname)~='boolean' then error('appname must be a string or boolean',2) end
  if allowTitles==false then self.apps[appname]=false return end

  local app = self.apps[appname] or {}
  if allowTitles~=nil then
    local titles=allowTitles
    if type(allowTitles)=='string' then titles={allowTitles}
    elseif type(allowTitles)~='number' and type(allowTitles)~='table' then error('allowTitles must be a number, string or table',2) end
    app.titles=titles
  end
  if rejectTitles~=nil then
    local rtitles=rejectTitles
    if type(rejectTitles)=='string' then rtitles={rejectTitles}
    elseif type(rejectTitles)~='table' then error('rejectTitles must be a string or table',2) end
    app.rtitles=rtitles
  end
  if allowRoles~=nil then
    local roles={}
    if type(allowRoles)=='string' then roles={[allowRoles]=true}
    elseif type(allowRoles)=='table' then
      for _,r in ipairs(allowRoles) do roles[r]=true end
    else error('allowRoles must be a string or table',2) end
    app.roles=roles
  end
  if fullscreen~=nil then app.fullscreen=fullscreen end
  if visible~=nil then app.visible=visible end
  self.apps[appname]=app
end

function windowfilter.new(fn,includeFullscreen,includeInvisible)
  if type(fn)=='function' then
    return {
      isWindowAllowed = fn,
      isAppAllowed = function()return true end,
      filterWindows = function(windows)
        local res={}
        for _,w in ipairs(windows) do
          if fn(w) then res[#res+1]=w end
        end
        return res
      end,
    }
  end
  local o = setmetatable({apps={}},{__index=wf})
  if fn==true then
    for _,list in ipairs{SKIP_APPS_NO_PID,SKIP_APPS_NO_WINDOWS,SKIP_APPS_TRANSIENT_WINDOWS} do
      for _,appname in ipairs(list) do
        o:rejectApp(appname)
      end
    end
    for _,appname in ipairs(APPS_ALLOW_NONSTANDARD_WINDOWS) do
      o:setAppFilter(appname,nil,nil,ALLOWED_NONSTANDARD_WINDOW_ROLES)
    end
    for _,appname in ipairs(APPS_SKIP_NO_TITLE) do
      o:setAppFilter(appname,1)
    end
    local fs,vis=false,true
    if includeFullscreen then fs=nil end
    if includeInvisible then vis=nil end
    o:setOverrideFilter(nil,nil,nil,fs,vis)
    o:setDefaultFilter(nil,nil,ALLOWED_WINDOW_ROLES)--,ALLOWED_WINDOW_ROLES_INVISIBLE)
    return o
  elseif fn==nil then return o
  else error('fn must be nil, true or a function',2) end
end
windowfilter.default = windowfilter.new(true)
--local appstoskip={Hammerspoon=true}
local appstoskip={}
for _,list in ipairs{SKIP_APPS_NO_PID,SKIP_APPS_NO_WINDOWS} do
  for _,appname in ipairs(list) do
    appstoskip[appname]=true
    --    skipnonguiapps:rejectApp(appname)
  end
end
local ssub=string.sub
windowfilter.isGuiApp = function(appname)
  if not appname then return true
  elseif appstoskip[appname] then return false
  elseif ssub(appname,1,12)=='QTKitServer-' then return false
  else return true end
end


return windowfilter


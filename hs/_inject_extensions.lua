--[[
--patch hs.screen
local fnutils=hs.fnutils
local geometry=hs.geometry
--local _=hs.screen -- force loading, allow override

local function first_screen_in_direction(screen, numrotations)
  if #screen.allScreens() == 1 then
    return nil
  end

  -- assume looking to east

  -- use the score distance/cos(A/2), where A is the angle by which it
  -- differs from the straight line in the direction you're looking
  -- for. (may have to manually prevent division by zero.)

  -- thanks mark!

  local otherscreens = fnutils.filter(screen.allScreens(), function(s) return s ~= screen end)
  local startingpoint = geometry.rectMidPoint(screen:fullFrame())
  local closestscreens = {}

  for _, s in pairs(otherscreens) do
    local otherpoint = geometry.rectMidPoint(s:fullFrame())
    otherpoint = geometry.rotateCCW(otherpoint, startingpoint, numrotations)

    local delta = {
      x = otherpoint.x - startingpoint.x,
      y = otherpoint.y - startingpoint.y,
    }

    if delta.x > 0 then
      local angle = math.atan(delta.y, delta.x)
      local distance = geometry.hypot(delta)
      local anglediff = -angle
      local score = distance / math.cos(anglediff / 2)
      table.insert(closestscreens, {s = s, score = score})
    end
  end

  -- actual patch --
  -- exclude screens without any horizontal/vertical overlap
  local myf=screen:fullFrame()
  for i=#closestscreens,1,-1 do
    local of=closestscreens[i].s:fullFrame()
    if numrotations==1 or numrotations==3 then
      if of.x+of.w-1<myf.x or myf.x+myf.w-1<of.x then table.remove(closestscreens,i) end
    else
      if of.y+of.h-1<myf.y or myf.y+myf.h-1<of.y then table.remove(closestscreens,i) end
    end
  end
  -- end actual patch --
  table.sort(closestscreens, function(a, b) return a.score < b.score end)

  if #closestscreens > 0 then
    return closestscreens[1].s
  else
    return nil
  end
end
hs.screen.toEast=function(self)  return first_screen_in_direction(self, 0) end
hs.screen.toWest=function(self)  return first_screen_in_direction(self, 2) end
hs.screen.toNorth=function(self) return first_screen_in_direction(self, 1) end
hs.screen.toSouth=function(self) return first_screen_in_direction(self, 3) end

-- end patch
--]]
hs._extensions.grid=nil -- inject the new hs.grid
local done,_hs={},hs
return setmetatable({},{__index=function(t,k)
  local t=_hs[k]
  if t then return t end
  if not done[k] then print('-- Loading extension: '..k)end done[k]=true
  t=require('hs.'..k)
  return t
end})

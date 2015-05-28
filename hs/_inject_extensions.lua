local done,_hs={},hs
return setmetatable({},{__index=function(t,k)
  local t=_hs[k]
  if t then return t end
  t=require('hs.'..k)
  if not done[k] then print('-- Loading extension: '..k)end done[k]=true
  return t
end})

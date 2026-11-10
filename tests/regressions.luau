local waku = require(nodes.init)
local Pose = require(nodes.Pose)
local State = require(nodes.CasterState)
local count=0
local function test(name,fn)
 waku.clear()
 fn()
 waku.clear()
 count+=1;print('PASS '..name)
end
local function restored(c,r,b,d,anchor)
 assert(c.Parent==Workspace,'parent not restored')
 assert(c.Archivable==false,'Archivable not restored')
 assert(r.Anchored==(anchor or false),'anchor not restored')
 assert(b.Transparency==0.35 and d.Transparency==0.2,'transparency not restored')
end
local function start(name,c)
 local h=waku.play(name,CFrame.new(),{caster=c})
 assert(h, 'build failed for '..name..': '..tostring(waku.Errors[#waku.Errors]))
 return h
end
for _,player in {true,false} do
 for _,pair in {{'PrismCleave','EarthRise'},{'EarthRise','StormLance'},{'PrismCleave','PrismCleave'},{'EarthRise','EarthRise'}} do
  test('same-caster guard '..pair[1]..' -> '..pair[2]..' player='..tostring(player),function()
   local c,r,b,d=makeCaster(player)
   local first=start(pair[1],c)
   local errors=#waku.Errors
   assert(waku.play(pair[2],CFrame.new(),{caster=c})==nil)
   assert(#waku.Errors==errors+1 and string.find(waku.Errors[#waku.Errors],'caster already has an active pose',1,true))
   assert(first.alive())
   if player then assert(b.Transparency==1 and r.Anchored) else assert(c.Parent==nil) end
   first.stop();first.stop();restored(c,r,b,d)
   local nextHandle=start(pair[2],c);nextHandle.stop();restored(c,r,b,d)
   tick(0.01);assert(waku.activeCount()==0 and not waku.connected())
  end)
 end
end
for _,name in waku.Order do
 test('natural lifecycle '..name,function()
  local c,r,b,d=makeCaster(true,true)
  local h=start(name,c)
  tick(0.2);assert(h.alive(), tostring(waku.Errors[#waku.Errors]))
  tick(h.life+0.1);assert(not h.alive());restored(c,r,b,d,true)
  assert(h.root.Parent==nil and waku.activeCount()==0 and not waku.connected())
 end)
end
test('different casters can overlap',function()
 local a,ar,ab,ad=makeCaster(true);local b,br,bb,bd=makeCaster(true)
 local x=start('PrismCleave',a);local y=start('EarthRise',b)
 assert(x.alive() and y.alive());waku.clear();restored(a,ar,ab,ad);restored(b,br,bb,bd)
end)
for _,kind in {'first-frame','later-frame','build'} do
 test('cleanup on '..kind..' failure',function()
  local c,r,b,d=makeCaster(true)
  local cleaned=0;local root
  waku.Effects.Failure={life=1,required={},build=function(ctx)
   root=ctx.root
   Pose.rig(ctx,c)
   table.insert(ctx.cleanups,function() cleaned+=1 end)
   if kind=='build' then error('intentional build failure') end
   return function(t)
    if kind=='first-frame' or t>0 then error('intentional update failure') end
   end
  end}
  local h=waku.play('Failure',CFrame.new())
  if kind=='later-frame' then assert(h);tick(0.1);assert(not h.alive()) else assert(h==nil) end
  assert(cleaned==1 and root.Parent==nil)
  assert(waku.activeCount()==0 and not waku.connected())
  restored(c,r,b,d);start('EarthRise',c).stop();restored(c,r,b,d)
 end)
end
test('clone failure restores archivable and releases guard',function()
 local c,r,b,d=makeCaster(true);c.FailClone=true
 assert(waku.play('PrismCleave',CFrame.new(),{caster=c})==nil)
 restored(c,r,b,d);c.FailClone=false;start('EarthRise',c).stop();restored(c,r,b,d)
end)
test('failure after hiding but before Pose finishes restores external state',function()
 local c,r,b,d=makeCaster(true)
 local original=c.Clone
 c.Clone=function(self)
  local clone=original(self)
  clone.GetDescendants=function() error('injected post-hide failure') end
  return clone
 end
 assert(waku.play('PrismCleave',CFrame.new(),{caster=c})==nil)
 restored(c,r,b,d);c.Clone=nil;start('EarthRise',c).stop();restored(c,r,b,d)
end)
test('noncycling palette retains spatial colour offsets',function()
 local Kit=require(nodes.Kit)
 local ctx={opts={rainbow=false,hue=0.55}}
 assert(Kit.hue(ctx,0,0)==Kit.hue(ctx,1,0))
 local a=Kit.col(Kit.hue(ctx,0,0)+1/12)
 local b=Kit.col(Kit.hue(ctx,0,0)+7/12)
 assert(math.abs(a.H-b.H)>0.49)
end)
test('tutorial real module creates grows cleans and cancels',function()
 waku.Effects.PulseOrb=require(nodes.PulseOrb)
 local h=assert(waku.play('PulseOrb',CFrame.new()))
 local p=h.root:FindFirstChild('Pulse');assert(p and p.Transparency==0 and p.Size.X==1)
 tick(0.4);assert(p.Size.X>1 and p.Transparency>0)
 tick(1);assert(not h.alive() and h.root.Parent==nil)
 local h2=assert(waku.play('PulseOrb',CFrame.new()));h2.stop();assert(not h2.alive())
end)
print('DONE '..count..' mock logic regressions; actual modules, not Studio/asset/render proof')

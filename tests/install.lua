local install=(assert(loadfile(ROOT..'/src/install.lua')))()
local polls,restores,starts,now,closed=0,0,0,0,0
local real_update=function(a)return nil,a,'kept' end
update=real_update;shutdown=function()closed=closed+1;return 'closed'end
-- Keep tests from replacing the real game log.
local old_io_open=io.open
io.open=function(path,mode)if path:match('EAT700Cooldown.log$')then return nil end;return old_io_open(path,mode)end
local profile={version='test',dll_sha256='dll',exe_sha256='exe',signatures={['0x10']='aa'}}
local function api()
    starts=starts+1
    return {pid=function()return 7 end,time=function()return now end,module=function(name)return name and 100 or 200 end,
        module_hash=function(module)return module==100 and 'dll' or 'exe'end,read=function()return string.char(0xaa)end}
end
local function controller(a,p,b,s)
    return {poll=function()polls=polls+1;s.status='active'end,restore=function()restores=restores+1;return true end}
end
local state=install(api,controller,profile)
local wrapped=update
local a,b,c=update(42)
assert(a==nil and b==42 and c=='kept' and polls==1 and state.status=='active')
assert(install(api,controller,profile)==state and update==wrapped and starts==1)
update(3);assert(polls==1);now=2;update(3);assert(polls==2)
assert(shutdown()=='closed' and closed==1 and restores==1 and state.status=='shutdown_restored')

EAT700Cooldown=nil;update=real_update
profile.dll_sha256='different'
local failed=install(api,controller,profile)
assert(failed.stopped and failed.error:match('Unsupported game build') and update==real_update)
profile.dll_sha256='dll';EAT700Cooldown=nil
update=function()error('original-error')end
local failed_update=install(api,controller,profile)
local success,reason=pcall(update)
assert(not success and tostring(reason):match('original%-error') and failed_update.stopped and restores==2)
io.open=old_io_open
return 'PASS initialization, duplicate entry, wrapper return values, shutdown chain, wrong build, original error propagation'

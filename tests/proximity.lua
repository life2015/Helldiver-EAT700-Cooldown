local factory=assert(loadfile(ROOT..'/src/proximity.lua'))()
local controller=assert(loadfile(ROOT..'/src/controller.lua'))()
local real=assert(loadfile(ROOT..'/src/windows.lua'))()()
local ffi=require('ffi')
local function bytes(s)return(s:gsub('..',function(h)return string.char(tonumber(h,16))end))end
local function pointer(n)return ffi.string(ffi.new('uint64_t[1]',n),8)end
local function replace(s,off,v)return s:sub(1,off)..v..s:sub(off+#v+1)end
local function fixture()
    local config={};for k,v in pairs(PROFILE.proximity)do config[k]=v end
    local base,record=0x100000,0x60000000
    local raw=bytes(config.identity_hex)..string.rep('\165',config.record_size-24)
    for _,e in ipairs(config.edits)do raw=replace(raw,e.offset,bytes(e.before))end
    config.original_sha256=real.sha(raw)
    local patched=raw
    for _,e in ipairs(config.edits)do patched=replace(patched,e.offset,bytes(e.after))end
    config.patched_sha256=real.sha(patched)
    local memory={[record]=raw,[base+config.slot_rva]=pointer(record)}
    local api={writes=0,sha=real.sha}
    function api.read(p,n)
        for start,data in pairs(memory)do if p>=start and p+n<=start+#data then return data:sub(p-start+1,p-start+n)end end
    end
    function api.ptr(p)return memory[p]==pointer(record) and record or nil end
    function api.writable(p,n)return p>=record and p+n<=record+#raw end
    function api.write(p,before,after)
        assert(#before==4 and #after==4 and api.read(p,4)==before)
        local allowed=false;for _,e in ipairs(config.edits)do if p==record+e.offset then allowed=true end end
        assert(allowed,'Unexpected write outside fuse fields')
        memory[record]=replace(memory[record],p-record,after);api.writes=api.writes+1
        if api.writes==api.fail then error('Injected failure after mutation')end
    end
    return {api=api,memory=memory,record=record,base=base,config=config,raw=raw,patched=patched,lease=factory(api,config,base)}
end
local t=fixture();assert(t.lease.prepare());t.lease.apply();t.lease.check()
assert(t.memory[t.record]==t.patched and t.api.writes==#t.config.edits)
for off=0,#t.raw-1 do
    local changed=false
    for _,e in ipairs(t.config.edits)do if off>=e.offset and off<e.offset+4 then changed=true end end
    if not changed then assert(t.memory[t.record]:byte(off+1)==t.raw:byte(off+1),'Payload changed')end
end
assert(t.lease.restore() and t.memory[t.record]==t.raw)
assert(t.lease.restore() and t.api.writes==2*#t.config.edits)
for n=1,#PROFILE.proximity.edits do
    t=fixture();assert(t.lease.prepare());t.api.fail=n
    assert(not pcall(t.lease.apply));assert(t.lease.restore() and t.memory[t.record]==t.raw)
end
t=fixture();t.memory[t.base+t.config.slot_rva]=nil
assert(not t.lease.prepare() and t.api.writes==0 and t.lease.restore())
t=fixture();t.memory[t.record]=replace(t.raw,t.config.edits[1].offset,bytes(t.config.edits[1].after))
assert(not pcall(t.lease.prepare) and t.api.writes==0 and t.lease.restore())
t=fixture();assert(t.lease.prepare());t.memory[t.record]=replace(t.raw,140,'xxxx')
assert(not pcall(t.lease.apply) and t.api.writes==0)
t=fixture();assert(t.lease.prepare());t.lease.apply()
t.memory[t.record]=replace(t.memory[t.record],148,'xxxx')
assert(not pcall(t.lease.check));assert(not t.lease.restore())
assert(t.memory[t.record]==replace(t.raw,148,'xxxx'),'Foreign field overwritten')
t=fixture();assert(t.lease.prepare());t.lease.apply();t.memory[t.base+t.config.slot_rva]=nil
local count=t.api.writes;assert(not t.lease.restore() and t.api.writes==count)
-- Failed cooldown write must roll back all fuse writes as part of one controller transaction.
t=fixture();local cd_restores=0
local function cooldown()
    return {prepare=function()return true end,apply=function()error('Cooldown failed')end,
        restore=function()cd_restores=cd_restores+1;return true end}
end
local control=controller(t.api,{cooldown=PROFILE.cooldown,proximity=t.config},t.base,{},cooldown,factory)
assert(not pcall(control.poll));assert(control.restore() and cd_restores==1 and t.memory[t.record]==t.raw)
return 'PASS six fuse fields only, payload bytes preserved, partial-write rollback, foreign values, identity changes, cooldown transaction rollback'

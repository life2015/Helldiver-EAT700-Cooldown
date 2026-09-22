-- Lease only EAT-700's native incendiary projectile fuse fields.
return function(api,config,base)
    local function bytes(s)return(s:gsub('..',function(h)return string.char(tonumber(h,16))end))end
    local function replace(s,off,value)return s:sub(1,off)..value..s:sub(off+#value+1)end
    local identity=bytes(config.identity_hex)
    local edits={}
    for _,e in ipairs(config.edits)do
        local before,after=bytes(e.before),bytes(e.after)
        assert(#before==4 and #after==4 and e.offset>=#identity and e.offset+4<=config.record_size)
        edits[#edits+1]={offset=e.offset,before=before,after=after,attempted=false}
    end
    local record,original,patched
    local function same()
        return record and api.ptr(base+config.slot_rva)==record and api.read(record,#identity)==identity
    end
    return {
        prepare=function()
            record=api.ptr(base+config.slot_rva)
            if not record then return false end
            assert(same(),'Incendiary projectile identity mismatch')
            original=assert(api.read(record,config.record_size),'Projectile read failed')
            assert(api.sha(original)==config.original_sha256,'Incendiary projectile definition differs')
            patched=original
            for _,e in ipairs(edits)do
                assert(original:sub(e.offset+1,e.offset+4)==e.before,'Original fuse field differs')
                assert(api.writable(record+e.offset,4),'Fuse field is not private RW data')
                patched=replace(patched,e.offset,e.after)
            end
            assert(api.sha(patched)==config.patched_sha256,'Patched fuse definition differs')
            return true
        end,
        apply=function()
            local expected=original
            for _,e in ipairs(edits)do
                assert(same() and api.read(record,config.record_size)==expected,'Projectile changed before fuse write')
                e.attempted=true
                api.write(record+e.offset,e.before,e.after)
                expected=replace(expected,e.offset,e.after)
            end
            assert(api.read(record,config.record_size)==patched,'Fuse readback failed')
        end,
        check=function()
            assert(same() and api.read(record,config.record_size)==patched,'Incendiary fuse ownership changed')
        end,
        restore=function()
            local success=true
            for i=#edits,1,-1 do
                local e=edits[i]
                if e.attempted then
                    if not same()then return false end
                    local current=api.read(record+e.offset,4)
                    if current==e.after then
                        local ok=pcall(api.write,record+e.offset,e.after,e.before)
                        success=ok and success
                    elseif current~=e.before then success=false end
                end
            end
            return success
        end
    }
end

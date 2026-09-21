-- A guarded lease on EAT-700's existing private RW cooldown field.
return function(api,config,base)
    local function bytes(s)return(s:gsub('..',function(h)return string.char(tonumber(h,16))end))end
    local before,after=bytes(config.before),bytes(config.after)
    local record,address
    local attempted=false
    local slot=base+config.slot_rva
    local identity=bytes(config.identity_hex)
    local function same()
        if not record or api.ptr(slot)~=record then return false end
        if api.read(record,#identity)~=identity then return false end
        local name=api.ptr(record+config.name_offset)
        return name and api.read(name,#config.name+1)==config.name..'\0'
    end
    return {
        prepare=function()
            record=api.ptr(slot)
            if not record then return false end
            assert(same(),'EAT-700 stratagem identity mismatch')
            address=record+config.offset
            assert(api.read(address,4)==before,'Original EAT-700 cooldown differs')
            assert(api.writable(address,4),'Cooldown is not private RW data')
            return true
        end,
        apply=function()
            assert(same(),'Stratagem changed before cooldown write')
            assert(api.read(address,4)==before,'Cooldown changed before application')
            attempted=true
            api.write(address,before,after)
        end,
        check=function()
            assert(same() and api.read(address,4)==after,'EAT-700 cooldown ownership changed')
        end,
        restore=function()
            if not attempted then return true end
            if not same() then return false end
            local current=api.read(address,4)
            if current==before then return true end
            if current~=after then return false end
            api.write(address,after,before);return true
        end
    }
end

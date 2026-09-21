-- Windows data access for the EAT addon. No executable allocation or native game calls.
return function()
    local ffi=require('ffi')
    assert(ffi.os=='Windows' and ffi.abi('64bit'),'Windows x64 required')
    ffi.cdef[[
        void *GetModuleHandleA(const char *name);
        uint32_t GetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity);
        void *GetCurrentProcess(void);
        uint32_t GetCurrentProcessId(void);
        uint64_t GetTickCount64(void);
        int ReadProcessMemory(void *process,const void *address,void *buffer,size_t size,size_t *read);
        int WriteProcessMemory(void *process,void *address,const void *buffer,size_t size,size_t *written);
        size_t VirtualQuery(const void *address,void *region,size_t size);
        typedef struct {
            void *base; void *allocation_base; uint32_t allocation_protection;
            uint16_t partition; uint16_t reserved; size_t size;
            uint32_t state; uint32_t protection; uint32_t type;
        } EAT700CooldownMemoryRegion;
        void *CreateFileW(const uint16_t *path,uint32_t access,uint32_t share,void *security,
                         uint32_t disposition,uint32_t flags,void *template_file);
        int ReadFile(void *file,void *buffer,uint32_t size,uint32_t *read,void *overlapped);
        int CloseHandle(void *handle);
        int32_t BCryptOpenAlgorithmProvider(void **algorithm,const uint16_t *name,const uint16_t *provider,uint32_t flags);
        int32_t BCryptCloseAlgorithmProvider(void *algorithm,uint32_t flags);
        int32_t BCryptCreateHash(void *algorithm,void **hash,void *object,uint32_t object_size,const void *secret,uint32_t secret_size,uint32_t flags);
        int32_t BCryptHashData(void *hash,const void *data,uint32_t size,uint32_t flags);
        int32_t BCryptFinishHash(void *hash,void *digest,uint32_t size,uint32_t flags);
        int32_t BCryptDestroyHash(void *hash);
    ]]
    local k,b=ffi.load('kernel32'),ffi.load('bcrypt')
    -- Another addon may have declared VirtualQuery with its own struct pointer.
    local query=ffi.cast('size_t (*)(const void *,void *,size_t)',k.VirtualQuery)
    local process=k.GetCurrentProcess()
    local api={}
    local function address(p)return tonumber(ffi.cast('uintptr_t',p))end
    function api.pid()return tonumber(k.GetCurrentProcessId())end
    function api.time()return tonumber(k.GetTickCount64())/1000 end
    function api.module(name)
        local p=k.GetModuleHandleA(name)
        assert(p~=nil,'Module missing')
        return address(p)
    end
    function api.read(p,n)
        if not p or p<0x10000 or p+n>0x800000000000 or n<=0 or n>1048576 then return nil end
        local data,count=ffi.new('uint8_t[?]',n),ffi.new('size_t[1]')
        if k.ReadProcessMemory(process,ffi.cast('const void *',p),data,n,count)==0 or count[0]~=n then return nil end
        return ffi.string(data,n)
    end
    function api.ptr(p)
        local data=api.read(p,8)
        if not data then return nil end
        local v=ffi.new('uint64_t[1]');ffi.copy(v,data,8)
        local n=tonumber(v[0])
        if n<0x10000 or n>=0x800000000000 then return nil end
        return n
    end
    function api.writable(p,n)
        local region=ffi.new('EAT700CooldownMemoryRegion[1]')
        if query(ffi.cast('const void *',p),region,ffi.sizeof(region[0]))~=ffi.sizeof(region[0]) then return false end
        return region[0].state==0x1000 and region[0].type==0x20000 and region[0].protection==4
            and p>=address(region[0].base) and p+n<=address(region[0].base)+tonumber(region[0].size)
    end
    function api.write(p,expected,data)
        assert(#expected==4 and #data==4 and api.writable(p,#data),'Write target is not private RW data')
        assert(api.read(p,#data)==expected,'Write precondition changed')
        local count=ffi.new('size_t[1]')
        assert(k.WriteProcessMemory(process,ffi.cast('void *',p),data,#data,count)~=0 and count[0]==#data,'Write failed')
        assert(api.read(p,#data)==data,'Write verification failed')
    end
    local function digest(feed)
        local algorithm,hash=ffi.new('void *[1]'),ffi.new('void *[1]')
        local ok,value=pcall(function()
            local name=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
            assert(b.BCryptOpenAlgorithmProvider(algorithm,name,nil,0)==0,'SHA256 provider failed')
            assert(b.BCryptCreateHash(algorithm[0],hash,nil,0,nil,0,0)==0,'SHA256 initialization failed')
            feed(function(data,n)assert(b.BCryptHashData(hash[0],data,n,0)==0,'SHA256 update failed')end)
            local bytes,out=ffi.new('uint8_t[32]'),{}
            assert(b.BCryptFinishHash(hash[0],bytes,32,0)==0,'SHA256 finish failed')
            for i=0,31 do out[#out+1]=string.format('%02X',bytes[i])end
            return table.concat(out)
        end)
        if hash[0]~=nil then b.BCryptDestroyHash(hash[0])end
        if algorithm[0]~=nil then b.BCryptCloseAlgorithmProvider(algorithm[0],0)end
        if not ok then error(value)end
        return value
    end
    function api.sha(data)return digest(function(push)push(data,#data)end)end
    function api.module_hash(module)
        local path=ffi.new('uint16_t[32768]')
        local n=k.GetModuleFileNameW(ffi.cast('void *',module),path,32768)
        assert(n>0 and n<32768,'Module path unavailable')
        local file=k.CreateFileW(path,0x80000000,7,nil,3,0x08000000,nil)
        assert(file~=ffi.cast('void *',-1),'Module file unavailable')
        local ok,value=pcall(digest,function(push)
            local buffer,count=ffi.new('uint8_t[1048576]'),ffi.new('uint32_t[1]')
            while true do
                assert(k.ReadFile(file,buffer,1048576,count,nil)~=0,'Module file read failed')
                if count[0]==0 then break end
                push(buffer,count[0])
            end
        end)
        k.CloseHandle(file)
        if not ok then error(value)end
        return value
    end
    return api
end

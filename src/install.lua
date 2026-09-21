return function(create_api,controller,profile,cooldown)
    if rawget(_G,'EAT700Cooldown') then return rawget(_G,'EAT700Cooldown')end
    local state={version=profile.version,status='starting'}
    rawset(_G,'EAT700Cooldown',state)
    local api,control,last_status
    local function report()
        if last_status==state.status then return end
        last_status=state.status
        pcall(function()
            local dir=os.getenv('LOCALAPPDATA');if not dir then return end
            local f=io.open(dir..'/EAT700Cooldown.log','w');if not f then return end
            f:write('EAT-700 Cooldown '..profile.version..'\n')
            for _,key in ipairs({'status','process_id','game_sha256','exe_sha256','base_cooldown','effective_cooldown','error','restored'})do
                f:write(key..'='..tostring(state[key] or '')..'\n')
            end
            f:write('target=EAT-700\nchange=cooldown_only\n');f:close()
        end)
    end
    local function stop(reason)
        state.stopped=true;state.error=tostring(reason)
        if control then
            local ok,restored=pcall(control.restore)
            state.restored=ok and restored
        end
        state.status='stopped';report()
    end
    report()
    local ok,why=pcall(function()
        api=create_api();state.process_id=api.pid()
        local base=api.module('game.dll')
        state.game_sha256=api.module_hash(base);state.exe_sha256=api.module_hash(api.module(nil))
        assert(state.game_sha256==profile.dll_sha256 and state.exe_sha256==profile.exe_sha256,'Unsupported game build')
        for offset,value in pairs(profile.signatures)do
            local signature=value:gsub('..',function(s)return string.char(tonumber(s,16))end)
            assert(api.read(base+tonumber(offset),#signature)==signature,'Native layout mismatch')
        end
        assert(type(update)=='function','Game update unavailable')
        control=controller(api,profile,base,state,cooldown)
    end)
    if not ok then stop(why);return state end
    local original,previous_shutdown=update,shutdown
    local next_poll=0
    local function poll()
        if state.stopped or api.time()<next_poll then return end
        next_poll=api.time()+1
        local accepted,reason=pcall(control.poll)
        if not accepted then stop(reason)else report()end
    end
    local function after(called,...)
        if not called then stop('original_update_failed');error((...),0)end
        poll();return ...
    end
    update=function(...)return after(pcall(original,...))end
    shutdown=function(...)
        state.stopped=true
        local restored,result=pcall(control.restore)
        state.restored=restored and result
        state.status=state.restored and 'shutdown_restored' or 'shutdown_restore_incomplete';report()
        if previous_shutdown then return previous_shutdown(...)end
    end
    state.status='waiting_for_stratagem';report()
    return state
end

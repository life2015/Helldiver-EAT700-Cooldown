-- Only the EAT-700 stratagem cooldown lease; no weapon table access.
return function(api,profile,base,state,cooldown_factory)
    local lease=cooldown_factory(api,profile.cooldown,base)
    local active=false
    return {
        poll=function()
            if active then lease.check();return end
            if not lease.prepare()then state.status='waiting_for_stratagem';return end
            lease.apply()
            active=true
            state.base_cooldown=profile.cooldown.base_seconds
            state.effective_cooldown=profile.cooldown.effective_seconds
            state.status='active'
        end,
        restore=lease.restore
    }
end

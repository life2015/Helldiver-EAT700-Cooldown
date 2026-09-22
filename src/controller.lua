-- Prepare the native incendiary fuse and cooldown before making either change.
return function(api,profile,base,state,cooldown_factory,proximity_factory)
    local lease=cooldown_factory(api,profile.cooldown,base)
    local fuse=profile.proximity and assert(proximity_factory,'Proximity factory required')(api,profile.proximity,base)
    local active=false
    return {
        poll=function()
            if active then lease.check();if fuse then fuse.check()end;return end
            if not lease.prepare()then state.status='waiting_for_stratagem';return end
            if fuse and not fuse.prepare()then state.status='waiting_for_projectile';return end
            if fuse then fuse.apply()end
            lease.apply()
            active=true
            state.base_cooldown=profile.cooldown.base_seconds
            state.effective_cooldown=profile.cooldown.effective_seconds
            state.fuse=fuse and 'proximity_incendiary' or 'vanilla'
            state.status='active'
        end,
        restore=function()
            local ok,a=pcall(lease.restore)
            local good,b=true,true
            if fuse then good,b=pcall(fuse.restore)end
            return ok and a and good and b
        end
    }
end

-- The published loader and this addon fail independently.
return function(run_shared,run_addon)
    local stages={}
    local function report(stage)
        stages[#stages+1]=stage
        pcall(function()
            local dir=os.getenv('LOCALAPPDATA');if not dir then return end
            local f=io.open(dir..'/EAT700Cooldown-startup.log','w');if not f then return end
            f:write(table.concat(stages,'\n')..'\n');f:close()
        end)
    end
    report('shared_loader_release=v14')
    local ok,why=pcall(run_shared)
    report(ok and 'shared_loader_returned' or 'shared_loader_error='..tostring(why))
    ok,why=pcall(run_addon)
    report(ok and 'addon_returned' or 'addon_error='..tostring(why))
    local state=rawget(_G,'EAT700Cooldown')
    report('addon_state='..tostring(state and state.status or 'missing'))
end

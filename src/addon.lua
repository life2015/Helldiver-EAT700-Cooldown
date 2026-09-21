-- HD2-Addon: mods/retrox/eat700_cooldown
local loader=rawget(_G,'CowboyBingusModLoader')
assert(loader and loader.api>=1 and loader.version>=16,'Bingus Shared Loader v15 or newer / API 1 required')
local name='mods/retrox/eat700_cooldown_impl'
assert(stingray.Application.can_get('lua',name),'EAT-700 Cooldown implementation missing')
return require(name)

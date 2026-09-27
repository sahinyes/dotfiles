-- Planted by tests/security_spec.lua: a hostile clone's module. Must never run.
local dir = os.getenv('HOSTILE_MARKER_DIR')
if dir then io.open(dir .. '/render-markdown', 'w'):close() end
return {}

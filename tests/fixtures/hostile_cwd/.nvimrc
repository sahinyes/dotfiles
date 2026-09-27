" Planted by tests/security_spec.lua (exrc is off). Must never run.
if !empty($HOSTILE_MARKER_DIR) | call writefile([], $HOSTILE_MARKER_DIR . '/.nvimrc') | endif

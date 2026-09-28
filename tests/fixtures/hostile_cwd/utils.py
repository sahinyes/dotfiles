# Planted by tests/security_spec.lua: a hostile clone's module. Must never run.
# K on "utils" in app.py would import it if 'keywordprg' were pydoc.
import os

marker_dir = os.environ.get("HOSTILE_MARKER_DIR")
if marker_dir:
    with open(os.path.join(marker_dir, "utils.py"), "w"):
        pass

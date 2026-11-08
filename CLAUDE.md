# Worlds Saga — notes for Claude
- Godot 4.3, GDScript, GL Compatibility renderer. Viewport 720×480; pixel art is drawn 5× (144×96 backgrounds).
- Owner: Vini (private English teacher). Replies to him in short Portuguese, no URLs unless asked.
- Story data comes from the original game (repo ViniMB/my-english, branch design-v05) via `tools/`.
- Before committing: `godot --headless --path . -- --autotest` must end with `problems: []`.
- Screenshots: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 720x480 -- --shots` → /tmp/ws-*.png.
- Avoid `:=` with Variant values (warnings are errors in this setup); use `=`.

# Instructions for AI assistants working in this repo

Start by reading `HANDOFF.md` — status, the user's standing rules, the round workflow, commands, score history and
what's next. Then `ARCHITECTURE.md` (code map) and `ASSETS.md` (asset paths and art pipeline).

The rules that matter most:
- Stay true to Heroes of Might and Magic III's mechanics and look; flag any deviation and ask first.
- Work in one session; at most one background judge agent at a time (no teams of parallel agents).
- Commit or push only when the user asks; end commit messages with your co-author line.
- Run `git checkout -- project.godot` after running Godot with a window (the scripts in `tools/` do it).
- Never print or commit keys: ElevenLabs from `ELEVENLABS_API_KEY`, Sketchfab inside Blender, the Vertex project
  id in the git-ignored `imagegen/vertex_project.txt`. The repo is public.
- Before claiming a visual change works, take a screenshot and look at it.
- Keep the docs current as part of every change, in the same commit: `HANDOFF.md` (status and last commit, score
  history after each judge, open findings, next steps, where new systems live, new gotchas), `ARCHITECTURE.md` for
  new scripts, systems or tools, `ASSETS.md` for new asset paths or art tools, `CREDITS.md` for new third-party
  assets. The docs must always let someone else resume exactly where the work stopped.

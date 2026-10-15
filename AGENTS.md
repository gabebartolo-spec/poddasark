# Agent rules for this project

These rules apply to every AI agent working on this project (Claude, Codex, Copilot,
Cursor or any other). They override an agent's default behaviour.

## Always read and follow the roadmap

1. **Before any work, read `docs/ROADMAP.md` in full.** Do this at the start of every
   session and every task, even if you think you remember it.
2. **Only work on the current milestone.** The current milestone is the earliest one
   whose gate the director has not signed off. Do not build features from a later
   milestone, even partly or "to save time later". The only exception is the M5 look
   work, which the director can start after M1's gate passes.
3. **Respect the gates.** A milestone is done only when the director says its gate has
   passed. Never mark a gate as passed yourself. Nothing wider than the wombat tutorial
   gets built until the director passes the M1 fun gate.
4. **Never decide a Director decision.** Anything listed under "Director decisions" in
   the roadmap, or as an open question in the brainstorm notes, must be asked of the
   director. Do not settle it in code, data or docs. If a task needs one, stop and ask.
5. **If a request conflicts with the roadmap, say so before acting.** Name the
   milestone or rule it conflicts with and ask the director how to proceed. The
   director may change the roadmap. Only edit `docs/ROADMAP.md` when the director
   explicitly asks.

## Design authority

- The director designs this game. AI helps build it but never makes design decisions.
  The lead director has final say.
- The design decisions are recorded in `docs/brainstorms/`. Read the relevant notes
  before working on a feature.
- Every feature must pass the core test: *does it help the player leave the park
  better than they found it, and closer to a balanced ecosystem?*
- Predators are never villains, in mechanics, text or presentation.
- Never invent final art, palette or style. Placeholder art is neutral grey and
  labelled as placeholder.

## Engineering conventions (confirmed by the director, M0)

- Ecosystem logic goes in `src/eco/`. It must not use scene nodes, the scene tree or
  rendering, so it can be tested and balanced without playing.
- Content (species, needs, parks, phase scripts) goes in `data/`, not in code.
- All randomness in the ecosystem logic goes through `SeededRng`, never the global
  `randf()` or `randi()`.
- Placeholder art is neutral grey and labelled as placeholder.
- The renderer is GL Compatibility, so the browser build works. Do not switch it.

## Checks before pushing

```
tools/godot.sh --headless --path . --import
tools/godot.sh --headless --path . -s tests/run_tests.gd
```

At every milestone gate, also export both presets (Windows and Web) and check that the
web build loads in a browser.

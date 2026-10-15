# Roadmap

This is the build plan for the game, taken from the design interview in
`docs/brainstorms/2026-10-14-core-idea.md`. The director designs the game. This plan
only puts their decisions in an order to build them. Anything marked
**Director decision** must be decided by the director before that step is built.

## How this roadmap works

- **Each milestone ends in a gate.** The director plays the build and signs off before
  the next milestone starts. If a gate fails, fix that milestone first and don't build
  on top of it.
- **The order follows the campaign.** Each milestone adds one layer, just as each
  campaign phase does when the camera zooms out: needs, then more species, then
  predators, then weather. Each layer is built and proven before the next goes on top.
- **Prove the fun before building wide.** No campaign shell, menus or free play until
  the wombat tutorial is fun (gate M1).
- **Every feature must pass the core test:** *does it help the player leave the park
  better than they found it, and closer to a balanced ecosystem?*

## Fixed constraints (already decided)

| | |
|---|---|
| Engine | Godot 4.7.2 |
| Platform | PC only |
| Release | itch.io, as a Windows download and a browser build |
| Tone | Relaxing |
| Pillars | Predators are never villains. Prey, predators and weather all do an essential job for the ecosystem. |
| Team | Lead director (final say). Their girlfriend joins later. |

## Recommended engineering conventions

These are proposed, not decided. The director should confirm them before M0 is done.

- **Keep the ecosystem logic separate from what's on screen.** The needs, contentedness
  and population maths live in plain GDScript classes, not inside scene nodes. Then
  they can be tested, and balanced without playing.
- **Put content in data files.** Species, their needs, park layouts and phase scripts go
  in data files (Godot resources or JSON), not in code. Your girlfriend can then add and
  tune animals in the editor without touching code.
- **Use a seeded random number generator**, so the same park and seed replays the same
  way. That makes bugs reproducible and balance testable.
- **Placeholder art is neutral grey and labelled as placeholder.** The look is a
  director decision, and nothing here invents it.
- **Export to the browser early and often.** Godot's web export behaves differently
  from desktop, so check the itch browser build at every gate, not just at release.

---

## M0: Foundations

**Goal:** an empty Godot project that runs on PC and in the browser on itch.

Build:
- A Godot 4.7.2 project in this repo, with a folder layout for the separate ecosystem
  logic, data files and scenes
- An overhead free camera: pan, zoom, rotate
- A flat grey placeholder terrain
- A Windows export, plus a browser export uploaded to a private itch.io page
- A basic test setup for the ecosystem logic

**Director decisions:**
- Confirm the engineering conventions above
- Camera feel: how high, how far it zooms, and whether it rotates freely or in steps

**Gate:** the director can move the camera around an empty park, on PC and in the
browser.

---

## M1: The lonely wombat (campaign phase 1)

**Goal:** the opening tutorial, playable start to finish with placeholder art. This is
the most important milestone, because it proves the whole game's core loop on one
animal.

Build:
- **The needs system:** water, food and safety (here, shelter), plus company. Each
  species' needs come from its data file.
- **Contentedness:** a value worked out from how well each need is met
- **Observing:** click an animal to see its needs, in the style of the Jurassic World
  Evolution needs panels
- **Placing things directly:** water sources, food sources, shelter (a burrow for the
  wombat)
- **Cleanup:** removing litter and pollutants, and invasive plants
- **The tutorial script:** one issue at a time, ending when the wombat finds its
  friends and family

**Director decisions:**
- The order of the wombat's four issues (scared, alone, hungry, no shelter), and which
  comes first
- How the wombat finds its friends: does the player search, follow clues, or fix the
  land so they come out?
- How contentedness is shown to the player
- What the player can place, and whether placing costs anything
- Whether cleanup is part of the wombat tutorial or comes in M2

**Gate (the fun gate):** the director plays the wombat tutorial and confirms it's
relaxing, readable, and makes them care about the wombat. **Nothing below starts until
this passes.**

---

## M2: Apply learnings (campaign phase 2)

**Goal:** zoom out to a larger area with several prey species and more environmental
features. There are no predators yet.

Build:
- The zoom-out moment between phases
- Several prey species, each with its own safety type (herd animals in numbers,
  tree-dwellers in trees, ground mammals in undergrowth and burrows)
- More environmental features to place and manage
- **The harmony gate:** a park-wide check that every species is at or above its
  contentedness level
- A tool to run the ecosystem logic forward without playing and report the results,
  for balance testing

**Director decisions:**
- Which species, and which features
- The contentedness level for the gate, and whether it differs between species
- How the player sees progress towards the harmony gate

**Gate:** the director can balance a multi-species park and pass the harmony gate with
no predators, and it still feels relaxing.

---

## M3: The dingo (campaign phase 3)

**Goal:** bring in the first predator, with its own small tutorial. It teaches the
balance it takes to keep a predator alive.

Build:
- **Predation:** the dingo hunts prey to meet its food need
- **Predator–prey balance:** prey numbers feed the predator's contentedness, and
  hunting lowers prey numbers. The system has to settle at a stable balance, not swing
  wildly.
- The predator tutorial
- Balance testing with the tool from M2

**Director decisions:**
- What the player sees when a hunt happens. It must never cast the dingo as a villain.
- How much the player can influence predator numbers
- What the tutorial teaches, step by step

**Gate:** the director confirms a hunt feels like a natural part of the ecosystem, not
a loss, and that a balanced park with dingoes can pass the harmony gate.

---

## M4: The full Australian park (campaign phase 4)

**Goal:** the last zoom-out, with more predators and the Weather Events system.

Build:
- **The eagle and the crocodile**, plus any new prey needed to keep the balance
- Rivers and wetlands for the crocodile (new kinds of environment)
- **The Weather Events system**, as a general framework. In Australia, the event is a
  **bush fire**.
- **Calling the fire brigade:** the player calls them, and they come and fight the fire
- **Recovery:** the player kick-starts regrowth, then nature takes over. Fire is part of
  the ecosystem.

**Director decisions:**
- The new prey species
- How often bush fires happen, how much damage they do, and what triggers them.
  Remember: setbacks, never total destruction.
- What kick-starting regrowth looks like for the player
- Whether fire benefits the ecosystem in game terms (for example, some plants that
  only regrow after fire)

**Gate:** the director plays the whole Australian campaign from the wombat to the
harmony gate, including at least one bush fire, and it's fun from start to finish.

---

## M5: The look

**Goal:** replace the grey placeholders with the director's art direction.

This milestone can begin any time after M1 passes, at the director's call. It isn't
blocked by M2 to M4.

**Director decisions:** everything about the look: art style, palette, how the animals
look, UI style, music and sound. AI does not decide any of these.

**Gate:** the director signs off the look of the Australian park.

---

## M6: Campaign shell and save

**Goal:** turn the Australian park into a game someone can start, stop and come back to.

Build:
- A main menu and a settings screen
- Saving and loading
- The campaign structure: parks unlocked in order (only Australia for now)
- The game's name and a title screen

**Director decisions:**
- The game's name (is "poddasark" the title?)
- What's in the settings menu

**Gate:** a new player can start the game, play the Australian campaign across several
sessions, and finish it.

---

## M7: Free play

**Goal:** the second mode.

Build:
- **First:** free play in any unlocked park
- **Later, only if the director wants it:** custom environments. This is much bigger,
  because it needs a map editor or a generator.

**Director decisions:**
- Free play rules: does the harmony gate apply, and are there starting conditions?
- Whether custom environments ship in the first release or come later

**Gate:** the director plays a free-play session in the Australian park and it holds up.

---

## M8: First release on itch.io

**Goal:** ship Australia.

Build:
- The itch.io page, with the Windows download and the browser build
- A performance check of the browser build on mid-range PCs
- A playtest with people who haven't seen the game, followed by fixes

**Director decisions:** the release date, the itch page text and screenshots, and the
price model.

**Gate:** the director publishes the game.

---

## After the first release

These are tabled until the director comes back to them:
- What happens after Australia, which park is next, and whether each park opens zoomed
  in on one animal
- Weather events for other parks
- Bringing the girlfriend into the project: shared repo access and an editor workflow
  for her to add species in data files

## Dependency summary

```
M0 → M1 (fun gate) → M2 → M3 → M4 → M6 → M7 → M8
                └──────── M5 (the look, any time after M1) ────────┘
```

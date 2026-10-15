# Data

Game content lives here, not in code, so it can be tuned without touching scripts.

- `species/<id>.json`: a species' needs, behaviour, mood thresholds and facts.
  Need types: `resource` (a feature within range), `safety` (a shelter within range,
  minus fear of nearby detritus) and `company` (others of its kind nearby).
- `parks/<id>.json`: a park's layout: starting features, animals (including hidden
  ones that come out when the land is healthy), placeable items and their costs,
  and the camera area.
- `phases/<id>.json`: a campaign phase's steps, each with a `done_when` condition,
  plus the finale text.

Numbers and text marked as placeholder or draft are first passes for the director to
tune. Species facts must be checked against sources before release.

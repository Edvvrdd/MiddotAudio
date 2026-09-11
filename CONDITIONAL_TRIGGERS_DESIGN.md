# Conditional Triggers & Parameters — Design Proposal

Status: PROPOSAL — awaiting review, not implemented.

References: FMOD manual ch. 7 (Parameters: continuous/discrete/labeled), ch. 4 (activation Conditions on markers/instruments); Wwise ch. 22 (Random/Sequence/**Switch**/Blend containers — "Switch Containers play back contents based on the current Switch or State within the game"); Godot 4.7 `AudioStreamInteractive`, `AudioStreamRandomizer`, `AudioStreamPlaylist` docs.

## 1. How the professional systems model it

- **Wwise Switch Container**: a container whose children are chosen by the game's current **Switch** (e.g. `SetSwitch("surface", "grass")` then `PostEvent("footstep")`). Related: **States** (global, affect many objects at once), **RTPCs** (continuous game parameter mapped to properties like volume/pitch), **Blend Containers** (simultaneous layers, crossfaded by RTPC).
- **FMOD**: **game parameters** (continuous, or **discrete/labeled** — integer steps with names) + **activation conditions**: "you can set [a marker/instrument] to only function if certain conditions are met. This allows you to create events that behave in different ways under different circumstances." Conditions are comparisons against parameter values, ANDed together.
- Common core: **the game declares state → the middleware picks content at trigger time based on that state.** Both systems also allow property automation driven by continuous values (RTPC), which is mix automation, not triggering.

## 2. What Godot gives us natively

- **`AudioStreamInteractive`**: clips + a transition table, switched via a player property, with crossfade/fill rules. This is Godot's built-in Switch Container — but it's built for **ongoing playback switching** (music layers), not pick-one-at-trigger-time one-shots.
- **`AudioStreamRandomizer`**: native random pool with per-stream probability weights + random pitch/volume — could eventually replace our hand-rolled random, but it does *not* do conditions or shuffle-with-refill semantics we already shipped.
- No runtime parameter/state system exists in Godot audio. Parameters must live in game code; the middleware just needs to evaluate conditions at `play_sound()` time — pure GDScript, fully within the stock-audio constraint.

**Decision:** pick the variation **at trigger time** in the parser (like Wwise does for one-shots). Do NOT route through `AudioStreamInteractive` — it would force all variations into one stream resource, complicate the bank, and buy us nothing for one-shots. It *is* the right native tool if we later add music/layered events with crossfades (noted below, deferred).

## 3. Proposed model (the minimal version that covers the FMOD+Wwise semantics)

**Parameters** — named values the game sets before/at trigger time:

```gdscript
AudioManager.set_parameter("surface", "grass")   # switch: string
AudioManager.set_parameter("speed", 4.5)          # continuous: float
```

- Declared in the authoring app (name + type + allowed values) so the UI can offer dropdowns and the parser can validate; the bank exports the declarations as metadata.
- Switch parameters: game passes a string. Continuous: game passes a float.
- Unknown/unset parameter at play time → treated as "no match" (with a parser warning, consistent with existing warning-not-crash policy).

**Conditions** — attached to **variations** (not to new container objects):

- One condition per variation: `{param, op, value}`.
- Ops: `==`, `!=` for switches; `<`, `<=`, `>`, `>=`, `between` for continuous.
- At `play_sound()`: filter variations by condition against current parameter values → pick among survivors with existing random/shuffle/playlist logic.
- All variations fail → **fallback: play nothing + warn** (Wwise behavior for an unmatched switch; predictable and debuggable).
- No conditions on any variation → behaves exactly like today (backward compatible by construction).

Why conditions-on-variations instead of a Wwise-style Switch Container object: same expressive power for the 90% case (footsteps-per-surface, UI-per-language), no new graph node type, no new container runtime, reuses everything we've built. Wwise's container exists to organize *large* switch sets; we don't have those yet. `ponytail:` if a switch group with 20+ entries appears, promote to a real Switch Container object then.

## 4. Soundbank format v3 (additive — v2 parsers keep working)

```gdscript
format_version: 3

# NEW: parameter declarations (name -> metadata)
parameters: Dictionary  # "surface" -> {type: "switch", values: ["grass","stone","wood"]}
                        # "speed"   -> {type: "range", min: 0.0, max: 10.0}

# EXISTING events dictionary, two additive fields per event:
#   conditions: Array  # index-aligned with sounds; "" or {} = always eligible
#   (declared params only affect authoring/validation; parser needs no opt-in)
```

Crucially, `sounds` stays `Array[String]` with a **parallel** `conditions: Array[String-encoded-dict]` — never a breaking reshape. A v2 parser loading a v3 bank ignores `conditions` and `parameters` (additive fields), plays all variations, and only warns on the version bump. That's the exact tolerance the parser already implements.

## 5. Authoring UI

1. **New "Params" left tab** (next to Events/Assets/Mixer): add parameter → name + type (Switch/Range) + values (comma list / min-max). Rename with follow-through, same pattern as bus rename.
2. **Condition editor on Sound nodes** (graph): when ≥1 parameter exists, each Sound node gains a small condition row: `[param ▾] [op ▾] [value ▾ or number field]`, plus "always" default. Stored per-variation in `e.conditions[i]`.
3. **Trigger node untouched** — filtering happens after variation selection logic, so Simple/Random/Playlist semantics are unchanged.

## 6. Parser changes (middleware-game-test)

- `set_parameter(name, value)` + `get_parameter(name)` on AudioManager (simple Dictionary).
- `_pick_audio()` gains a filter pass before random/shuffle/playlist selection.
- Warning (not error) on: unknown parameter, no eligible variation, malformed condition.
- `format_version` check accepts 3 (existing policy: warn on newer, tolerate).

## 7. Explicitly deferred (do not build now)

- **RTPC property automation** (continuous param → live volume/pitch): that's mix automation, a different feature; the trigger system doesn't need it.
- **Blend/layered playback + crossfades**: native home is `AudioStreamInteractive`; only relevant for music. Revisit with the music features.
- **Conditions on events** (whole event gated, not per-variation): games can do `if` themselves before calling play; add only when asked.
- **Multiple ANDed conditions per variation**: one condition covers the realistic cases; format has room to grow (value could become an Array later — additive).

## 8. Implementation order

1. Format v3 in both `SoundBank.gd` copies + parser `set_parameter` + `_pick_audio` filtering
2. Params left tab (declare/rename)
3. Condition editor row on Sound nodes + export/import of `conditions`
4. Headless round-trip test: author event with conditions → export → parser picks correctly per parameter value
5. Bump `format_version` to 3 in export; verify middleware-game-test still loads it (v2-tolerant parser path)

## 9. Questions for review

1. **Fallback when no variation matches** — play nothing + warn (proposed), or always play variation #0, or config per event? Wwise plays nothing; FMOD conditions simply don't fire. I propose nothing+warn.
2. **Condition model** — one condition per variation (proposed) enough, or do you foresee needing AND of two (e.g. `surface == stone AND speed > 3`)?
3. **Where parameters live in the UI** — separate Params tab (proposed) vs. a collapsible section inside the Events panel?
4. Should the exported bank include the parameter declarations (proposed, for parser validation + future editor features) or keep the bank minimal (conditions only)?

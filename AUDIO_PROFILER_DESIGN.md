# MiddotWare Remote Audio Profiler — Design Draft

Status: design, not yet implemented.

References consulted:

- Godot 4.7 offline docs (`godot-docs`): `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, `EngineProfiler`, `AudioServer`, command-line tutorial
- FMOD Studio manual: "Profiling" (ch. 12), "Editing During Live Update" (ch. 13)
- Wwise manual: "Specifying network ports", "Mixing Desk remote connection", Performance Monitor / Voice Monitor chapters

## 1. What FMOD and Wwise actually do (the model to copy)

- **FMOD Live Update**: the game embeds a communication module that opens a network port. Studio connects to a *running game*, receives a stream of profiler data (event instances, voices, CPU, levels), records it into sessions, and can also *push* changes back (mix tweaks audible immediately). Only string-bank metadata changes don't propagate.
- **Wwise Remote Connection**: the game runs a communication module on configurable network ports; the authoring tool discovers running games on the network ("Remote Connection dialog lists consoles"), connects, then monitors voices/game objects/performance bus activity in real time, and can tweak bus/object properties live (Mixing Desk).
- Common shape: **game-side agent + network channel + authoring-side UI**, with monitoring data flowing game → tool, and (optionally) parameter tweaks flowing authoring → game.

## 2. What Godot gives us (from the offline docs)

Two viable transports — both pure GDScript, no C++/GDExtension:

### Option A — EditorDebuggerPlugin (best fit for "game running in the target editor")

Godot's debugger is a built-in, scriptable remote channel:

- Game side: `EngineDebugger.register_message_capture("middot_audio", ...)` receives messages from the editor; `EngineDebugger.send_message("middot_audio:stats", data)` sends data out. Active whenever the game runs with debug enabled (F5 from the target editor — the default for dev).
- Authoring side (the target editor, via the `middot_audio` addon): an `EditorDebuggerPlugin` subclass registers a capture prefix, gets `EditorDebuggerSession` objects for each running instance, can `send_message` back and `add_session_tab()` — i.e. a dedicated **Audio** tab appears in the target editor's debugger bottom panel, exactly where Godot's own profilers live.
- Works with multiple simultaneous game sessions (`get_sessions()`), matching how the editor can run several instances.

Constraint: the monitoring UI lives in the **target game's editor**, not in MiddotWare's standalone window.

### Option B — custom TCP channel (works everywhere, incl. exported games)

- Game side: the `middot_audio` addon spins up a `TCPServer` (port 9071, configurable) when a `MIDDOT_PROFILER=1` env var or project setting is set.
- MiddotWare connects as a client, the agent streams JSON frames ~10×/sec.
- Same protocol could later carry write-back (live update): bank reload, bus volume changes (`AudioServer.set_bus_volume_db`).

Recommendation: **build A first** (zero new networking, native debugger UX, matches how Godot devs already work), keep the wire protocol identical so B can reuse it. This mirrors Wwise, whose profiler UI is also inside the authoring tool but whose data comes over a documented socket.

## 3. What data is available (pure stock Godot — no engine changes)

From `AudioServer`:

- Per-bus peak volume L/R (`get_bus_peak_volume_left_db`/`right_db`) — the voice-meter strip FMOD/Wwise show
- Bus graph sanity: names, sends, volumes, mute/solo/bypass — everything MiddotWare authored
- Mix timing: `get_time_since_last_mix`, `get_output_latency`, `get_speaker_mode`
- `set_enable_tagging_used_audio_streams(true)` + stream tagging for playback introspection

Voices / what is playing:

- The `middot_audio` **AudioManager owns every voice it spawns** (it creates the `AudioStreamPlayer`s), so it can maintain a voice table directly: event name, bank, bus, playback position (`get_playback_position`), `playing`, loop count — no engine hooks needed
- Per-event counters (active instances, last-triggered time, plays-per-second) come free from the same structure
- Cross-engine note: FMOD/Wwise count "voices" engine-wide including sounds the game plays outside the middleware; ours will report *middleware-managed voices only*. That's honest and useful — it's the Middot-managed subset. Document it in the UI.

## 4. Proposed architecture

```
┌────────────────────────────┐        ┌──────────────────────────────┐
│ Target game (addon)        │        │ Monitoring surface           │
│                            │        │                              │
│ AudioManager               │        │ A: EditorDebuggerPlugin      │
│  └─ VoiceTracker (new)     │──A───▶ │    "Audio" tab in debugger   │
│     tracks own players     │        │                              │
│  └─ BusPoller (new)        │──B───▶ │ B: standalone socket client  │
│     10 Hz bus peaks,       │        │    (MiddotWare, later)       │
│     mix timings            │        │                              │
└────────────────────────────┘        └──────────────────────────────┘
```

- **Game side** (add to `middot_audio` addon, `@tool`-safe):
  - `VoiceTracker`: AudioManager notifies it on `play()`/`finished`; holds `{event, bus, pos, playing}` rows; ~10 Hz it emits a snapshot
  - `BusPoller`: per-bus peak collection, one frame of data per tick
  - Both serialize to a flat Array (Godot debugger messages take Arrays; JSON for the TCP path)
- **Editor side** (also in the addon, `@tool` EditorPlugin):
  - `AudioProfilerPlugin extends EditorDebuggerPlugin`: `_has_capture("middot_audio")`, `_capture` feeds the tab UI
  - Tab UI: three columns like FMOD's profiler — **Voices** (live table: event, bus, position, playing), **Buses** (L/R peak meters per bus), **Events** (recent triggers, active instance counts)
  - History ring buffer (last ~30 s) so FMOD-style session scrubbing is possible later; sessions exportable as JSON

## 5. Wire protocol (shared by A and B)

Messages prefixed `middot_audio:` (Godot captures are string-prefixed by design):

| Message | Direction | Payload |
| --- | --- | --- |
| `middot_audio:hello` | game → tool | `{project, bank_path, format_version, godot_version}` |
| `middot_audio:voices` | game → tool | `[{event, bus, pos, playing}, ...]` @10 Hz |
| `middot_audio:buses` | game → tool | `[{name, peaks:[l,r], volume_db, mute, solo}, ...]` @10 Hz |
| `middot_audio:event_fired` | game → tool | `{event, timestamp}` (fire-and-forget log) |
| `middot_audio:cmd_*` | tool → game | later: set_bus_volume, reload_bank (live update) |

Keep frames small, JSON-encodable arrays only — Godot's debugger messages are Variant arrays; the TCP path uses the same shape serialized as JSON.

## 6. Phasing

1. **P1 — voice + bus monitoring via debugger plugin** (game editor tab). Smallest useful thing; zero new infra; directly answers "what is playing and how loud".
2. **P2 — MiddotWare-side TCP client** (Option B) so the standalone app can monitor exported/dev games. Same protocol.
3. **P3 — live update (write-back)**: bus volume/mute from the mixer tab, bank hot-reload. FMOD proves the value; `AudioServer` + `use_bank()` already expose everything needed.
4. **P4 — session recording/replay** (FMOD-style saved sessions), only if real use appears.

## 7. Risks / honest limits

- **Not a full engine voice census**: Godot doesn't expose a global "all playing streams" registry. We profile what the middleware owns (which is the point of the middleware — but sounds the game plays via raw AudioStreamPlayer are invisible). Mitigation: document it; optionally offer an opt-in helper the game can call to register foreign players.
- Debugger-plugin monitoring only exists when the game runs **with debugging from the editor** (F5). Exported/standalone games need the P2 socket path.
- 10 Hz × ~50 voices of JSON is trivial bandwidth (<100 KB/s), but debugger message flooding at very high voice counts should be capped (batch, drop if >200 voices, aggregate counts instead of rows).

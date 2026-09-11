# MiddotAudio (MiddotWare)

A free, open-source **audio middleware authoring tool** for Godot 4.7, inspired by FMOD Studio and Wwise.

The app is **not** an audio engine. It authors a **soundbank** — a Godot `.tres` resource — plus the audio files it references. A target game embeds a small parser addon (`middot_audio`) that reads the bank and wires everything up with **stock Godot audio only** (AudioServer, buses, AudioStreamPlayer). No external audio engine, no C++ modules, no GDExtension runtime.

- **This repo** = the authoring app: define sound events on a free-canvas node graph (Sound / Trigger / Variable / Output nodes, three-mode trigger transforms, bus mixer), save projects as `.middot`, and export the soundbank.
- **Target game** = the consumer: a small parser autoload (`AudioManager`) exposes `play("event_name")` and handles simple/random/shuffle/playlist/conditional triggers and bus routing.

Built with Godot 4.7 (GL Compatibility). Open the project and run `control.tscn` to start authoring.

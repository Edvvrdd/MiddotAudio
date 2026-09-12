class_name SoundBank
extends Resource

## Version of the soundbank format. Target parsers check this before reading `events`.
## v2: events may have trigger=random with a sounds[] variation list.
## v3: events may have trigger=conditional with conditions[] ({param, op, value});
##     the game sets parameters via AudioManager.set_parameter() before play.
##     Sound nodes may carry file_volume_db / pitch_scale (per-file, additive:
##     file volume adds to the event's volume_db in dB; pitch replaces it).
##     trigger "sync": all sounds[] play simultaneously (one player each).
## buses: bus name → parent bus name ("" or missing = no parent).
@export var format_version: int = 3

@export var events: Dictionary = {}

@export var buses: Dictionary = {}

## Linear volume 0-100 per bus; absent = unchanged (100).
@export var bus_volumes: Dictionary = {}

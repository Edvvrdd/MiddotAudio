class_name SoundBank
extends Resource

## Version of the soundbank format. Target parsers check this before reading `events`.
## v2: events may have trigger=random with a sounds[] variation list.
## v3: events may have trigger=conditional with conditions[] ({param, op, value});
##     the game sets parameters via AudioManager.set_parameter() before play.
## buses: bus name → parent bus name ("" or missing = no parent).
@export var format_version: int = 3

@export var events: Dictionary = {}

@export var buses: Dictionary = {}

## Linear volume 0-100 per bus; absent = unchanged (100).
@export var bus_volumes: Dictionary = {}

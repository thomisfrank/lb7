extends Node

# Simple project-wide logger. Keep `VERBOSE` false to mute prints.
@export var VERBOSE: bool = false

# General static flags (used when the script is preloaded as LOG)
static var VERBOSE_STATIC: bool = true
static var TRACKING_STATIC: bool = false

static func log(msg: Variant) -> void:
	if VERBOSE_STATIC:
		print(msg)

static func log_args(args: Array) -> void:
	if VERBOSE_STATIC:
		# Join args into a single string for printing
		var out = ""
		for a in args:
			out += str(a) + " "
		print(out.strip_edges())

# Tracking-specific prints — these are intended to remain visible when
# general VERBOSE_STATIC is false. Toggle TRACKING_STATIC to control.
static func tracking(msg: Variant) -> void:
	if TRACKING_STATIC:
		print(msg)

static func tracking_args(args: Array) -> void:
	if TRACKING_STATIC:
		var out = ""
		for a in args:
			out += str(a) + " "
		print(out.strip_edges())

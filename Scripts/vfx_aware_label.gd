extends Label
## Helper to apply visual effects setting to text shader materials
##
## Attach this to any Label that uses TextJitter or other animated shaders
## to automatically freeze/resume animation based on settings.

func _ready() -> void:
	if has_node("/root/SettingsManager"):
		var settings_mgr = get_node("/root/SettingsManager")
		if settings_mgr and settings_mgr.has_signal("visual_effects_changed"):
			settings_mgr.visual_effects_changed.connect(_on_visual_effects_changed)
			# Apply current VFX state
			_apply_visual_effects_state(settings_mgr.visual_effects_enabled)


func _on_visual_effects_changed(enabled: bool) -> void:
	_apply_visual_effects_state(enabled)


func _apply_visual_effects_state(enabled: bool) -> void:
	if material and material is ShaderMaterial:
		var shader_mat = material as ShaderMaterial
		if enabled:
			shader_mat.set_shader_parameter("animation_speed", 1.0)
		else:
			shader_mat.set_shader_parameter("animation_speed", 0.0)

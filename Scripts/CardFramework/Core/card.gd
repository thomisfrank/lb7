## A card object that represents a single playing card with drag-and-drop functionality.
##
## The Card class extends DraggableObject to provide interactive card behavior including
## hover effects, drag operations, and visual state management. Cards can display
## different faces (front/back) and integrate with the card framework's container system.
##
## Key Features:
## - Visual state management (front/back face display)
## - Drag-and-drop interaction with state machine
## - Integration with CardContainer for organized card management
## - Hover animation and visual feedback
##
## Usage:
## [codeblock]
## var card = card_factory.create_card("ace_spades", target_container)
## card.show_front = true
## card.move(target_position, 0)
## [/codeblock]
class_name Card
extends DraggableObject

const LOG = preload("res://Scripts/logger.gd")

# Static counters for global card state tracking
static var hovering_card_count: int = 0
static var holding_card_count: int = 0


## The name of the card.
@export var card_name: String
## The size of the card.
@export var card_size: Vector2 = CardFrameworkSettings.LAYOUT_DEFAULT_CARD_SIZE
## The suit of the card (draw, swap, back, etc.)
@export var card_suit: String
## The value of the card
@export var value: String
## Color A for the dynamic background
@export var color_a: Color
## Color B for the dynamic background  
@export var color_b: Color
## Icon texture for the card
@export var icon_texture: Texture2D
## (lock overlay feature removed)
## Whether the front face of the card is shown.
## If true, the front face is visible; otherwise, the back face is visible.
@export var show_front: bool = true:
	set(value):
		if value:
			front_face.visible = true
			back_face.visible = false
		else:
			front_face.visible = false
			back_face.visible = true


# Card data and container reference
var card_info: Dictionary
var card_container: CardContainer
var back_customized: bool = false


@onready var front_face: Control = $FrontFace
@onready var back_face: Control = $BackFace
@onready var front_dynamic_bg: ColorRect = $FrontFace/TextureRect/DynamicBackground
@onready var back_dynamic_bg: ColorRect = $BackFace/TextureRect/DynamicBackground
@onready var front_icon: TextureRect = $FrontFace/TextureRect/Icon
@onready var back_icon: TextureRect = $BackFace/TextureRect/Icon
@onready var front_top_value: Label = $FrontFace/TextureRect/TopValue
@onready var front_bottom_value: Label = $FrontFace/TextureRect/TopValue2
@onready var back_top_value: Label = $BackFace/TextureRect/TopValue
@onready var back_bottom_value: Label = $BackFace/TextureRect/TopValue2

# (lock overlay variables removed)


func _ready() -> void:
	super._ready()
	# Set card size for both faces
	front_face.size = card_size
	back_face.size = card_size
	pivot_offset = card_size / 2
	# This creates a unique material for this card instance's front face
	if front_dynamic_bg and front_dynamic_bg.material:
		front_dynamic_bg.material = front_dynamic_bg.material.duplicate()

	# Also create a unique material for the back face so shader params are per-instance
	if back_dynamic_bg and back_dynamic_bg.material:
		back_dynamic_bg.material = back_dynamic_bg.material.duplicate()

	# Update card visuals if data is available
	update_card_visuals()

	# ...existing code...



func _on_move_done() -> void:
	card_container.on_card_move_done(self)


## Updates all card visuals based on current properties
func update_card_visuals() -> void:
	if not is_node_ready():
		return
		
	# Update dynamic background colors
	if front_dynamic_bg and front_dynamic_bg.material:
		var shader_mat = front_dynamic_bg.material as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("color_a", color_a)
			shader_mat.set_shader_parameter("color_b", color_b)

	# Do NOT overwrite the back face material here. The back face should be
	# controlled only via setup_card_back() (which applies Back.json styling).
	# Avoid writing front colors into the back material so the back graphic
	# remains consistent and never appears on the front face.
	
		# Update icon textures
	if icon_texture:
			# Only set the front icon for non-back cards. Back cards must not use
			# their back texture on the front face.
			if front_icon and card_suit != "back":
				front_icon.texture = icon_texture
			# Do not apply the same icon_texture to the back face here for normal
			# cards — the back face should be controlled by setup_card_back(). For
			# the dedicated back card (suit == "back") we allow the icon_texture
			# to be used on the back face if present.
			if back_icon and card_suit == "back":
				back_icon.texture = icon_texture
	
	# Update value labels
	if front_top_value:
		front_top_value.text = value
	if front_bottom_value:
		front_bottom_value.text = value
	
	# Hide value labels on back face for "back" suit cards
	if card_suit == "back":
		if back_top_value:
			back_top_value.visible = false
		if back_bottom_value:
			back_bottom_value.visible = false
	else:
		if back_top_value:
			back_top_value.text = value
			back_top_value.visible = true
		if back_bottom_value:
			back_bottom_value.text = value
			back_bottom_value.visible = true

## Sets the card data from JSON information
## @param card_data: Dictionary containing card information from JSON
func set_card_data(arg1: Variant, arg2: Variant = null, arg3: Variant = "") -> void:
	# Backwards-compatible API:
	# - Called as set_card_data(card_info: Dictionary)
	# - Or as set_card_data(id: String, value: String, suit: String = "")
	if typeof(arg1) == TYPE_DICTIONARY:
		var card_data: Dictionary = arg1
		# Basic fields
		card_name = card_data.get("name", card_name)
		value = card_data.get("value", value)
		card_suit = card_data.get("suit", card_suit)

		# Colors (optional arrays [r,g,b,a])
		if card_data.has("color_a") and card_data.color_a is Array and card_data.color_a.size() >= 4:
			var ca = card_data.color_a
			color_a = Color(ca[0], ca[1], ca[2], ca[3])
		if card_data.has("color_b") and card_data.color_b is Array and card_data.color_b.size() >= 4:
			var cb = card_data.color_b
			color_b = Color(cb[0], cb[1], cb[2], cb[3])

		# Icon texture may be provided by factories (preloaded) as a separate arg
		if arg2 and arg2 is Texture2D:
			icon_texture = arg2
		elif card_data.has("icon_path"):
			var icon_path = card_data.get("icon_path", "")
			if icon_path != "":
				var res_path = icon_path
				# If the path looks relative, try to resolve under Assets/icons/
				if not res_path.begins_with("res://"):
					res_path = "res://Assets/icons/" + res_path
				var tex = load(res_path) as Texture2D
				if tex:
					icon_texture = tex

	else:
		# Old style call
		var new_id: String = String(arg1)
		var new_value: String = String(arg2)
		var new_suit: String = String(arg3)
		card_name = new_id
		value = new_value
		if new_suit != "":
			card_suit = new_suit

	update_card_visuals()

## Sets up the card back with specific back styling
## @param back_data: Dictionary containing back card data from Back.json
func setup_card_back(back_data: Dictionary) -> void:
	# Store back data for when card is ready
	if not is_node_ready():
		# Defer until after _ready() is called
		call_deferred("setup_card_back", back_data)
		return
	
	if back_data.has("color_a") and back_data.color_a is Array:
		var color_array = back_data.color_a
		if color_array.size() >= 4:
			var back_color_a = Color(color_array[0], color_array[1], color_array[2], color_array[3])
			if back_dynamic_bg and back_dynamic_bg.material:
				var shader_mat = back_dynamic_bg.material as ShaderMaterial
				if shader_mat:
					shader_mat.set_shader_parameter("color_a", back_color_a)
	
	if back_data.has("color_b") and back_data.color_b is Array:
		var color_array = back_data.color_b
		if color_array.size() >= 4:
			var back_color_b = Color(color_array[0], color_array[1], color_array[2], color_array[3])
			if back_dynamic_bg and back_dynamic_bg.material:
				var shader_mat = back_dynamic_bg.material as ShaderMaterial
				if shader_mat:
					shader_mat.set_shader_parameter("color_b", back_color_b)
	
	# Load and set back icon if specified
	if back_data.has("icon_path") and back_icon:
		var icon_path = "res://Assets/icons/" + back_data["icon_path"]
		var back_texture = load(icon_path) as Texture2D
		if back_texture:
			back_icon.texture = back_texture
			back_icon.visible = true
		else:
			push_warning("Could not load back icon: " + icon_path)
			back_icon.visible = false

	# Mark that the back face has been explicitly customized so other updates
	# do not overwrite the back visuals.
	back_customized = true
	
	# Hide value labels on back face for cleaner look
	if back_top_value:
		back_top_value.visible = false
	if back_bottom_value:
		back_bottom_value.visible = false


## Public: lock this card visually and prevent dragging/interactions
func lock(overlay_alpha: float = 0.7, debug_visual: bool = false) -> void:
	if not is_instance_valid(self):
		return
	# If overlay already exists, ensure visible
	if has_node("LockOverlay"):
		var existing = get_node("LockOverlay")
		existing.visible = true
		LOG.log_args(["Card.lock: existing overlay ->", name, "parent=", get_path(), "z=", existing.z_index])
		return

	# Prevent interaction
	can_be_interacted_with = false

	# Single full-card overlay TextureRect
	var overlay = TextureRect.new()
	overlay.name = "LockOverlay"
	overlay.texture = load("res://Assets/UI/LockOverlay.png")
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 200
	overlay.modulate = Color(1, 1, 1, 0.0)
	add_child(overlay)
	set_meta("lock_badge", overlay)

	LOG.log_args(["Card.lock: created overlay ->", name, "overlay_path=", overlay.get_path(), "parent=", get_path(), "z=", overlay.z_index, "card_size=", card_size])

	var tween = create_tween()
	tween.tween_property(overlay, "modulate:a", overlay_alpha, 0.2)
	tween.tween_callback(func(): LOG.log_args(["Card.lock: overlay visible ->", name, "overlay=", overlay.name, "alpha=", overlay.modulate.a]))

	# Diagnostic: log ancestor chain and siblings to help find occluders
	_log_overlay_stack(overlay)

	# Optional debug overlay: bright translucent ColorRect so it's obvious on screen
	if debug_visual:
		if not has_node("LockOverlayDebug"):
			var dbg = ColorRect.new()
			dbg.name = "LockOverlayDebug"
			dbg.color = Color(1, 0.0, 0.0, 0.25)
			dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
			dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dbg.z_index = 1000
			add_child(dbg)
			LOG.log_args(["Card.lock: added debug overlay ->", name, "dbg_z=", dbg.z_index])


func _log_overlay_stack(overlay: Node) -> void:
	if not is_instance_valid(overlay):
		return
	var info = []
	var node = self
	while node:
		var entry = {
			"name": node.name,
			"class": node.get_class(),
			"visible": node.is_visible_in_tree() if node is CanvasItem else false,
		}
		if node is CanvasItem:
			entry["z_index"] = (node as CanvasItem).z_index
		if node is CanvasLayer:
			entry["canvas_layer"] = (node as CanvasLayer).layer
		info.append(entry)
		node = node.get_parent()

	LOG.log_args(["Card._log_overlay_stack: ancestor_chain=", info])

	var p = overlay.get_parent()
	if p:
		var siblings = []
		for child in p.get_children():
			var s = {
				"name": child.name,
				"class": child.get_class(),
				"visible": child.is_visible_in_tree() if child is CanvasItem else false,
			}
			if child is CanvasItem:
				s["z_index"] = (child as CanvasItem).z_index
			siblings.append(s)
		LOG.log_args(["Card._log_overlay_stack: siblings_of_parent=", p.get_path(), siblings])


## Public: unlock this card (remove overlay and restore interaction)
func unlock() -> void:
	if not is_instance_valid(self):
		return
	can_be_interacted_with = true
	var overlay = null
	if has_meta("lock_badge"):
		overlay = get_meta("lock_badge")
	elif has_node("LockOverlay"):
		overlay = get_node("LockOverlay")

	if overlay and is_instance_valid(overlay) and overlay.is_inside_tree():
		var tween = create_tween()
		tween.tween_property(overlay, "modulate:a", 0.0, 0.12)
		tween.tween_callback(Callable(overlay, "queue_free"))
		LOG.log_args(["Card.unlock: fading out overlay ->", name, "overlay=", overlay.name])

	if has_meta("lock_badge"):
		remove_meta("lock_badge")


## (lock overlay code removed)


## (lock overlay code removed)
## Public: show locked visuals on this card
## (lock overlay code removed)


## Returns the card to its original position with smooth animation.
func return_card() -> void:
	super.return_to_original()


# Override state entry to add card-specific logic
func _enter_state(state: DraggableState, from_state: DraggableState) -> void:
	super._enter_state(state, from_state)
	
	match state:
		DraggableState.HOVERING:
			hovering_card_count += 1
		DraggableState.HOLDING:
			holding_card_count += 1
			if card_container:
				card_container.hold_card(self)

# Override state exit to add card-specific logic
func _exit_state(state: DraggableState) -> void:
	match state:
		DraggableState.HOVERING:
			hovering_card_count -= 1
		DraggableState.HOLDING:
			holding_card_count -= 1
	
	super._exit_state(state)

## Legacy compatibility method for holding state.
## @deprecated Use state machine transitions instead
func set_holding() -> void:
	if card_container:
		card_container.hold_card(self)


## Returns a string representation of this card.
func get_string() -> String:
	return card_name


## Checks if this card can start hovering based on global card state.
## Prevents multiple cards from hovering simultaneously.
func _can_start_hovering() -> bool:
	return hovering_card_count == 0 and holding_card_count == 0


## Handles mouse press events with container notification.
func _handle_mouse_pressed() -> void:
	card_container.on_card_pressed(self)
	super._handle_mouse_pressed()


## Handles mouse release events and releases held cards.
func _handle_mouse_released() -> void:
	super._handle_mouse_released()
	if card_container:
		card_container.release_holding_cards()
# play_area.gd

extends CardContainer

class_name PlayArea

var is_card_being_dragged: bool = false
var _drop_setup_attempts: int = 0
var _background: TextureRect = null  # Reference to the visual background

# Helper to compute combined ancestor scale for a node (excluding the node itself)
func _compute_combined_ancestor_scale(node: Node) -> Vector2:
	var s = Vector2.ONE
	var cur = node
	while cur and cur.get_parent():
		cur = cur.get_parent()
		if cur and cur is CanvasItem:
			# CanvasItem.scale exists for Control-derived nodes
			s *= cur.scale
	return s

func _ready() -> void:
	# Let CardContainer setup the drop zone and card manager
	super._ready()
	
	# Get reference to the background texture
	_background = get_node_or_null("TextureRect")
	
	# Start with background transparent (but PlayArea visible for hit detection)
	if _background:
		_background.modulate.a = 0.0

	# NOTE: We no longer use a CenterContainer for layout, as it interferes
	# with card effect animations. Instead, we will manually position the card
	# in _update_target_positions.
	
	# Debug: print drop zone sensor info after initialization
	if debug_mode:
		if drop_zone != null:
			LOG.log_args(["PlayArea: drop_zone present. sensor_size=", drop_zone.sensor_size, ", stored_sensor_size=", drop_zone.stored_sensor_size])
		else:
			LOG.log("PlayArea: drop_zone is null after ready()")

	# Connect to all cards in the card manager to detect dragging
	if card_manager:
		# If drop_zone sensor_size was left at (0,0), set it explicitly to card size.
		# Use a deferred helper that waits until the PlayArea has a non-zero global rect
		# to avoid Control assertions like "parent_rect_size.x == 0.0".
		if drop_zone != null and drop_zone.sensor_size == Vector2(0, 0):
			_ensure_drop_zone_sensor()

		# Use a timer to periodically check for dragging state
		var timer = Timer.new()
		timer.wait_time = 0.05  # Check every 50ms
		timer.timeout.connect(_check_drag_state)
		add_child(timer)
		timer.start()
	
	if debug_mode:
		LOG.log_args(["PlayArea ready - drop zone enabled:", enable_drop_zone])


## Helper: ensure the drop_zone sensor is configured only when background has valid size.
func _ensure_drop_zone_sensor() -> void:
	if drop_zone == null:
		return
	if drop_zone.sensor_size != Vector2(0, 0):
		return
	
	# Check if background has a valid size
	if not _background or _background.size == Vector2(0, 0):
		# Background not ready yet, retry
		_drop_setup_attempts += 1
		if _drop_setup_attempts > 10:
			LOG.log("PlayArea: drop_zone sensor setup giving up after retries")
			return
		
		var t = Timer.new()
		t.wait_time = 0.1
		t.one_shot = true
		t.timeout.connect(Callable(self, "_ensure_drop_zone_sensor"))
		add_child(t)
		t.start()
		return
	
	# Background is ready, configure the sensor to match its size and position
	var bg_size = _background.size * _background.scale
	var bg_pos = _background.position
	LOG.log_args(["PlayArea: configuring drop_zone sensor - size:", bg_size, "pos:", bg_pos])
	drop_zone.set_sensor(bg_size, bg_pos, sensor_texture, sensor_visibility)
	_drop_setup_attempts = 0  # Reset for any future use

## Check if any card is being dragged and manage visibility
func _check_drag_state() -> void:
	if not card_manager or not drop_zone:
		return
	
	var any_card_being_dragged = false
	
	# Check all containers for cards in HOLDING state
	for container_id in card_manager.card_container_dict:
		var container = card_manager.card_container_dict[container_id]
		if container == self:
			continue  # Skip checking our own container
		
		# Check all cards in the container
		for card in container._held_cards:
			if card.current_state == Card.DraggableState.HOLDING:
				any_card_being_dragged = true
				break
		
		if any_card_being_dragged:
			break
	
	# Manage state transitions
	if any_card_being_dragged and not is_card_being_dragged:
		# Drag just started
		is_card_being_dragged = true
	elif not any_card_being_dragged and is_card_being_dragged:
		# Drag just ended
		is_card_being_dragged = false

	# Update visibility based on drag state and mouse position
	if is_card_being_dragged:
		# Check if mouse is over the drop zone
		var mouse_in_zone = drop_zone.check_mouse_is_in_drop_zone()
		
		# Fade in/out the background based on mouse position
		if _background:
			_background.modulate.a = 1.0 if mouse_in_zone else 0.0
	else:
		# If not dragging, only show background if there are cards inside
		if _background and get_card_count() == 0:
			_background.modulate.a = 0.0


## Public API: hide/show the PlayArea visual (keeps the Control active for hit detection)
func hide_visual() -> void:
	if _background:
		_background.modulate.a = 0.0

func show_visual() -> void:
	if _background:
		# Only show if dragging or there are cards; otherwise keep hidden
		if is_card_being_dragged or get_card_count() > 0:
			_background.modulate.a = 1.0
		else:
			_background.modulate.a = 0.0


## Override to position cards in the play area
func _update_target_positions() -> void:
	if not _background:
		return
	
	for card in _held_cards:
		# Use card_manager.card_size if card.size is zero
		var card_size = card.size if card.size != Vector2.ZERO else card_manager.card_size
		
		if card_size == Vector2.ZERO:
			# Still no valid size, skip positioning for now
			LOG.log("PlayArea: card has no size yet, skipping positioning")
			continue
		
		var bg_rect = _background.get_global_rect()
		var bg_center = bg_rect.get_center()
		
		# Calculate the card's center position
		# Since card.position is the top-left corner, we need to offset by half the card size
		var target_pos = bg_center - (card_size / 2.0)
		
		LOG.log_args(["PlayArea: centering card - bg_center=", bg_center, "card_size=", card_size, "target_pos=", target_pos])
		
		card.move(target_pos, 0)
		card.visible = true


## Only allow single-card play into the play area
func _card_can_be_added(cards: Array) -> bool:
	var can_add = cards.size() == 1 and get_card_count() == 0
	LOG.log_args(["PlayArea: _card_can_be_added called with ", cards.size(), " cards, returning: ", can_add])
	return can_add

## When a card finishes moving into the PlayArea, wait, then trigger the effect.
func on_card_move_done(card: Card) -> void:
	# Only trigger effect if card is in PlayArea AND hasn't been processed yet
	if card.card_container != self:
		return
	
	# Check if this card has already had its effect triggered (use metadata flag)
	if card.has_meta("playarea_effect_triggered"):
		LOG.log_args(["PlayArea: on_card_move_done - effect already triggered for card=", card.name, ", ignoring"])
		return
	
	# Mark this card as processed so we don't retrigger
	card.set_meta("playarea_effect_triggered", true)

	# Ensure the card is shown face-up in the play area
	card.show_front = true
	card.can_be_interacted_with = false

	# Wait for 0.5 seconds as requested
	await get_tree().create_timer(0.5).timeout

	# Notify EffectsManager if available
	if has_node("/root/EffectsManager"):
		var effects_manager = get_node("/root/EffectsManager")
		await effects_manager.execute_card_effect(card, "player")
		# Clean up the flag after effect completes
		if card and card.has_meta("playarea_effect_triggered"):
			card.remove_meta("playarea_effect_triggered")
	else:
		LOG.log("PlayArea: EffectsManager not found as autoload")
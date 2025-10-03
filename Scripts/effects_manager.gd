# effects_manager.gd

extends Node

signal card_effect_executed(card: Card, effect_type: String, result: Dictionary)

# Internal signal used to notify waiting callers when an enqueued effect completes

enum EffectType { DRAW, SWAP, DISCARD, SHUFFLE }

var card_manager: CardManager
var player_hand: Hand
var opponent_hand: Hand
var deck: Pile
var discard_pile: Pile

var current_turn: String = "player"
var game_phase: String = "play"
var locked_cards: Array[Card] = []

const LOG = preload("res://Scripts/logger.gd")

var pending_swap_card: Card = null
var pending_swap_player: String = ""
var is_waiting_for_swap_selection: bool = false
@export var play_area: Control
var pending_swap_owner_hand: Hand = null

# Effect processing queue and state
var _effect_queue: Array = []
var _processing_effects: bool = false
var _current_request_id: String = ""
var _completed_results: Dictionary = {}

# Track cards that were interactive before locking
var _cards_locked_during_effect: Array[Card] = []


func _lock_all_cards() -> void:
	# Lock all cards in all hands and containers (except locked cards which are already non-interactive)
	_cards_locked_during_effect.clear()
	var all_containers = [player_hand, opponent_hand]
	for container in all_containers:
		if not container:
			continue
		for card in container._held_cards:
			if card.can_be_interacted_with:
				_cards_locked_during_effect.append(card)
				card.can_be_interacted_with = false
				# Keep mouse_filter as STOP to allow hover visual feedback
	LOG.log_args(["EffectsManager: locked", _cards_locked_during_effect.size(), "cards during effect"])


func _unlock_all_cards() -> void:
	# Restore interaction for cards that were locked during the effect
	# BUT: do NOT unlock cards that have the is_locked meta (those are permanently locked)
	var unlocked_count = 0
	for card in _cards_locked_during_effect:
		if card and is_instance_valid(card):
			# Skip cards that are permanently locked
			if card.has_meta("is_locked"):
				print("[UNLOCK_ALL] Skipping permanently locked card: ", card.name)
				continue
			
			card.can_be_interacted_with = true
			unlocked_count += 1
			# mouse_filter is already STOP, no need to restore
	LOG.log_args(["EffectsManager: unlocked", unlocked_count, "cards after effect (", _cards_locked_during_effect.size() - unlocked_count, " remain locked)"])
	_cards_locked_during_effect.clear()



func _process_queue() -> void:
	# Run the queue processing as an async loop so callers can await results
	if _processing_effects:
		return
	_processing_effects = true

	# Defer SHUFFLE requests so they run after all other effects in this processing batch.
	var deferred_shuffles: Array = []
	LOG.log_args(["EffectsManager: _process_queue starting. queue_size=", _effect_queue.size()])

	while _effect_queue.size() > 0:
		var req = _effect_queue.pop_front()
		if not req:
			continue
		_current_request_id = req.id
		var card: Card = req.card
		var player: String = req.player
		var effect_type: String = req.effect_type
		var chosen_card: Card = req.chosen_card

		# If it's a SHUFFLE request, defer it until after other effects
		if effect_type == "SHUFFLE":
			deferred_shuffles.append(req)
			continue

		var res: Dictionary = {"success": false, "message": "Unhandled effect"}
		match effect_type:
			"DRAW":
				res = await execute_draw_effect(card, player)
			"SWAP":
				res = await execute_swap_effect(card, player, chosen_card)
				# If swap entered a selection phase, wait until the selection completes
				if is_waiting_for_swap_selection:
					while is_waiting_for_swap_selection:
						await get_tree().process_frame
					if _completed_results.has(req.id):
						res = _completed_results[req.id]
			_:
				res = {"success": false, "message": "Unknown effect type: " + effect_type}

		# Store result so the original caller can pick it up
		_completed_results[req.id] = res

	# After processing all non-shuffle effects, run deferred shuffles (last step)
	for sreq in deferred_shuffles:
		# run each shuffle and store its result
		LOG.log_args(["EffectsManager: executing deferred shuffle req=", sreq.id, "player=", sreq.player])
		var sres = execute_shuffle_effect(sreq)
		_completed_results[sreq.id] = sres
		LOG.log_args(["EffectsManager: deferred shuffle completed req=", sreq.id, "result=", sres])

	# Finished processing
	_processing_effects = false
	_current_request_id = ""


func initialize(manager: CardManager, p_hand: Hand, o_hand: Hand, deck_pile: Pile, discard: Pile):
	card_manager = manager
	player_hand = p_hand
	opponent_hand = o_hand
	deck = deck_pile
	discard_pile = discard


func set_play_area(pa: Control) -> void:
	# Public setter so callers (like main.gd) can provide the PlayArea node at runtime
	if pa == null:
		return
	play_area = pa
	LOG.log_args(["EffectsManager: set_play_area ->", play_area])

func execute_card_effect(card: Card, player: String = "player", chosen_card: Card = null) -> Dictionary:
	# Debug: log every call to track where duplicates come from
	var card_name_str = "null"
	if card:
		card_name_str = card.name
	var chosen_name_str = "null"
	if chosen_card:
		chosen_name_str = chosen_card.name
	LOG.log_args(["EffectsManager: execute_card_effect called - card=", card_name_str, " player=", player, " chosen_card=", chosen_name_str, " is_waiting=", is_waiting_for_swap_selection])
	
	# If a chosen_card is provided while we're waiting for a swap selection,
	# complete the pending swap immediately.
	if chosen_card != null and is_waiting_for_swap_selection and pending_swap_card != null:
		return await _complete_swap(chosen_card)

	# Prevent enqueueing the same card while a swap is already waiting for selection
	if is_waiting_for_swap_selection and pending_swap_card != null and card == pending_swap_card:
		LOG.log_args(["EffectsManager: execute_card_effect ignored - swap already in progress for card=", card.name])
		return {"success": false, "message": "Swap already in progress for this card"}

	if not card:
		return {"success": false, "message": "No card provided"}

	var parts = card.card_name.split("_")
	if parts.size() != 2:
		return {"success": false, "message": "Invalid card format: " + card.card_name}

	var effect_type = parts[0].to_upper()

	# Enqueue the effect request and return the final result once processed.
	var req_id = str(Engine.get_frames_drawn()) + "_" + str(randi())
	var req = {
		"id": req_id,
		"card": card,
		"player": player,
		"effect_type": effect_type,
		"chosen_card": chosen_card
	}

	_effect_queue.append(req)

	# Kick off the processing loop if it's not already running
	if not _processing_effects:
		_process_queue()

	# Wait for the processing to finish this request (poll small frames)
	while not _completed_results.has(req_id):
		await get_tree().process_frame

	var result = _completed_results[req_id]
	_completed_results.erase(req_id)
	return result


## Public: enqueue a shuffle effect to be processed as the last step in the current batch
func enqueue_shuffle(card: Card = null, player: String = "player") -> String:
	var req_id = str(Engine.get_frames_drawn()) + "_shuffle_" + str(randi())
	var req = {
		"id": req_id,
		"card": card,
		"player": player,
		"effect_type": "SHUFFLE",
		"chosen_card": null
	}
	LOG.log_args(["EffectsManager.enqueue_shuffle called -> id=", req_id, "player=", player, "card=", card])
	_effect_queue.append(req)
	# Kick off processing if necessary
	if not _processing_effects:
		_process_queue()
	return req_id

## Execute a draw effect: discard the card, wait, draw a new card, and lock it.
func execute_draw_effect(played_card: Card, player: String) -> Dictionary:
	if not deck or not player_hand or not opponent_hand or not discard_pile:
		return {"success": false, "message": "Game components not initialized"}

	# Lock all interactive cards during the effect
	_lock_all_cards()

	# Hide PlayArea visuals while the effect runs
	if play_area and play_area.has_method("hide_visual"):
		play_area.hide_visual()

	# 1. Discard the played card
	if play_area and play_area.has_card(played_card):
		play_area.remove_card(played_card)
	discard_pile.add_card(played_card)

	# 2. Wait for 0.5 seconds
	await get_tree().create_timer(0.5).timeout

	# 3. Draw a new card
	var player_hand_ref = player_hand if player == "player" else opponent_hand
	if deck.get_card_count() < 1:
		_unlock_all_cards()
		return {"success": false, "message": "No cards left in deck"}

	var drawn_cards = deck.get_top_cards(1)
	if drawn_cards.is_empty():
		_unlock_all_cards()
		return {"success": false, "message": "Failed to draw card from deck"}

	var drawn_card = drawn_cards[0]
	if not deck.remove_card(drawn_card):
		_unlock_all_cards()
		return {"success": false, "message": "Failed to remove card from deck"}

	player_hand_ref.add_card(drawn_card)
	
	# 4. Lock the newly drawn card
	if drawn_card and is_instance_valid(drawn_card) and drawn_card.has_method("lock"):
		var parent_path = "null"
		var dp = drawn_card.get_parent()
		if dp:
			parent_path = dp.get_path()
		LOG.log_args(["EffectsManager: locking drawn_card=", drawn_card.name, " parent=", parent_path])
		# Use lock_card() so the EffectsManager records and enforces the locked state
		lock_card(drawn_card)
	elif drawn_card and is_instance_valid(drawn_card):
		# Fallback: mark non-interactive
		drawn_card.can_be_interacted_with = false

	var result = {
		"success": true, "effect_type": "DRAW", "player": player,
		"discarded_card": played_card, "drawn_card": drawn_card, "locked_card": drawn_card
	}

	# Restore PlayArea visuals
	if play_area and play_area.has_method("show_visual"):
		play_area.show_visual()

	# Unlock all cards after effect completes
	_unlock_all_cards()

	emit_signal("card_effect_executed", played_card, "DRAW", result)
	
	# Shuffle the player's hand after drawing
	player_hand_ref.shuffle()
	
	return result


## Execute a shuffle effect: shuffle the requested hand (or deck/container) as the final step
func execute_shuffle_effect(req: Dictionary) -> Dictionary:
	var player = req.player if req.has("player") else "player"
	var target_hand: Hand = player_hand if player == "player" else opponent_hand

	if not target_hand:
		return {"success": false, "message": "No hand available to shuffle"}

	# Simple shuffle like the example - just call shuffle()
	target_hand.shuffle()

	var res = {"success": true, "effect_type": "SHUFFLE", "player": player}
	emit_signal("card_effect_executed", req.card if req.card else null, "SHUFFLE", res)
	return res


## Execute a swap effect: move the card, then start the selection phase.
func execute_swap_effect(played_card: Card, player: String, chosen_card: Card = null):
	if not player_hand or not opponent_hand:
		return {"success": false, "message": "Game components not initialized"}

	var opponent_hand_ref = opponent_hand if player == "player" else player_hand

	# This is the start of the swap process
	if not chosen_card:
		if opponent_hand_ref.get_card_count() == 0:
			# If opponent has no cards, just discard the played card
			if play_area and play_area.has_card(played_card):
				play_area.remove_card(played_card)
			discard_pile.add_card(played_card)
			return {"success": false, "message": "Opponent has no cards to swap"}

		# Lock all interactive cards before starting the swap animation
		_lock_all_cards()

		# Hide PlayArea visuals while swap animation and selection runs
		if play_area and play_area.has_method("hide_visual"):
			LOG.log("EffectsManager: hide_visual() called for PlayArea before swap")
			play_area.hide_visual()

		pending_swap_card = played_card
		# Record which hand originally owned the played swap card (if available)
		if played_card and played_card.card_container and played_card.card_container is Hand:
			pending_swap_owner_hand = played_card.card_container
		else:
			# Fallback to player param
			pending_swap_owner_hand = player_hand if player == "player" else opponent_hand
		pending_swap_player = player
		# Debug log: record which hand is the owner and who initiated the swap
		var owner_path = "null"
		if pending_swap_owner_hand:
			owner_path = pending_swap_owner_hand.get_path()
		LOG.log_args(["EffectsManager: swap started - pending_swap_card=", pending_swap_card.name, " owner_path=", owner_path, " pending_swap_player=", pending_swap_player])
		is_waiting_for_swap_selection = true

		# 1. Remove card from play area to move it freely
		if play_area and play_area.has_card(played_card):
			play_area.remove_card(played_card)
			# Reparent to the game layer to ensure it's visible and preserve its global position
			if is_instance_valid(played_card):
				var prev_parent = played_card.get_parent()
				var saved_global = Vector2.ZERO
				if played_card is CanvasItem:
					saved_global = played_card.global_position
				if prev_parent and prev_parent != self:
					prev_parent.remove_child(played_card)
				# Defer adding and restoring global position to avoid scene tree race conditions
				call_deferred("_deferred_reparent_apply", played_card, saved_global)


		# 2. Move the card to the left of the deck
		if deck:
			# Move the played card closer to the deck (previously 450px left; reduce by ~half)
			var target_pos = deck.global_position - Vector2(225, 0)
			played_card.move(target_pos, 0)
			# Wait for the move animation to finish
			await get_tree().create_timer(0.5).timeout 

		# 3. Begin selection phase - temporarily unlock opponent cards for selection
		_enable_opponent_card_selection(opponent_hand_ref)

		return {
			"success": true, "waiting_for_selection": true,
			"message": "Click on one of the opponent's cards to swap"
		}

	# This part is called when a chosen_card is provided (completing the swap)
	var res = await _complete_swap(chosen_card)
	# Restore PlayArea visuals after swap completes
	if play_area and play_area.has_method("show_visual"):
		LOG.log("EffectsManager: show_visual() called for PlayArea after swap")
		play_area.show_visual()
	
	# Unlock all cards after swap completes
	_unlock_all_cards()
	
	# Shuffle both hands after swap - player and opponent
	player_hand.shuffle()
	opponent_hand.shuffle()
	
	return res

func _enable_opponent_card_selection(opponent_hand_ref: Hand):
	for card in opponent_hand_ref._held_cards:
		# Skip cards that are permanently locked
		if card.has_meta("is_locked"):
			print("[SELECTION] skipping locked card for selection: ", card.name)
			continue
		# Mark card as selectable for the duration of selection. This flag is
		# checked by DraggableObject so hover animations can be allowed even when
		# global interaction is otherwise disabled.
		card.set_meta("selection_enabled", true)
		card.can_be_interacted_with = true
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Add blue outline highlight for selection phase
		_add_selection_highlight(card)
		
		# Connect hover events to show/hide highlight
		if not card.is_connected("mouse_entered", Callable(self, "_on_selectable_card_hover_enter").bind(card)):
			card.connect("mouse_entered", Callable(self, "_on_selectable_card_hover_enter").bind(card))
		if not card.is_connected("mouse_exited", Callable(self, "_on_selectable_card_hover_exit").bind(card)):
			card.connect("mouse_exited", Callable(self, "_on_selectable_card_hover_exit").bind(card))
		
		# Connect to the card's input to detect the click
		var cb = Callable(self, "_on_opponent_card_selected").bind(card)
		if not card.is_connected("gui_input", cb):
			card.connect("gui_input", cb)

func _on_opponent_card_selected(event: InputEvent, selected_card: Card):
	# We only care about left-clicks
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()):
		return
		
	if not is_waiting_for_swap_selection:
		return

	# Disable selection and restore original appearance for all opponent cards
	var opponent_hand_ref = opponent_hand if pending_swap_player == "player" else player_hand
	for card in opponent_hand_ref._held_cards:
		# Clear selection-enabled marker and restore interaction flags
		if card.has_meta("selection_enabled"):
			card.remove_meta("selection_enabled")
		card.can_be_interacted_with = false
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		# Remove selection highlight
		_remove_selection_highlight(card)

		# Disconnect all signal handlers for this card
		var gui_cb = Callable(self, "_on_opponent_card_selected").bind(card)
		if card.is_connected("gui_input", gui_cb):
			card.disconnect("gui_input", gui_cb)

		var hover_enter_cb = Callable(self, "_on_selectable_card_hover_enter").bind(card)
		if card.is_connected("mouse_entered", hover_enter_cb):
			card.disconnect("mouse_entered", hover_enter_cb)

		var hover_exit_cb = Callable(self, "_on_selectable_card_hover_exit").bind(card)
		if card.is_connected("mouse_exited", hover_exit_cb):
			card.disconnect("mouse_exited", hover_exit_cb)
	
	# Complete the swap
	await _complete_swap(selected_card)


func _on_selectable_card_hover_enter(card: Card) -> void:
	# Show the highlight when mouse enters during selection phase
	if not is_waiting_for_swap_selection:
		return
	
	if card.has_meta("selection_highlight"):
		var highlight = card.get_meta("selection_highlight")
		if is_instance_valid(highlight):
			highlight.visible = true
			# Animate in
			var tween = create_tween()
			tween.tween_property(highlight, "modulate:a", 1.0, 0.15)


func _on_selectable_card_hover_exit(card: Card) -> void:
	# Hide the highlight when mouse exits during selection phase
	if not is_waiting_for_swap_selection:
		return
	
	if card.has_meta("selection_highlight"):
		var highlight = card.get_meta("selection_highlight")
		if is_instance_valid(highlight):
			# Animate out
			var tween = create_tween()
			tween.tween_property(highlight, "modulate:a", 0.0, 0.15)
			tween.tween_callback(func(): highlight.visible = false)


func _complete_swap(chosen_card: Card) -> Dictionary:
	# Determine owner and other hand based on recorded owner to avoid string mismatches
	var owner_hand: Hand = pending_swap_owner_hand if pending_swap_owner_hand != null else (player_hand if pending_swap_player == "player" else opponent_hand)
	var other_hand: Hand = opponent_hand if owner_hand == player_hand else player_hand

	# Remove chosen card from its current hand (should be the other hand)
	LOG.log_args(["EffectsManager: _complete_swap - owner_hand=", owner_hand.get_path(), " other_hand=", other_hand.get_path(), " chosen_card=", chosen_card.name, " pending_swap_card=", pending_swap_card.name])
	if other_hand.has_card(chosen_card):
		other_hand.remove_card(chosen_card)
	else:
		LOG.log_args(["EffectsManager: WARNING - other_hand did not contain chosen_card=", chosen_card.name])

	# Reparent both cards temporarily to this EffectsManager so they share the same coordinate space
	if is_instance_valid(chosen_card):
		var saved_chosen_global = Vector2.ZERO
		if chosen_card is CanvasItem:
			saved_chosen_global = chosen_card.global_position
		var prev_chosen_parent = chosen_card.get_parent()
		if prev_chosen_parent and prev_chosen_parent != self:
			prev_chosen_parent.remove_child(chosen_card)
		call_deferred("_deferred_reparent_apply", chosen_card, saved_chosen_global)

	if is_instance_valid(pending_swap_card):
		var saved_pending_global = Vector2.ZERO
		if pending_swap_card is CanvasItem:
			saved_pending_global = pending_swap_card.global_position
		var prev_pending_parent = pending_swap_card.get_parent()
		if prev_pending_parent and prev_pending_parent != self:
			prev_pending_parent.remove_child(pending_swap_card)
		call_deferred("_deferred_reparent_apply", pending_swap_card, saved_pending_global)

	# Compute card target positions using each hand's global rect center and the card size
	var card_size = chosen_card.card_size if chosen_card and chosen_card.card_size != Vector2.ZERO else (card_manager.card_size if card_manager else Vector2(100,150))
	var player_target = owner_hand.get_global_rect().get_center() - card_size * 0.5
	var opponent_target = other_hand.get_global_rect().get_center() - card_size * 0.5

	# 1) Move the chosen opponent card into the player's hand area and then add it
	chosen_card.move(player_target, 0)
	LOG.log_args(["EffectsManager: moving chosen_card to owner_hand target=", player_target])
	# Wait for the move animation to finish
	await get_tree().create_timer(0.5).timeout
	# Add to owner's hand logic (this will snap it precisely into the hand)
	owner_hand.add_card(chosen_card)

	# Lock the card the player just received using lock_card() to properly set metadata
	if chosen_card and is_instance_valid(chosen_card):
		var parent_path = "null"
		var cp = chosen_card.get_parent()
		if cp:
			parent_path = cp.get_path()
		LOG.log_args(["EffectsManager: locking chosen_card=", chosen_card.name, " parent=", parent_path])
		lock_card(chosen_card)  # Use lock_card() instead of chosen_card.lock() to set is_locked meta

	# 2) Now move the pending swap card into the opponent's hand area and then add it
	pending_swap_card.move(opponent_target, 0)
	await get_tree().create_timer(0.5).timeout
	LOG.log_args(["EffectsManager: moving pending_swap_card to other_hand target=", opponent_target])
	other_hand.add_card(pending_swap_card)
	
	LOG.log_args(["EffectsManager: swap complete - owner_hand=", owner_hand.get_path(), " other_hand=", other_hand.get_path()])
	var result = {
		"success": true,
		"effect_type": "SWAP",
		"swapped_card": chosen_card,
		"played_card": pending_swap_card
	}
	
	emit_signal("card_effect_executed", pending_swap_card, "SWAP", result)
	
	# Clean up state
	is_waiting_for_swap_selection = false
	# Clear the pending swap card reference (we lock only when effect concludes)
	pending_swap_card = null
	pending_swap_player = ""
	pending_swap_owner_hand = null

	# If this swap was triggered as part of an enqueued request, publish the result
	if _current_request_id != "":
		_completed_results[_current_request_id] = result

	return result

## Locks a card so it cannot be played or interacted with.
func lock_card(card: Card) -> void:
	if not card or not is_instance_valid(card) or locked_cards.has(card):
		return

	print("[LOCK] Locking card: ", card.name)
	
	# Record locked state and mark card as non-interactive
	locked_cards.append(card)
	
	# Mark card as locked (stores state for checking later)
	card.set_meta("is_locked", true)
	
	# Prevent all interactions except hover
	card.can_be_interacted_with = false

	# Do NOT forcibly change the card's transform here; locking should be
	# logical + visual only. Previously we attempted to force held cards back to
	# IDLE and call return_to_original(), but that caused unexpected position
	# jumps. If a caller needs to interrupt an active drag, do it explicitly
	# before calling lock_card().

	print("[LOCK] Card locked: ", card.name, " | can_interact=", card.can_be_interacted_with, " | is_locked=", card.has_meta("is_locked"))
	
	# Show visual lock overlay
	if card.has_method("lock"):
		# We pass debug_visual=false here; callers can pass true if they want the red debug rect
		card.lock(0.7, false)

## Unlocks a card so it can be played or interacted with.
func unlock_card(card: Card) -> void:
	if card and locked_cards.has(card):
		print("[UNLOCK] Unlocking card: ", card.name)
		
		locked_cards.erase(card)
		
		# Remove locked state
		if card.has_meta("is_locked"):
			card.remove_meta("is_locked")
		
		# Restore interaction
		card.can_be_interacted_with = true
		
		print("[UNLOCK] Card unlocked: ", card.name, " | can_interact=", card.can_be_interacted_with, " | is_locked=", card.has_meta("is_locked"))
		
		# Remove visual lock overlay
		if card.has_meta("lock_badge"):
			var overlay = card.get_meta("lock_badge")
			if is_instance_valid(overlay) and overlay.is_inside_tree():
				# Fade out overlay, then free
				var tween = create_tween()
				tween.tween_property(overlay, "modulate:a", 0.0, 0.12)
				tween.tween_callback(Callable(overlay, "queue_free"))
			card.remove_meta("lock_badge")


# Developer helper: remove all lock badges and clear internal locked list (call from debugger)
func clear_all_lock_badges() -> void:
	for c in locked_cards.duplicate():
		if c and c.is_inside_tree():
			if c.has_meta("lock_badge"):
				var badge = c.get_meta("lock_badge")
				if is_instance_valid(badge) and badge.is_inside_tree():
					badge.queue_free()
				c.remove_meta("lock_badge")

			# Also remove overlays placed under the front/back TextureRect parents
			var fp = c.get_node_or_null("FrontFace/TextureRect")
			var bp = c.get_node_or_null("BackFace/TextureRect")
			if fp and fp.has_node("LockOverlay"):
				var fo = fp.get_node("LockOverlay")
				if is_instance_valid(fo) and fo.is_inside_tree():
					fo.queue_free()
			if bp and bp.has_node("LockOverlay"):
				var bo = bp.get_node("LockOverlay")
				if is_instance_valid(bo) and bo.is_inside_tree():
					bo.queue_free()

	# Also scan scene for any rogue badges using a DFS
	var root = get_tree().get_root()
	var stack = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.name == "LockBadge":
			if node.is_inside_tree():
				node.queue_free()
			continue
		for child in node.get_children():
			stack.push_back(child)

	locked_cards.clear()


## Adds a blue outline highlight to a card during selection phase
func _add_selection_highlight(card: Card) -> void:
	if not card or card.has_node("SelectionHighlight"):
		return
	
	# Create a Panel for the outline effect using StyleBoxFlat
	var highlight = Panel.new()
	highlight.name = "SelectionHighlight"
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Use card_size for proper dimensions
	var card_rect_size = card.card_size if card.card_size != Vector2.ZERO else card.size
	
	# Position it to cover the entire card with a border
	highlight.position = Vector2(-6, -6)
	highlight.size = card_rect_size + Vector2(12, 12)
	
	# Create a StyleBoxFlat for the outline
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent background
	style.border_color = Color(0.49, 0.87, 1.0, 1.0)  # #7DE9FF blue outline
	style.border_width_left = 6
	style.border_width_right = 6
	style.border_width_top = 6
	style.border_width_bottom = 6
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	
	highlight.add_theme_stylebox_override("panel", style)
	
	# Start hidden and invisible
	highlight.visible = false
	highlight.modulate.a = 0.0
	
	card.add_child(highlight)
	card.set_meta("selection_highlight", highlight)
	
	LOG.log_args(["EffectsManager: added selection highlight to card=", card.name, " size=", highlight.size])


## Removes the blue outline highlight from a card
func _remove_selection_highlight(card: Card) -> void:
	if not card or not card.has_meta("selection_highlight"):
		return
	
	var highlight = card.get_meta("selection_highlight")
	if is_instance_valid(highlight) and highlight.is_inside_tree():
		# Animate out
		var tween = create_tween()
		tween.tween_property(highlight, "modulate:a", 0.0, 0.2)
		tween.tween_callback(highlight.queue_free)
	
	card.remove_meta("selection_highlight")
	LOG.log_args(["EffectsManager: removed selection highlight from card=", card.name])


# Deferred helper to reparent a node and restore its global position (to avoid animation jumping)
func _deferred_reparent_apply(node: Node, saved_global_pos: Vector2) -> void:
	if not is_instance_valid(node):
		return
	# If node already has a parent, we assume it's correctly parented
	if node.get_parent() != self:
		add_child(node)
	# Restore global position for CanvasItem nodes so animations start from the visible spot
	if node is CanvasItem:
		var ci = node as CanvasItem
		ci.global_position = saved_global_pos
		# local position left untouched; global_position restored so visual stays stable
	
	LOG.log_args(["EffectsManager: deferred reparent applied for", node.name])

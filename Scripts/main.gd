extends Node

const LOG = preload("res://Scripts/logger.gd")
const CF_SETTINGS = preload("res://Scripts/CardFramework/Core/card_framework_settings.gd")

# Ensure EffectsManager is loaded as a singleton (autoload) in Project Settings,
# or load it manually if not using autoload:
# const EffectsManager = preload("res://path/to/EffectsManager.gd")

@onready var cm: CardManager = $SubViewportContainer/SubViewport/GameLayer/CardManager
@onready var deck: Pile = cm.get_node("Deck") if cm else null
@onready var player_hand: Hand = cm.get_node("PlayerHand") if cm else null
@onready var opponent_hand: Hand = cm.get_node("OpponentHand") if cm else null
@export var desired_deck_size: int = 0 # 0 = create one of each available card
@export var debug_deck_counter: bool = false

var deck_counter: Control
var deck_counter_label: Label
var _align_deck_attempts: int = 0
var _align_playarea_attempts: int = 0

func _ready():
	# Ensure CardManager is ready.
	if cm == null:
		push_error("CardManager not found at expected path")
		return

	# Disable interaction with Deck and Discard piles (everything is automatic)
	if deck:
		deck.allow_card_movement = false
		deck.enable_drop_zone = false
	var discard = cm.get_node_or_null("DiscardPile")
	if discard and discard is Pile:
		discard.allow_card_movement = false
		discard.enable_drop_zone = false
	
	# Get deck counter references
	# Prefer finding deck counter relative to GameLayer (parent of CardManager)
	var game_layer = null
	if cm and cm.get_parent():
		game_layer = cm.get_parent()
	if game_layer:
		deck_counter = game_layer.get_node_or_null("DeckCounter")
	else:
		# fallback to absolute path
		deck_counter = get_node_or_null("SubViewportContainer/SubViewport/GameLayer/DeckCounter")
	
	if deck_counter:
		deck_counter_label = deck_counter.get_node_or_null("Box/Count")

	# Defer card creation to ensure all nodes and resources are fully initialized.
	call_deferred("_create_test_cards")
	
	# Initialize EffectsManager with game components
	call_deferred("_initialize_effects_manager")

	# Align deck center to SubViewport center (deferred so sizes settle)
	call_deferred("align_deck_to_viewport")

	# Align PlayArea center to SubViewport center as well (safe deferred helper)
	call_deferred("align_playarea_to_viewport")

	# Connect deck signals to update counter when deck changes
	# We'll try to connect after creation as well, but connect here in case deck is already present
	if deck:
		if not deck.is_connected("count_changed", Callable(self, "_update_deck_counter")):
			deck.connect("count_changed", Callable(self, "_update_deck_counter"))
	# If a Discard pile exists, optionally connect to it for mirror updates
	if cm:
		var discard_pile = cm.get_node_or_null("Discard")
		if discard_pile and not discard_pile.is_connected("count_changed", Callable(self, "_update_deck_counter")):
			discard_pile.connect("count_changed", Callable(self, "_update_deck_counter"))

func _create_test_cards():
	if deck == null:
		# Try to find the Deck container under CardManager
		deck = cm.get_node("Deck") if cm else null
		if deck == null:
			push_error("Deck container not found")
			return

	# Diagnostics: print factory and deck state (muted unless LOG enabled)
	LOG.log_args(["DEBUG: card_factory =", cm.card_factory])
	if cm.card_factory:
		LOG.log_args(["DEBUG: factory.card_info_dir =", cm.card_factory.card_info_dir])
		LOG.log_args(["DEBUG: factory.card_asset_dir =", cm.card_factory.card_asset_dir])
		if cm.card_factory.preloaded_cards != null:
			var keys = cm.card_factory.preloaded_cards.keys()
			LOG.log_args(["DEBUG: preloaded card keys count=", keys.size(), " sample=", keys.slice(0,10)])

	# Define the guaranteed deck composition
	# 2 → 10 copies (5 draw, 5 swap)
	# 4 → 10 copies (5 draw, 5 swap)
	# 6 → 10 copies (5 draw, 5 swap)
	# 8 → 9 copies (5 draw, 4 swap)
	# 10 → 9 copies (4 draw, 5 swap)
	var deck_composition: Dictionary = {
		"Draw_2": 5,
		"Swap_2": 5,
		"Draw_4": 5,
		"Swap_4": 5,
		"Draw_6": 5,
		"Swap_6": 5,
		"Draw_8": 5,
		"Swap_8": 4,
		"Draw_10": 4,
		"Swap_10": 5
	}
	
	# Create cards based on the guaranteed composition
	var card_list: Array = []
	for card_name in deck_composition.keys():
		var count = deck_composition[card_name]
		for i in range(count):
			card_list.append(card_name)
	
	# Shuffle the deck
	card_list.shuffle()
	
	# Create the cards in the shuffled order
	for card_name in card_list:
		var card = null
		if cm.card_factory:
			card = cm.card_factory.create_card(card_name, deck)
		if card:
			if deck and deck.card_face_up == false:
				card.show_front = false
			if debug_deck_counter:
				LOG.log_args(["created:", card_name, " node_path=", card.get_path(), " parent=", card.get_parent()])
				LOG.log_args(["  -> show_front=", card.show_front, " icon_texture=", card.icon_texture, " card_size=", card.card_size])
			# Diagnostic: print deck counts after each create (only when debug enabled)
			if debug_deck_counter and deck:
				LOG.log_args(["DEBUG: deck.get_card_count() after create=", deck.get_card_count()])
				var cards_node = deck.get_node_or_null("Cards")
				if cards_node:
					LOG.log_args(["DEBUG: deck.Cards child count=", cards_node.get_child_count()])
		else:
			push_warning("create_card returned null for: " + card_name)
			if cm.card_factory and debug_deck_counter:
				LOG.log_args(["  factory.card_info_dir=", cm.card_factory.card_info_dir])
				LOG.log_args(["  Looking for file:", cm.card_factory.card_info_dir + "/" + card_name + ".json"]) 

	# Diagnostic: dump final deck stats after creating all cards
	if deck:
		LOG.log_args(["DEBUG: final deck.get_card_count()=", deck.get_card_count()])
		LOG.log_args(["DEBUG: deck child count=", deck.get_child_count()])
		var cards_node = deck.get_node_or_null("Cards")
		if cards_node:
			LOG.log_args(["DEBUG: deck.Cards child count=", cards_node.get_child_count()])

	# Synchronize internal state (in case factory added nodes but didn't update internal list)
	_sync_deck_internal_state()

	# Update deck counter after all cards are created
	_update_deck_counter()
	call_deferred("_deal_cards")

func _deal_cards():
	if not deck or not player_hand or not opponent_hand:
		push_error("Deck or hands not found for dealing.")
		return

	# Deal 4 cards to player
	var player_cards = deck.get_top_cards(4)
	for card in player_cards:
		if deck.remove_card(card):
			player_hand.add_card(card)

	# Deal 4 cards to opponent
	var opponent_cards = deck.get_top_cards(4)
	for card in opponent_cards:
		if deck.remove_card(card):
			opponent_hand.add_card(card)
	
	# Update deck counter after dealing
	_update_deck_counter()

func _update_deck_counter(arg: Variant = null):
	# Accept either a Card (old calls) or an int from the count_changed signal.
	var override_count: int = -1
	if typeof(arg) == TYPE_INT:
		override_count = int(arg)
		LOG.log_args(["DEBUG: _update_deck_counter() received override count=", override_count])

	# Ensure we have the UI label reference; try to reacquire if missing
	if not deck_counter_label:
		# Try previous methods first
		if deck_counter == null:
			if cm and cm.get_parent():
				deck_counter = cm.get_parent().get_node_or_null("DeckCounter")
			else:
				deck_counter = get_node_or_null("SubViewportContainer/SubViewport/GameLayer/DeckCounter")
			if deck_counter:
				deck_counter_label = deck_counter.get_node_or_null("Box/Count")
		# If still missing, search the whole scene tree for a node named DeckCounter
		if not deck_counter_label:
			var root = get_tree().get_root()
			# Try current_scene first (safer), then root
			var search_root = get_tree().current_scene if get_tree().current_scene else root
			var found = _find_node_recursive(search_root, "DeckCounter")
			if not found and root != search_root:
				found = _find_node_recursive(root, "DeckCounter")
			if found:
				LOG.log_args(["DEBUG: _update_deck_counter() - found DeckCounter via recursive search ->", found])
				deck_counter = found
				# Prefer direct child path first, then any Label named 'Count'
				deck_counter_label = deck_counter.get_node_or_null("Box/Count")
				if not deck_counter_label:
					var found_label = _find_node_recursive(deck_counter, "Count")
					if found_label and found_label is Label:
						deck_counter_label = found_label
						LOG.log_args(["DEBUG: _update_deck_counter() - found Count label via recursive search ->", found_label])
			# Final fallback: search globally for a Label named 'Count' (risky)
			if not deck_counter_label:
				var found_any = _find_node_recursive(search_root, "Count")
				if not found_any and root != search_root:
					found_any = _find_node_recursive(root, "Count")
				if found_any and found_any is Label:
					deck_counter_label = found_any
					LOG.log_args(["DEBUG: _update_deck_counter() - fallback found a Label named 'Count' ->", found_any])

	# Update the deck counter label with current card count
	if deck:
		var count: int
		if override_count >= 0:
			count = override_count
		else:
			count = deck.get_card_count()
		var cards_node = deck.get_node_or_null("Cards")
		if cards_node:
			var visual_count = cards_node.get_child_count()
			if debug_deck_counter:
				LOG.log_args(["DEBUG: _update_deck_counter() - deck.get_card_count()=", count, ", deck.Cards child count=", visual_count])
			# If internal count is zero but visual children exist, use visual count
			if count == 0 and visual_count > 0:
				count = visual_count
		else:
			if debug_deck_counter:
				LOG.log_args(["DEBUG: _update_deck_counter() - deck has no 'Cards' child, get_card_count()=", count])

		if deck_counter_label:
			# concise print only when debug enabled
			if debug_deck_counter:
				LOG.log_args(["DEBUG: _update_deck_counter() - updating label from ", deck_counter_label.text, " to ", str(count)])
			# Always update the label silently
			deck_counter_label.text = str(count)
			# Ensure counter UI appears above card visuals (cards use VISUAL_PILE_Z_INDEX)
			if deck_counter and deck_counter is Control:
				# Use a safe offset above pile z to avoid occlusion by cards
				deck_counter.z_index = CF_SETTINGS.VISUAL_PILE_Z_INDEX + 500
				# Also raise the label specifically
				deck_counter_label.z_index = deck_counter.z_index + 1
		else:
			if debug_deck_counter:
				LOG.log("DEBUG: _update_deck_counter() - deck_counter_label is still null after all attempts")
	else:
		if debug_deck_counter:
			LOG.log("DEBUG: _update_deck_counter() - deck is null")

func _input(event):
	# Press R to clear and recreate test cards while running
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if cm:
			# Clear all containers managed by the CardManager
			for container_id in cm.card_container_dict:
				var container = cm.card_container_dict[container_id]
				if container and container.has_method("clear_cards"):
					container.clear_cards()
			
			# Re-create the deck and deal cards
			_create_test_cards()
	
	# Test EffectsManager functionality
	if event is InputEventKey and event.pressed:
		if not has_node("/root/EffectsManager"):
			LOG.log("EffectsManager not available")
			return
			
		match event.keycode:
			KEY_D:
				await _test_draw_effect()
			KEY_S:
				await _test_swap_effect()
			KEY_T:
				get_node("/root/EffectsManager").next_turn()
				LOG.log_args(["=== Turn switched to:", get_node("/root/EffectsManager").current_turn, "==="]) 
			KEY_G:
				_print_game_state()
			KEY_ESCAPE:
				# Cancel swap selection if active
				var effects_manager = get_node("/root/EffectsManager")
				if effects_manager.is_waiting_for_swap_selection:
					effects_manager.cancel_swap_selection()

func _sync_deck_internal_state() -> void:
	# Ensure deck's internal held list matches actual Nodes under 'Cards'
	if not deck:
		return
	var changed = false
	var cards_node = deck.get_node_or_null("Cards")
	if not cards_node:
		return
	var children = cards_node.get_children()
	for child in children:
		if child is Card:
			# If deck doesn't believe it holds this card, add it
			if not deck.has_card(child):
				LOG.log_args(["DEBUG: _sync_deck_internal_state() - adding missing child to deck._held_cards:", child.name])
				# Use add_card to ensure container bookkeeping runs
				deck.add_card(child)
				changed = true
	# Also remove any held_cards entries that no longer have nodes
	# (defensive, but ensures consistency)
	var to_remove = []
	for c in deck._held_cards:
		if not (c in children):
			to_remove.append(c)
		for r in to_remove:
			LOG.log_args(["DEBUG: _sync_deck_internal_state() - removing stale held card:", r])
			deck._held_cards.erase(r)
		changed = true
	# After sync, update visuals
	deck.update_card_ui()
	if changed:
		deck.emit_signal("count_changed", deck.get_card_count())

# Initialize EffectsManager with game component references
func _initialize_effects_manager():
	# Check if EffectsManager autoload is available
	if not has_node("/root/EffectsManager"):
		push_error("EffectsManager autoload not found! Check Project Settings -> Autoload")
		return
		
	if cm and deck and player_hand and opponent_hand:
		var discard = cm.get_node_or_null("DiscardPile")
		var p_area = cm.get_node_or_null("PlayArea")
		var em = get_node("/root/EffectsManager")
		# Call initialize with the five core references. Some loaded autoloads may expect
		# the older 5-argument signature; set play_area separately to be compatible.
		em.initialize(cm, player_hand, opponent_hand, deck, discard)
		if p_area and em.has_method("set_play_area"):
			em.set_play_area(p_area)
		LOG.log("EffectsManager initialized with game components")
	else:
		push_warning("Could not initialize EffectsManager - missing game components")


## Align the Deck's center to the SubViewport's center.
## This uses the SubViewport size (1920x1080) rather than the editor viewport
## and sets the Deck's global_position so its center matches the viewport center.
func align_deck_to_viewport() -> void:
	var subv = get_node_or_null("SubViewportContainer/SubViewport")
	if not subv:
		return

	var deck_node = get_node_or_null("SubViewportContainer/SubViewport/GameLayer/CardManager/Deck")
	if not deck_node:
		# try cached onready var
		deck_node = deck if deck else null
	if not deck_node:
		return

	# Desired center in SubViewport pixels
	var V = subv.size * 0.5

	# Deck size in global pixels (accounts for scale/transform)
	var S = deck_node.get_global_rect().size

	# If deck size isn't ready yet, wait for frames (but limit retries)
	_align_deck_attempts += 1
	while S == Vector2.ZERO and _align_deck_attempts <= 10:
		# wait a frame for layout to settle
		await get_tree().process_frame
		S = deck_node.get_global_rect().size
		_align_deck_attempts += 1
	if S == Vector2.ZERO:
		LOG.log("align_deck_to_viewport: giving up after retries (deck size zero)")
		return

	var top_left = V - S * 0.5

	# Convert top_left (in SubViewport coordinates) into the deck parent's local coordinates
	var parent = deck_node.get_parent()
	var parent_global_pos = Vector2.ZERO
	if parent == null:
		parent_global_pos = Vector2.ZERO
	elif parent is Control:
		parent_global_pos = parent.get_global_rect().position
	elif parent.has_method("get_global_position"):
		parent_global_pos = parent.get_global_position()
	else:
		parent_global_pos = Vector2.ZERO

	var local_top_left = top_left - parent_global_pos

	# Apply position safely depending on node type
	if deck_node is Control:
		# Use rect_position for Controls
		deck_node.rect_position = local_top_left
		LOG.log_args(["align_deck_to_viewport: set rect_position=", local_top_left])
	elif deck_node.has_method("set_global_position"):
		# Fallback for CanvasItem/Node2D
		deck_node.set_global_position(top_left)
		LOG.log_args(["align_deck_to_viewport: set global_position=", top_left])
	else:
		# Last-resort: try setting 'position' if available
		if deck_node.has_method("set_position"):
			deck_node.set_position(local_top_left)
			LOG.log_args(["align_deck_to_viewport: set position=", local_top_left])
		else:
			LOG.log("align_deck_to_viewport: could not set deck position - unsupported node type")

	LOG.log_args(["align_deck_to_viewport: V=", V, " S=", S, " top_left=", top_left, " parent_global=", parent_global_pos, " local_top_left=", local_top_left])


func align_playarea_to_viewport() -> void:
	# Find the PlayArea node under the CardManager / GameLayer path
	var subv = get_node_or_null("SubViewportContainer/SubViewport")
	if not subv:
		return

	# PlayArea is expected to be under the GameLayer alongside CardManager
	var play_area = get_node_or_null("SubViewportContainer/SubViewport/GameLayer/PlayArea")
	if not play_area:
		# Try to find relative to CardManager if scene differs
		if has_node("SubViewportContainer/SubViewport/GameLayer/CardManager"):
			var cm_node = get_node("SubViewportContainer/SubViewport/GameLayer/CardManager")
			play_area = cm_node.get_node_or_null("PlayArea")
	if not play_area:
		# Last resort: try to find any node named 'PlayArea' in the current scene
		var root_search = get_tree().current_scene if get_tree().current_scene else get_tree().get_root()
		play_area = _find_node_recursive(root_search, "PlayArea")
	if not play_area:
		return

	# Desired center in SubViewport pixels
	var V = subv.size * 0.5

	# PlayArea size (global rect)
	var S = play_area.get_global_rect().size

	_align_playarea_attempts += 1
	while S == Vector2.ZERO and _align_playarea_attempts <= 15:
		await get_tree().process_frame
		S = play_area.get_global_rect().size
		_align_playarea_attempts += 1
	if S == Vector2.ZERO:
		LOG.log("align_playarea_to_viewport: giving up after retries (play_area size zero)")
		return

	var top_left = V - S * 0.5

	# Convert to parent-local coordinates similar to deck helper
	var parent = play_area.get_parent()
	var parent_global_pos = Vector2.ZERO
	if parent == null:
		parent_global_pos = Vector2.ZERO
	elif parent is Control:
		# Wait until parent has a non-zero global rect to avoid Godot control assertions
		var parent_size = parent.get_global_rect().size
		var attempts = 0
		while parent_size == Vector2.ZERO and attempts < 10:
			await get_tree().process_frame
			parent_size = parent.get_global_rect().size
			attempts += 1
		parent_global_pos = parent.get_global_rect().position
	elif parent.has_method("get_global_position"):
		parent_global_pos = parent.get_global_position()
	else:
		parent_global_pos = Vector2.ZERO

	var local_top_left = top_left - parent_global_pos

	# Apply safely depending on node type
	if play_area is Control:
		# Only set rect_position when parent has non-zero size (guard above)
		play_area.rect_position = local_top_left
		LOG.log_args(["align_playarea_to_viewport: set rect_position=", local_top_left])
	elif play_area.has_method("set_global_position"):
		play_area.set_global_position(top_left)
		LOG.log_args(["align_playarea_to_viewport: set global_position=", top_left])
	elif play_area.has_method("set_position"):
		play_area.set_position(local_top_left)
		LOG.log_args(["align_playarea_to_viewport: set position=", local_top_left])
	else:
		LOG.log("align_playarea_to_viewport: could not set play_area position - unsupported node type")

	LOG.log_args(["align_playarea_to_viewport: V=", V, " S=", S, " top_left=", top_left, " parent_global=", parent_global_pos, " local_top_left=", local_top_left])

# Test draw effect with a random draw card from player's hand
func _test_draw_effect():
	if not has_node("/root/EffectsManager"):
		LOG.log("EffectsManager not available")
		return
		
	if not player_hand or player_hand.get_card_count() == 0:
		LOG.log("No cards in player hand to test draw effect")
		return
	
	# Find a draw card in player's hand
	var draw_card = null
	for card in player_hand._held_cards:
		if card.card_name.begins_with("Draw_"):
			draw_card = card
			break
	
	if not draw_card:
		LOG.log("No draw cards found in player hand")
		return
	
	LOG.log("=== Testing Draw Effect ===")
	LOG.log_args(["Using card:", draw_card.card_name])
	LOG.log_args(["Before - Player hand:", player_hand.get_card_count(), "cards"])
	LOG.log_args(["Before - Deck:", deck.get_card_count(), "cards"])
	
	# Remove card from hand (simulate playing it)
	player_hand.remove_card(draw_card)
	
	var result = await get_node("/root/EffectsManager").execute_card_effect(draw_card, "player")
	
	if result.success:
		LOG.log("✓ Draw effect successful!")
		LOG.log_args(["Discarded:", result.discarded_card.card_name])
		LOG.log_args(["Drew:", result.drawn_card.card_name, "(locked)"])
		LOG.log_args(["After - Player hand:", player_hand.get_card_count(), "cards"])
		LOG.log_args(["After - Deck:", deck.get_card_count(), "cards"])
	else:
		LOG.log_args(["✗ Draw effect failed:", result.message])

# Test swap effect with a random swap card from player's hand
func _test_swap_effect():
	if not has_node("/root/EffectsManager"):
		LOG.log("EffectsManager not available")
		return
		
	if not player_hand or player_hand.get_card_count() == 0:
		LOG.log("No cards in player hand to test swap effect")
		return
	
	if not opponent_hand or opponent_hand.get_card_count() == 0:
		LOG.log("No cards in opponent hand to swap with")
		return
	
	# Find a swap card in player's hand
	var swap_card = null
	for card in player_hand._held_cards:
		if card.card_name.begins_with("Swap_"):
			swap_card = card
			break
	
	if not swap_card:
		LOG.log("No swap cards found in player hand")
		return
	
	LOG.log("=== Testing Swap Effect ===")
	LOG.log_args(["Using card:", swap_card.card_name])
	LOG.log_args(["Before - Player hand:", player_hand.get_card_count(), "cards"])
	LOG.log_args(["Before - Opponent hand:", opponent_hand.get_card_count(), "cards"])
	
	# Remove card from hand (simulate playing it)
	player_hand.remove_card(swap_card)
	
	# Start the swap selection process
	var effects_manager = get_node("/root/EffectsManager")
	var result = await effects_manager.execute_card_effect(swap_card, "player")
	
	if result.get("waiting_for_selection", false):
		LOG.log("✓ Swap selection mode activated!")
		LOG.log(result.message)
		LOG.log("Now click on one of the opponent's cards to complete the swap")
	else:
		LOG.log_args(["✗ Swap setup failed:", result.get("message", "Unknown error")])

# Print current game state
func _print_game_state():
	if not has_node("/root/EffectsManager"):
		LOG.log("EffectsManager not available")
		return
		
	var effects_manager = get_node("/root/EffectsManager")
	var state = effects_manager.get_game_state()
	LOG.log("=== Game State ===")
	LOG.log_args(["Current turn:", state.current_turn])
	LOG.log_args(["Game phase:", state.game_phase])
	LOG.log_args(["Player hand:", state.player_hand_count, "cards"])
	LOG.log_args(["Opponent hand:", state.opponent_hand_count, "cards"])
	LOG.log_args(["Deck:", state.deck_count, "cards"])
	LOG.log_args(["Discard:", state.discard_count, "cards"])
	LOG.log_args(["Locked cards:", effects_manager.locked_cards.size()])

# Recursive search helper to find a node by name in the scene tree
func _find_node_recursive(start: Node, target_name: String) -> Node:
	if start == null:
		return null
	if start.name == target_name:
		return start
	for child in start.get_children():
		if child is Node:
			var found = _find_node_recursive(child, target_name)
			if found:
				return found
	return null

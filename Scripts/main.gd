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
@onready var player_score_panel: Control = $SubViewportContainer/SubViewport/UILayer/PlayerScoreActionPanel
@onready var opponent_score_panel: Control = %OpponentScoreActionPanel2
@onready var round_counter: Control = $SubViewportContainer/SubViewport/UILayer/RoundCounter
@onready var game_state_screen: Control = $SubViewportContainer/SubViewport/UILayer/GameStateLayer/GameStateScreen
@onready var round_total_screen: Control = $SubViewportContainer/SubViewport/UILayer/GameStateLayer/RoundTotalScreen
@onready var game_over_screen: Control = $SubViewportContainer/SubViewport/UILayer/GameStateLayer/GameOverScreen
@onready var pass_message: Control = $SubViewportContainer/SubViewport/UILayer/PassMessage
@onready var options_button: TextureButton = $SubViewportContainer/SubViewport/UILayer/OptionsButton
@onready var settings_panel: Control = $SubViewportContainer/SubViewport/UILayer/OptionsButton/"Settings Panel"
@onready var surrender_button: Button = $SubViewportContainer/SubViewport/UILayer/OptionsButton/"Settings Panel"/SurrenderButton
@onready var tooltip_button: TextureButton = $SubViewportContainer/SubViewport/UILayer/OptionsButton/ToolTipButton2
@onready var how_to_play_panel: Control = $SubViewportContainer/SubViewport/UILayer/OptionsButton/ToolTipButton2/HowToPlay
@onready var viewport_container: SubViewportContainer = $SubViewportContainer

# RoundManager
var round_manager: Node

# Track original shader material for VFX toggle
var original_shader_material: ShaderMaterial = null

@export var desired_deck_size: int = 0 # 0 = create one of each available card
@export var debug_deck_counter: bool = false

var deck_counter: Control
var deck_counter_label: Label
var _align_deck_attempts: int = 0
var _align_playarea_attempts: int = 0
var game_surrendered: bool = false
var skip_auto_start: bool = false  # Flag to prevent auto-starting game when recreating deck

## --- Debug / Development helpers (removed) ---
## The detailed debug helper function and noisy diagnostics were
## removed during cleanup. Enable the `logger.gd` utility for
## targeted debugging instead of inline prints.

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	# Initialize score panels
	if player_score_panel:
		player_score_panel.set_is_player_panel(true)
	if opponent_score_panel:
		opponent_score_panel.set_is_player_panel(false)

	# Initialize RoundManager
	var RoundManagerScript = preload("res://Scripts/round_manager.gd")
	round_manager = RoundManagerScript.new()
	add_child(round_manager)
	
	# Pass all references to RoundManager (done here so @onready vars are available)
	var discard_pile_ref = cm.get_node_or_null("DiscardPile") if cm else null
	var play_area_ref = cm.get_node_or_null("PlayArea") if cm else null
	round_manager.initialize(
		self,
		round_counter,
		game_state_screen,
		round_total_screen,
		game_over_screen,
		player_score_panel,
		opponent_score_panel,
		cm,
		deck,
		player_hand,
		opponent_hand,
		discard_pile_ref,
		play_area_ref
	)

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
	
	# Connect options and surrender buttons
	if options_button:
		options_button.process_mode = Node.PROCESS_MODE_ALWAYS
		options_button.pressed.connect(_on_options_pressed)
		print("DEBUG: Options button set to PROCESS_MODE_ALWAYS")
	
	if surrender_button:
		surrender_button.pressed.connect(_on_surrender_pressed)
	
	# Connect tooltip button for how to play
	if tooltip_button:
		tooltip_button.process_mode = Node.PROCESS_MODE_ALWAYS
		tooltip_button.pressed.connect(_on_tooltip_pressed)
		tooltip_button.visible = false  # Hidden until settings panel opens
		print("DEBUG: Tooltip button set to PROCESS_MODE_ALWAYS and initially hidden")
	
	# Ensure settings panel and how to play are hidden initially
	if settings_panel:
		settings_panel.visible = false
	
	if how_to_play_panel:
		how_to_play_panel.visible = false
	
	# Store original shader material and connect to VFX settings
	if viewport_container:
		original_shader_material = viewport_container.material
		var settings_mgr = get_node_or_null("/root/SettingsManager")
		if settings_mgr and settings_mgr.has_signal("visual_effects_changed"):
			settings_mgr.visual_effects_changed.connect(_on_visual_effects_changed)
			# Apply current setting immediately
			_on_visual_effects_changed(settings_mgr.visual_effects_enabled)


func _create_test_cards():
	if deck == null:
		# Try to find the Deck container under CardManager
		deck = cm.get_node("Deck") if cm else null
		if deck == null:
			push_error("Deck container not found")
			return

	# Create deck using configured composition. Detailed diagnostics
	# previously emitted here have been removed for a cleaner log.

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
			# Card created (normal flow). Per-card diagnostics removed.
		else:
			push_warning("create_card returned null for: " + card_name)
			if cm.card_factory and debug_deck_counter:
				LOG.log_args(["  factory.card_info_dir=", cm.card_factory.card_info_dir])
				LOG.log_args(["  Looking for file:", cm.card_factory.card_info_dir + "/" + card_name + ".json"]) 

	# Final deck created. Use logger.gd to inspect counts if required.

	# Synchronize internal state (in case factory added nodes but didn't update internal list)
	_sync_deck_internal_state()

	# Update deck counter after all cards are created
	_update_deck_counter()

	# Play deck load sound
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_deck_load()
	
	# Start the round manager now that the deck is ready
	# ONLY if we're not manually managing the start (e.g., from Play Again)
	if round_manager and not skip_auto_start:
		call_deferred("_start_round_manager")


func _start_round_manager():
	if round_manager and round_manager.has_method("start_game"):
		round_manager.start_game()

func _deal_cards():
	# This function is deprecated - RoundManager now handles dealing
	# Keeping it for backward compatibility but it won't be called
	return

func _update_deck_counter(arg: Variant = null):
	# Accept either a Card (old calls) or an int from the count_changed signal.
	var override_count: int = -1
	if typeof(arg) == TYPE_INT:
		override_count = int(arg)
		# LOG.log_args(["DEBUG: _update_deck_counter() received override count=", override_count])

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
			# if debug_deck_counter:
			#	LOG.log("DEBUG: _update_deck_counter() - deck_counter_label is still null after all attempts")
			pass
	else:
		# if debug_deck_counter:
		#	LOG.log("DEBUG: _update_deck_counter() - deck is null")
		pass

func _input(event):
	# Only handle input while in the active scene tree
	if not is_inside_tree():
		# Debug: if you'd like to trace, uncomment the next line
		# LOG.log_args(["_input called while not inside tree on node:", self.get_path()])
		return
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


func _unhandled_input(event):
	# Only handle unhandled input while in the active scene tree
	if not is_inside_tree():
		# Debug: uncomment to trace which node is receiving input while detached
		# LOG.log_args(["_unhandled_input called while not inside tree on node:", self.get_path()])
		return

	# Close panels when clicking outside of them
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check how to play panel first (it takes priority when visible)
		if how_to_play_panel and how_to_play_panel.visible:
			if not how_to_play_panel.get_global_rect().has_point(event.global_position):
				_close_how_to_play_panel()
		# Check settings panel
		elif settings_panel and settings_panel.visible:
			if not settings_panel.get_global_rect().has_point(event.global_position):
				_close_options_panel()

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


## Shows the pass message with a bounce animation
func show_pass_message(player_name: String = "Player") -> void:
	# show_pass_message called
	
	if not pass_message:
		# pass_message node missing
		return
	
		# pass_message node found, starting animation
	
	# Set the text if there's a label
	var label = pass_message.get_node_or_null("Label")
	if label and label is Label:
		label.text = player_name + " Passes"
	
	# Start hidden and scaled down
	pass_message.visible = true
	pass_message.modulate.a = 0.0
	pass_message.scale = Vector2(0.5, 0.5)
	
	# Create bounce animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)  # Back easing for bounce effect
	
	# Bounce in
	tween.set_parallel(true)
	tween.tween_property(pass_message, "modulate:a", 1.0, 0.3)
	tween.tween_property(pass_message, "scale", Vector2(1.2, 1.2), 0.3)
	
	# Hold at full size briefly
	tween.set_parallel(false)
	tween.tween_interval(0.4)
	
	# Scale back to normal
	tween.tween_property(pass_message, "scale", Vector2(1.0, 1.0), 0.15)
	
	# Hold again
	tween.tween_interval(0.3)
	
	# Bounce out
	tween.set_parallel(true)
	tween.tween_property(pass_message, "modulate:a", 0.0, 0.25)
	tween.tween_property(pass_message, "scale", Vector2(0.8, 0.8), 0.25)
	
	# Hide when done
	tween.set_parallel(false)
	tween.tween_callback(func(): pass_message.visible = false)
	
	# Wait for the tween to finish
	# Waiting for pass message tween to finish...
	await tween.finished
	# Pass message animation complete!


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


# Recursively set process mode for a node and all its children
# This allows UI elements to work even when the game tree is paused
func _set_panel_process_mode_recursive(node: Node, mode: Node.ProcessMode) -> void:
	if node == null:
		return
	node.process_mode = mode
	for child in node.get_children():
		_set_panel_process_mode_recursive(child, mode)


## Called when options button is pressed
func _on_options_pressed() -> void:
	print("DEBUG: Options button pressed!")
	if settings_panel:
		print("DEBUG: Settings panel found, making visible")
		settings_panel.visible = true
		# Set panel to process even when paused
		_set_panel_process_mode_recursive(settings_panel, Node.PROCESS_MODE_ALWAYS)
		print("DEBUG: Panel process mode set to ALWAYS")
		
		# Show tooltip button when settings panel opens
		if tooltip_button:
			tooltip_button.visible = true
			print("DEBUG: Tooltip button made visible")
		
		# Cancel any active card dragging
		_cancel_all_card_dragging()
		
		# Disable gameplay elements
		_set_gameplay_enabled(false)
		
		# Pause the game tree to freeze gameplay
		get_tree().paused = true
		print("DEBUG: Game paused")
		LOG.tracking("Options panel opened - game paused")


## Called when surrender button is pressed
func _on_surrender_pressed() -> void:
	print("DEBUG: Surrender button pressed!")
	LOG.log("Player surrendered!")
	game_surrendered = true
	# Close panel but DON'T unpause - game should stay paused until game over
	if settings_panel:
		settings_panel.visible = false
	
	# Tell round manager to end the game with surrender flag
	if round_manager and round_manager.has_method("surrender_game"):
		print("DEBUG: Calling round_manager.surrender_game()")
		round_manager.surrender_game()
	else:
		# Fallback: just end the game
		print("DEBUG: Fallback - calling round_manager.end_game()")
		if round_manager and round_manager.has_method("end_game"):
			round_manager.end_game()


## Called when tooltip/help button is pressed
func _on_tooltip_pressed() -> void:
	print("DEBUG: Tooltip button pressed!")
	if how_to_play_panel:
		print("DEBUG: How to play panel found, making visible")
		how_to_play_panel.visible = true
		# Set panel to process even when paused
		_set_panel_process_mode_recursive(how_to_play_panel, Node.PROCESS_MODE_ALWAYS)
		print("DEBUG: How to play panel process mode set to ALWAYS")
		
		# Hide settings panel when showing how to play
		if settings_panel:
			settings_panel.visible = false
		
		# Cancel any active card dragging
		_cancel_all_card_dragging()
		
		# Disable gameplay elements
		_set_gameplay_enabled(false)
		
		# Pause the game tree to freeze gameplay
		get_tree().paused = true
		print("DEBUG: Game paused")
		LOG.tracking("How to play panel opened - game paused")


## Close the how to play panel and return to settings
func _close_how_to_play_panel() -> void:
	print("DEBUG: Closing how to play panel")
	if how_to_play_panel:
		how_to_play_panel.visible = false
	
	# Show settings panel again
	if settings_panel:
		settings_panel.visible = true
		print("DEBUG: Settings panel shown again")
	
	LOG.tracking("How to play panel closed - returned to settings")


## Close the options panel and unpause the game
func _close_options_panel() -> void:
	print("DEBUG: Closing options panel")
	if settings_panel:
		settings_panel.visible = false
		
		# Hide tooltip button when settings panel closes
		if tooltip_button:
			tooltip_button.visible = false
			print("DEBUG: Tooltip button hidden")
		
		# Also hide how to play panel if it's visible
		if how_to_play_panel:
			how_to_play_panel.visible = false
		
		# Only unpause if game hasn't ended
		if not game_surrendered:
			# Re-enable gameplay elements
			_set_gameplay_enabled(true)
			get_tree().paused = false
			print("DEBUG: Panel hidden, game unpaused")
			LOG.tracking("Options panel closed - game unpaused")
		else:
			print("DEBUG: Game surrendered - keeping paused")


## Enable or disable gameplay elements (cards, play area, score panels)
func _set_gameplay_enabled(enabled: bool) -> void:
	print("DEBUG: Setting gameplay enabled = ", enabled)
	
	# Disable/enable play area
	var play_area = cm.get_node_or_null("PlayArea") if cm else null
	if play_area:
		play_area.process_mode = Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT
	
	# Disable/enable player hand
	if player_hand:
		player_hand.process_mode = Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT
	
	# Disable/enable opponent hand  
	if opponent_hand:
		opponent_hand.process_mode = Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT
	
	# Disable/enable score panels
	if player_score_panel:
		player_score_panel.process_mode = Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT
	if opponent_score_panel:
		opponent_score_panel.process_mode = Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT


## Cancel any active card dragging across all hands and containers
func _cancel_all_card_dragging() -> void:
	print("DEBUG: Canceling all card dragging")
	
	# Get all cards in the scene
	var all_cards = []
	
	if cm:
		# Get cards from all containers
		for container_id in cm.card_container_dict:
			var container = cm.card_container_dict[container_id]
			if container and container.has_method("get_all_cards"):
				all_cards.append_array(container.get_all_cards())
	
	# Force all cards back to IDLE state
	for card in all_cards:
		if card and card.has_method("_change_state"):
			# DraggableState.IDLE = 0
			card._change_state(0)  # Force to IDLE state
			print("DEBUG: Reset card ", card.name, " to IDLE")


## Handle visual effects toggle (accessibility)
func _on_visual_effects_changed(enabled: bool) -> void:
	if not viewport_container:
		return
	
	if enabled:
		# Restore original shader material
		viewport_container.material = original_shader_material
	else:
		# Disable all post-processing effects for accessibility
		viewport_container.material = null
	
	print("DEBUG: VFX post-processing ", "enabled" if enabled else "disabled")

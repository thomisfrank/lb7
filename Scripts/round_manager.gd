extends Node
## RoundManager
## Manages the complete game flow: rounds, turns, scoring, and game state

const LOG = preload("res://Scripts/logger.gd")

# UI References
var round_counter: Control
var game_state_screen: Control
var round_total_screen: Control
var game_over_screen: Control
var player_score_panel: Control
var opponent_score_panel: Control

# Main node reference
var main_node: Node

# Game References
var card_manager: Node
var deck: Node
var player_hand: Node
var opponent_hand: Node
var discard_pile: Node
var play_area: Node

# AI Opponent
var ai_opponent: AIOpponent

# Game State
enum TurnState { PLAYER_TURN, OPPONENT_TURN, ROUND_END, GAME_END }
var current_turn_state: TurnState
var current_round: int = 1
var player_goes_first: bool = true  # Alternates each round
var is_restarting: bool = false  # Flag to prevent actions during restart

# Turn tracking within current round
var player_turn_completed: bool = false
var opponent_turn_completed: bool = false

# Score Tracking
var player_game_score: int = 0
var opponent_game_score: int = 0
var best_player_round_score: int = 999  # Sentinel: no best round yet (valid scores: 8-40, lower is better)
var best_player_round_cards: Array = []

# Stats Tracking
var total_swaps_used: int = 0
var total_draws_used: int = 0
var total_passes_taken: int = 0

# Configuration
@export var cards_per_hand: int = 4
@export var actions_per_turn: int = 2
@export var game_state_pause_duration: float = 1.0


func _ready() -> void:
	# Wait for scene tree to be ready
	await get_tree().process_frame
	# References are set by Main via initialize() method
	# Don't try to setup here as @onready vars might not be ready


## Helper to create a pausable timer that respects get_tree().paused
func _create_pausable_timer(duration: float) -> SceneTreeTimer:
	# process_always = false makes the timer pausable
	var timer = get_tree().create_timer(duration, false, false, false)
	return timer


## Initialize the RoundManager with references from Main
func initialize(
	p_main_node: Node,
	p_round_counter: Control,
	p_game_state_screen: Control,
	p_round_total_screen: Control,
	p_game_over_screen: Control,
	p_player_score_panel: Control,
	p_opponent_score_panel: Control,
	p_card_manager: Node,
	p_deck: Node,
	p_player_hand: Node,
	p_opponent_hand: Node,
	p_discard_pile: Node,
	p_play_area: Node
) -> void:
	# Set main node reference
	main_node = p_main_node
	
	# Set UI references
	round_counter = p_round_counter
	game_state_screen = p_game_state_screen
	round_total_screen = p_round_total_screen
	game_over_screen = p_game_over_screen
	player_score_panel = p_player_score_panel
	opponent_score_panel = p_opponent_score_panel
	
	# Set game references
	card_manager = p_card_manager
	deck = p_deck
	player_hand = p_player_hand
	opponent_hand = p_opponent_hand
	discard_pile = p_discard_pile
	play_area = p_play_area
	
	# Initialize AI opponent
	_initialize_ai()
	
	# Now connect signals
	_connect_signals()


## Sets up all node references (DEPRECATED - use initialize() instead)
func _setup_references() -> void:
	var main = get_tree().root.get_node("Main")
	if not main:
		push_error("RoundManager: Cannot find Main node")
		return
	
	# Get UI references
	round_counter = main.round_counter
	game_state_screen = main.game_state_screen
	round_total_screen = main.round_total_screen
	game_over_screen = main.game_over_screen
	player_score_panel = main.player_score_panel
	opponent_score_panel = main.opponent_score_panel
	
	# Get game references
	card_manager = main.cm
	deck = main.deck
	player_hand = main.player_hand
	opponent_hand = main.opponent_hand
	discard_pile = card_manager.get_node_or_null("DiscardPile") if card_manager else null
	
	# Initialize AI opponent
	_initialize_ai()


## Initialize the AI opponent
func _initialize_ai() -> void:
	if not ai_opponent:
		ai_opponent = AIOpponent.new()
		add_child(ai_opponent)
	
	# Set AI references
	ai_opponent.opponent_hand = opponent_hand
	ai_opponent.player_hand = player_hand
	ai_opponent.deck = deck
	ai_opponent.discard_pile = discard_pile
	
	# Set AI difficulty (can be changed via settings)
	ai_opponent.set_difficulty(AIOpponent.Difficulty.MEDIUM)


## Connects necessary signals
func _connect_signals() -> void:
	# Connect pass button signals
	if player_score_panel and player_score_panel.has_node("BG/PassButton/AspectRatioContainer/TextureButton"):
		var pass_button = player_score_panel.get_node("BG/PassButton/AspectRatioContainer/TextureButton")
		if not pass_button.is_connected("pressed", Callable(self, "_on_player_pass_pressed")):
			pass_button.connect("pressed", Callable(self, "_on_player_pass_pressed"))
	
	# Connect to EffectsManager signal for card plays
	if has_node("/root/EffectsManager"):
		var effects_manager = get_node("/root/EffectsManager")
		if not effects_manager.is_connected("card_effect_executed", Callable(self, "_on_card_effect_executed")):
			effects_manager.connect("card_effect_executed", Callable(self, "_on_card_effect_executed"))
	
	# Connect Play Again button - try multiple possible paths
	if game_over_screen:
		var play_again_btn = null
		var button_paths = [
			"transparentBG/Buttons/PlayAgainButton/AspectRatioContainer/TextureButton",
			"transparentBG/Buttons/PlayAgainButton/TextureButton",
			"transparentBG/Buttons/PlayAgainButton/Button",
			"transparentBG/Buttons/PlayAgainButton"
		]
		
		for path in button_paths:
			if game_over_screen.has_node(path):
				play_again_btn = game_over_screen.get_node(path)
				break
		
		if play_again_btn and play_again_btn.has_signal("pressed"):
			if not play_again_btn.is_connected("pressed", Callable(self, "_on_play_again_pressed")):
				play_again_btn.connect("pressed", Callable(self, "_on_play_again_pressed"))
			else:
				pass
	
	# Connect Quit button
	if game_over_screen and game_over_screen.has_node("transparentBG/Buttons/QuitButton"):
		var quit_btn = game_over_screen.get_node("transparentBG/Buttons/QuitButton")
		if quit_btn and quit_btn.has_signal("pressed"):
			if not quit_btn.is_connected("pressed", Callable(self, "_on_quit_button_pressed")):
				quit_btn.connect("pressed", Callable(self, "_on_quit_button_pressed"))


## Starts the game
func start_game() -> void:
	print("DEBUG: start_game() called, paused=", get_tree().paused)
	
	# Reset all scores and stats
	current_round = 1
	player_game_score = 0
	opponent_game_score = 0
	best_player_round_score = 999  # Reset to sentinel value (no best round yet)
	# Free any old card copies
	for card in best_player_round_cards:
		if card and is_instance_valid(card):
			card.queue_free()
	best_player_round_cards.clear()
	total_swaps_used = 0
	total_draws_used = 0
	total_passes_taken = 0
	
	# Update score panels
	if player_score_panel:
		player_score_panel.reset_score()
	if opponent_score_panel:
		opponent_score_panel.reset_score()
	
	# Player always goes first in round 1
	player_goes_first = true
	
	# Deal initial hands
	await _deal_hands()
	
	# Start first round
	start_round()


## Deals cards to both players
func _deal_hands() -> void:
	print("DEBUG: _deal_hands() called, paused=", get_tree().paused)
	if not deck or not player_hand or not opponent_hand:
		push_error("RoundManager: Missing deck or hand references")
		return
	
	# Deal to player
	var player_cards = deck.get_top_cards(cards_per_hand)
	for card in player_cards:
		if deck.remove_card(card):
			player_hand.add_card(card)
	
	# Deal to opponent
	var opponent_cards = deck.get_top_cards(cards_per_hand)
	for card in opponent_cards:
		if deck.remove_card(card):
			opponent_hand.add_card(card)
	
	# Play hand fill sound
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").play_hand_fill(-2.0)
	
	# Small delay to let cards settle - use regular timer (not pausable) for game initialization
	print("DEBUG: Waiting for cards to settle, paused=", get_tree().paused)
	await get_tree().create_timer(0.5, true).timeout  # process_always=true for initialization
	print("DEBUG: Cards settled")


## Starts a new round
func start_round() -> void:
	print("DEBUG: start_round() called, paused=", get_tree().paused)
	# Round start
	
	# Reset turn completion flags for new round
	player_turn_completed = false
	opponent_turn_completed = false
	
	# Update round counter
	if round_counter:
		round_counter.set_round(current_round)
	
	# Reset actions for both players
	if player_score_panel:
		player_score_panel.reset_actions()
		player_score_panel.hide_pass_button()
	if opponent_score_panel:
		opponent_score_panel.reset_actions()
	
	# Show "Round #" message
	if game_state_screen:
		game_state_screen.show_round(current_round)
		# Play new round sound
		if has_node("/root/SoundManager"):
			get_node("/root/SoundManager").play_new_round(-2.0)
		# Wait for the full animation to complete
		# fade_in (0.2) + display (1.0) + fade_out (0.2) = 1.4 seconds
		await get_tree().create_timer(1.4).timeout
	else:
		await get_tree().create_timer(game_state_pause_duration).timeout
	
	# Start the first turn based on who goes first
	if player_goes_first:
		start_player_turn()
	else:
		start_opponent_turn()


## Starts the player's turn
func start_player_turn() -> void:
	# Don't start a turn if game has ended or is restarting
	if current_turn_state == TurnState.GAME_END or is_restarting:
		print("=== ROUND_MANAGER: Blocked PLAYER_TURN - game ended or restarting ===")
		return
	
	current_turn_state = TurnState.PLAYER_TURN
	print("=== ROUND_MANAGER: State changed to PLAYER_TURN ===")
	# Play player turn sound
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_player_turn()
	if play_area:
		play_area.set_current_player("player")
	
	# Show "Your Turn" message
	if game_state_screen:
		game_state_screen.show_your_turn()
		# Wait for the full animation to complete
		await get_tree().create_timer(1.4).timeout
	else:
		await get_tree().create_timer(game_state_pause_duration).timeout
	
	# Enable player controls
	if player_score_panel:
		player_score_panel.reset_actions()
		player_score_panel.show_pass_button()
	
	# Enable card interaction for player
	if player_hand:
		player_hand.cards_interactable = true
	
	# Unlock any locked cards from previous effects
	var effects_manager = get_node_or_null("/root/Main/EffectsManager")
	if effects_manager:
		# First unlock any permanently locked cards
		if effects_manager.has_method("unlock_card") and "locked_cards" in effects_manager:
			var locked_cards = effects_manager.locked_cards.duplicate()
			for card in locked_cards:
				if card and is_instance_valid(card):
					effects_manager.unlock_card(card)
	
	# Force unlock all cards in player hand (regardless of how they were locked)
	if player_hand and "_held_cards" in player_hand:
			# Force unlocking all player hand cards
		for card in player_hand._held_cards:
			if card and is_instance_valid(card):
				# Remove any lock meta
				if card.has_meta("is_locked"):
					card.remove_meta("is_locked")
					# Remove any selection meta that might interfere
					if card.has_meta("selection_enabled"):
						card.remove_meta("selection_enabled")
					# Force enable interaction
					card.can_be_interacted_with = true
		
			# Force hand UI update to apply the changes
			if player_hand.has_method("update_card_ui"):
				player_hand.update_card_ui()

	
	# Optionally test sound manager if available
	if has_node("/root/SoundManager"):
		var _sound_manager = get_node("/root/SoundManager")
		if Engine.is_editor_hint():
			# In editor/debug builds we could exercise the sound manager; no-op in release
			pass


## Starts the opponent's turn
func start_opponent_turn() -> void:
	# Don't start a turn if game has ended or is restarting
	if current_turn_state == TurnState.GAME_END or is_restarting:
		print("=== ROUND_MANAGER: Blocked OPPONENT_TURN - game ended or restarting ===")
		return
	
	# Opponent's turn starting
	current_turn_state = TurnState.OPPONENT_TURN
	print("=== ROUND_MANAGER: State changed to OPPONENT_TURN ===")
	# Play opponent turn sound
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_opponent_turn()
	if play_area:
		play_area.set_current_player("opponent")
	
	# Show "Opponent's Turn" message
	if game_state_screen:
		game_state_screen.show_opponent_turn()
		# Wait for the full animation to complete
		await get_tree().create_timer(1.4).timeout
	else:
		await get_tree().create_timer(game_state_pause_duration).timeout
	
	# Reset opponent actions
	if opponent_score_panel:
		opponent_score_panel.reset_actions()
	
	# Disable player controls
	if player_score_panel:
		player_score_panel.hide_pass_button()
	if player_hand:
		player_hand.cards_interactable = false
	
	# AI opponent logic
	await _simulate_opponent_turn()
	
	# After opponent's turn, decide what happens next
	_end_opponent_turn()


## Simulates opponent's turn with AI logic
func _simulate_opponent_turn() -> void:
	if not ai_opponent:
		# Fallback placeholder when AI is missing
		# Fallback to simple simulation
		for i in range(actions_per_turn):
			await _create_pausable_timer(1.0).timeout
			if opponent_score_panel:
				opponent_score_panel.use_action()
		return
	
	# Get EffectsManager for playing cards
	var effects_manager = get_node_or_null("/root/EffectsManager")
	if not effects_manager:
		effects_manager = get_node_or_null("/root/Main/EffectsManager")
	
	# AI makes up to 2 actions per turn
	for i in range(actions_per_turn):
		print("DEBUG: AI waiting (thinking time)... paused=", get_tree().paused)
		await _create_pausable_timer(1.2).timeout  # Thinking time
		print("DEBUG: AI thinking done, paused=", get_tree().paused)
		
		# Check if game ended or is restarting during the wait
		if current_turn_state == TurnState.GAME_END or is_restarting:
			print("DEBUG: AI loop aborted - game ended or restarting")
			return
		
		# AI action loop
		
		var actions_remaining = actions_per_turn - i
		var decision = ai_opponent.decide_action(actions_remaining)
		
		if decision.type == "pass":
			# Clear ALL remaining actions when passing
			if opponent_score_panel and opponent_score_panel.has_method("clear_actions"):
				opponent_score_panel.clear_actions()
			
			# Play opponent pass sound
			var sm = get_node_or_null("/root/SoundManager")
			if sm:
				sm.play_pass()
			
			if main_node and main_node.has_method("show_pass_message"):
				await main_node.show_pass_message("Opponent")
			else:
				await _create_pausable_timer(1.0).timeout  # Brief pause anyway
			break
		
		if decision.type == "play_card" and decision.has("card"):
			var card = decision.card
			# ALWAYS remove card from hand first before any effect
			opponent_hand.remove_card(card)
			
			# Execute card effect based on type
			if card.card_name.begins_with("Draw_"):
				await _ai_execute_draw(card, effects_manager)
			elif card.card_name.begins_with("Swap_"):
				await _ai_execute_swap(card, effects_manager)
			else:
				# Regular card: Just discard it
				discard_pile.add_card(card)
			
			# after effect
			
			# Use an action
			if opponent_score_panel:
				opponent_score_panel.use_action()


## AI executes a DRAW effect
func _ai_execute_draw(card: Card, effects_manager: Node) -> void:
	# AI executing draw effect
	
	if effects_manager:
		# Use the EffectsManager to properly execute the effect
		var result = await effects_manager.execute_card_effect(card, "opponent")
		# Check for failed draw from empty deck, which ends the game
		if not result.get("success", false):
			var message = result.get("message", "")
			if message == "No cards left in deck" or message == "Failed to draw card from deck":
				LOG.log("Game over: AI tried to draw from an empty deck.")
				end_game()
				return
	else:
		# Fallback: manual draw without effects manager
		# Manual draw fallback
		discard_pile.add_card(card)
		await get_tree().create_timer(0.3).timeout
		
		if deck.get_card_count() < 1:
			LOG.log("Game over: AI tried to draw from an empty deck (fallback).")
			end_game()
			return
		
		var drawn_cards = deck.get_top_cards(1)
		if not drawn_cards.is_empty():
			var drawn_card = drawn_cards[0]
			deck.remove_card(drawn_card)
			opponent_hand.add_card(drawn_card)
			# drew card


## AI executes a SWAP effect
func _ai_execute_swap(card: Card, effects_manager: Node) -> void:
	# AI executing swap effect
	
	# Show AI "thinking" by highlighting player cards
	await _ai_simulate_thinking_on_player_cards()
	
	# AI chooses which player card to swap with
	var target_card = ai_opponent.choose_swap_target()
	
	if not target_card or not is_instance_valid(target_card):
		# No swap target found
		if discard_pile:
			discard_pile.add_card(card)
		return
	
	# Highlight the chosen card briefly before swapping
	await _ai_highlight_chosen_card(target_card)
	
	if effects_manager:
		# Phase 1: Start the swap (this sets up pending_swap_card)
		var result1 = await effects_manager.execute_card_effect(card, "opponent")
		
		if result1.get("waiting_for_selection", false):
			# Phase 2: Complete the swap with the chosen card
			var _result2 = await effects_manager.execute_card_effect(card, "opponent", target_card)
			# result2.success handling is internal to effects manager
	else:
		# Fallback: manual swap
		# Manual swap fallback
		if player_hand and player_hand.has_card(target_card):
			player_hand.remove_card(target_card)
			opponent_hand.add_card(target_card)
		if discard_pile:
			discard_pile.add_card(card)
		await get_tree().create_timer(0.5).timeout


## Simulate AI "thinking" by highlighting player's cards sequentially
func _ai_simulate_thinking_on_player_cards() -> void:
	if not player_hand or not "_held_cards" in player_hand:
		return
	
	var player_cards = player_hand._held_cards.duplicate()
	if player_cards.is_empty():
		return
	
	# Highlight each card briefly (simulating consideration)
	var card_index = 0
	for card in player_cards:
		if not card or not is_instance_valid(card):
			continue
		
		# Play selecting swap sound with varying pitch for each card
		var sm = get_node_or_null("/root/SoundManager")
		if sm:
			# Vary pitch slightly for each card (0.9 to 1.1 range)
			var pitch = 0.9 + (card_index * 0.05)
			sm.play_selecting_swap(pitch)
		
		card_index += 1
		
		# Create a highlight effect
		var highlight = ColorRect.new()
		highlight.color = Color(1.0, 1.0, 0.3, 0.0)  # Yellow, start transparent
		highlight.size = card.card_size
		highlight.position = Vector2.ZERO
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.z_index = 100
		card.add_child(highlight)
		
		# Animate highlight in
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(highlight, "color:a", 0.3, 0.15)
		tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.15)
		
		await get_tree().create_timer(0.2).timeout
		
		# Animate highlight out
		var tween_out = create_tween()
		tween_out.set_parallel(true)
		tween_out.tween_property(highlight, "color:a", 0.0, 0.15)
		tween_out.tween_property(card, "scale", Vector2.ONE, 0.15)
		
		await get_tree().create_timer(0.15).timeout
		
		# Remove highlight
		if is_instance_valid(highlight):
			highlight.queue_free()


## Highlight the AI's chosen card before swapping
func _ai_highlight_chosen_card(card: Card) -> void:
	if not card or not is_instance_valid(card):
		return
	
	# Create a more prominent highlight for the chosen card
	var highlight = ColorRect.new()
	highlight.color = Color(1.0, 0.3, 0.3, 0.0)  # Red/orange, start transparent
	highlight.size = card.card_size
	highlight.position = Vector2.ZERO
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.z_index = 100
	card.add_child(highlight)
	
	# Pulse the chosen card
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(highlight, "color:a", 0.5, 0.2)
	tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.2)
	
	await get_tree().create_timer(0.3).timeout
	
	# Pulse back
	var tween_out = create_tween()
	tween_out.set_parallel(true)
	tween_out.tween_property(highlight, "color:a", 0.0, 0.2)
	tween_out.tween_property(card, "scale", Vector2.ONE, 0.2)
	
	await get_tree().create_timer(0.25).timeout
	
	# Remove highlight
	if is_instance_valid(highlight):
		highlight.queue_free()



## Called when player uses an action (draw or swap)
func on_player_action_used(action_type: String) -> void:
	if current_turn_state != TurnState.PLAYER_TURN:
		return
	
	# Update stats
	if action_type == "draw":
		total_draws_used += 1
	elif action_type == "swap":
		total_swaps_used += 1
	
	# Use an action
	if player_score_panel:
		player_score_panel.use_action()
		
		# Check if player has no more actions
		if not player_score_panel.has_actions():
			_end_player_turn()


## Called when player presses pass button
func _on_player_pass_pressed() -> void:
	if current_turn_state != TurnState.PLAYER_TURN:
		return
	# Player passed
	total_passes_taken += 1

	# Play pass sound
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		sm.play_pass()
	
	# Clear any remaining actions when player passes
	if player_score_panel:
		player_score_panel.clear_actions()
	
	# Show pass message animation if available, otherwise brief pause
	if main_node and main_node.has_method("show_pass_message"):
		await main_node.show_pass_message("Player")
	else:
		await get_tree().create_timer(1.0).timeout  # Brief pause anyway
	
	_end_player_turn()


## Called when a card effect is executed (from EffectsManager signal)
func _on_card_effect_executed(_card: Card, effect_type: String, result: Dictionary) -> void:
	if current_turn_state != TurnState.PLAYER_TURN:
		return

	# Check for failed draw from empty deck, which ends the game
	if effect_type == "DRAW" and not result.get("success", false):
		var message = result.get("message", "")
		if message == "No cards left in deck" or message == "Failed to draw card from deck":
			LOG.log("Game over: Player tried to draw from an empty deck.")
			end_game()
			return

	# Determine action type (stats are already incremented below)
	var action_type = ""
	if effect_type == "DRAW":
		action_type = "draw"
	elif effect_type == "SWAP":
		action_type = "swap"
	
	if action_type != "":
		on_player_action_used(action_type)

## Called when play again button is pressed
func _on_play_again_pressed() -> void:
	print("DEBUG: Play Again pressed - FULL GAME RESET")
	
	# Set restart flag to block any ongoing game logic
	is_restarting = true
	
	# Hide game over screen
	if game_over_screen:
		game_over_screen.hide_screen()
	
	# ========== CLEAR ALL GAME DATA ==========
	# Reset turn state
	current_turn_state = TurnState.PLAYER_TURN
	player_turn_completed = false
	opponent_turn_completed = false
	
	# Reset round/score tracking
	current_round = 0
	player_game_score = 0
	opponent_game_score = 0
	best_player_round_score = 999  # Reset to sentinel value (no best round yet)
	# Free any old card copies
	for card in best_player_round_cards:
		if card and is_instance_valid(card):
			card.queue_free()
	best_player_round_cards.clear()
	total_swaps_used = 0
	total_draws_used = 0
	total_passes_taken = 0
	player_goes_first = true
	
	# Clear effects manager state
	var effects_manager = get_node_or_null("/root/EffectsManager")
	if not effects_manager:
		effects_manager = get_node_or_null("/root/Main/EffectsManager")
	if effects_manager:
		effects_manager.locked_cards.clear()
		effects_manager._cards_locked_during_effect.clear()
		effects_manager._effect_queue.clear()
		effects_manager._processing_effects = false
		effects_manager._completed_results.clear()
		effects_manager.is_waiting_for_swap_selection = false
		effects_manager.pending_swap_card = null
		effects_manager.pending_swap_player = ""
		effects_manager.pending_swap_owner_hand = null
	
	# Reset main node state
	if main_node:
		main_node.game_surrendered = false
		main_node._align_deck_attempts = 0
		main_node._align_playarea_attempts = 0
		
		# Cancel any stuck card dragging
		if main_node.has_method("_cancel_all_card_dragging"):
			main_node._cancel_all_card_dragging()
			print("DEBUG: Canceled card dragging")
		
		# Unpause if still paused
		if get_tree().paused:
			get_tree().paused = false
			print("DEBUG: Game unpaused")
		
		# Re-enable gameplay elements
		if main_node.has_method("_set_gameplay_enabled"):
			main_node._set_gameplay_enabled(true)
			print("DEBUG: Gameplay re-enabled")
	
	# Clear all card containers
	if player_hand:
		player_hand.clear_cards()
	if opponent_hand:
		opponent_hand.clear_cards()
	if discard_pile:
		discard_pile.clear_cards()
	
	# Clear the deck before recreating
	if deck:
		deck.clear_cards()
	
	# Recreate the deck WITHOUT auto-starting the game
	if main_node and main_node.has_method("_create_test_cards"):
		main_node.skip_auto_start = true  # Prevent auto-start
		main_node._create_test_cards()
		main_node.skip_auto_start = false  # Reset flag
	
	# Wait for deck to be created
	await get_tree().create_timer(0.5).timeout
	
	# Clear restart flag
	is_restarting = false
	
	print("DEBUG: Starting new game with deck count:", deck.get_card_count() if deck else 0)
	# Starting new game
	start_game()


## Called when quit button is pressed
func _on_quit_button_pressed() -> void:
	print("DEBUG: Quit button pressed - returning to start screen")
	
	# Unpause the game if paused
	if get_tree().paused:
		get_tree().paused = false
	
	# Change to start screen
	get_tree().change_scene_to_file("res://Scenes/GameStartScreen.tscn")


## Ends the player's turn
func _end_player_turn() -> void:
	# Ending player turn
	player_turn_completed = true
	
	# Disable player controls
	if player_score_panel:
		player_score_panel.hide_pass_button()
	if player_hand:
		player_hand.cards_interactable = false
	
	# Check if both players have completed their turns
	if opponent_turn_completed:
	# Both players finished, ending round
		# Wait for any card effects to finish animating
		await get_tree().create_timer(1.5).timeout
		end_round()
		return
	
	# Small delay before opponent's turn
	await get_tree().create_timer(0.5).timeout
	
	# Start opponent's turn
	start_opponent_turn()


## Ends the opponent's turn and determines next phase
func _end_opponent_turn() -> void:
	# Ending opponent turn
	opponent_turn_completed = true
	
	# Check if both players have completed their turns
	if player_turn_completed:
	# Both players finished, ending round
		# Wait for any card effects to finish animating
		await get_tree().create_timer(1.5).timeout
		end_round()
		return
	
	# If player hasn't had their turn yet, start it
	# Opponent finished, starting player turn
	start_player_turn()


## Ends the current round and shows results
func end_round() -> void:
	# Don't end round if game has already ended or is restarting
	if current_turn_state == TurnState.GAME_END or is_restarting:
		print("=== ROUND_MANAGER: Blocked ROUND_END - game ended or restarting ===")
		return
	
	# Round end
	current_turn_state = TurnState.ROUND_END
	print("=== ROUND_MANAGER: State changed to ROUND_END ===")
	
	# Calculate hand values
	var player_cards = _get_hand_cards(player_hand)
	var opponent_cards = _get_hand_cards(opponent_hand)
	
	# Show round total screen
	if round_total_screen:
		round_total_screen.show_round_results(
			player_cards,
			opponent_cards,
			player_game_score,
			opponent_game_score
		)

		# Wait for animation to complete (estimate based on card count and delays)
		var animation_duration = (player_cards.size() * round_total_screen.card_reveal_delay) + \
			round_total_screen.win_condition_delay + \
			round_total_screen.score_count_duration + \
			round_total_screen.final_score_delay + 2.0

		await get_tree().create_timer(animation_duration).timeout
	else:
		# round_total_screen missing
		await get_tree().create_timer(2.0).timeout
	
	# Get round results
	var totals = {}
	if round_total_screen:
		totals = round_total_screen.get_round_totals()
	var player_round_total = totals.get("player", 0)
	var opponent_round_total = totals.get("opponent", 0)
	
	print("DEBUG: Round ", current_round, " results - Player:", player_round_total, " Opponent:", opponent_round_total)
	print("DEBUG: Current best_player_round_score:", best_player_round_score)
	print("DEBUG: Player cards count:", player_cards.size())
	
	# Award points to winner (lower score wins the round)
	if player_round_total < opponent_round_total:
		player_game_score += player_round_total
		if player_score_panel:
			player_score_panel.set_score(player_game_score)
		
		# Track best round (lower is better, always save first win or if score is better/lower than previous best)
		if player_round_total < best_player_round_score:
			print("DEBUG: NEW BEST ROUND! Score:", player_round_total, " Saving", player_cards.size(), "cards")
			best_player_round_score = player_round_total
			# Create deep copies of the cards NOW before they get discarded
			best_player_round_cards.clear()
			for card in player_cards:
				if card and is_instance_valid(card):
					var card_copy = card.duplicate()
					best_player_round_cards.append(card_copy)
			print("DEBUG: best_player_round_cards now has", best_player_round_cards.size(), "card copies")
		else:
			print("DEBUG: Not a best round (", player_round_total, " not better than ", best_player_round_score, ")")
	elif opponent_round_total < player_round_total:
		print("DEBUG: Opponent won this round")
		opponent_game_score += opponent_round_total
		if opponent_score_panel:
			opponent_score_panel.set_score(opponent_game_score)
	# Tie = no points awarded
	
	# Hide round total screen
	if round_total_screen:
		round_total_screen.hide_screen()
	
	await get_tree().create_timer(0.5).timeout
	
	# Discard hands
	_discard_hands()
	
	# Check if game should continue
	if _should_game_continue():
		# Deal new hands
		await _deal_hands()
		
		# Alternate starting player
		player_goes_first = not player_goes_first
	# Starting player alternated for next round
		
		# Start next round
		current_round += 1
		start_round()
	else:
		# Game over
		end_game()


## Discards all cards from both hands
func _discard_hands() -> void:
	if not discard_pile:
		return
	
	# Discard player hand
	if player_hand:
		var cards = player_hand._held_cards.duplicate()
		for card in cards:
			if card:
				player_hand.remove_card(card)
				discard_pile.add_card(card)
	
	# Discard opponent hand
	if opponent_hand:
		var cards = opponent_hand._held_cards.duplicate()
		for card in cards:
			if card:
				opponent_hand.remove_card(card)
				discard_pile.add_card(card)


## Checks if the game should continue
func _should_game_continue() -> bool:
	# Game continues if deck has enough cards for both hands
	if deck:
		return deck.get_card_count() >= (cards_per_hand * 2)
	return false


## Ends the game and shows game over screen
func end_game() -> void:
	# Game over
	current_turn_state = TurnState.GAME_END
	print("=== ROUND_MANAGER: State changed to GAME_END ===")
	
	# Determine winner (unless surrendered)
	var player_won = player_game_score > opponent_game_score
	
	# Check if player surrendered
	var surrendered = false
	if main_node and "game_surrendered" in main_node:
		surrendered = main_node.game_surrendered
	
	# Show game over screen
	if game_over_screen:
		print("DEBUG: Showing game over screen")
		print("DEBUG: best_player_round_score:", best_player_round_score)
		print("DEBUG: best_player_round_cards.size():", best_player_round_cards.size())
		print("DEBUG: Passing", best_player_round_cards.size(), "cards to game_over_screen")
		
	# Calling game_over_screen.show_game_over()
		if game_over_screen.has_method("show_game_over_surrender") and surrendered:
			# Use surrender version if available
			game_over_screen.show_game_over_surrender(
				player_game_score,
				opponent_game_score,
				best_player_round_score,
				best_player_round_cards,
				total_swaps_used,
				total_draws_used,
				total_passes_taken
			)
		else:
			# Normal game over
			game_over_screen.show_game_over(
				player_won,
				player_game_score,
				opponent_game_score,
				best_player_round_score,
				best_player_round_cards,
				total_swaps_used,
				total_draws_used,
				total_passes_taken
			)
	else:
		# game_over_screen is null - nothing to show
		pass


## Called when player surrenders - force a loss
func surrender_game() -> void:
	print("=== ROUND_MANAGER: surrender_game() called ===")
	LOG.log("Player has surrendered!")
	# Set flag in main node
	if main_node:
		main_node.game_surrendered = true
	# End the game immediately
	end_game()


## Helper function to get all cards from a hand as an array
func _get_hand_cards(hand: Node) -> Array:
	var cards = []
	if hand and "_held_cards" in hand:
		cards = hand._held_cards.duplicate()
	return cards

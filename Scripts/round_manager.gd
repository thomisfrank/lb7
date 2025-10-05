extends Node
## RoundManager
## Manages the complete game flow: rounds, turns, scoring, and game state

# UI References
var round_counter: Control
var game_state_screen: Control
var round_total_screen: Control
var game_over_screen: Control
var player_score_panel: Control
var opponent_score_panel: Control

# Game References
var card_manager: Node
var deck: Node
var player_hand: Node
var opponent_hand: Node
var discard_pile: Node

# Game State
enum TurnState { PLAYER_TURN, OPPONENT_TURN, ROUND_END, GAME_END }
var current_turn_state: TurnState
var current_round: int = 1
var player_goes_first: bool = true  # Alternates each round

# Turn tracking within current round
var player_turn_completed: bool = false
var opponent_turn_completed: bool = false

# Score Tracking
var player_game_score: int = 0
var opponent_game_score: int = 0
var best_player_round_score: int = 0
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


## Initialize the RoundManager with references from Main
func initialize(
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
	p_discard_pile: Node
) -> void:
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


## Connects necessary signals
func _connect_signals() -> void:
	# Connect pass button signals
	if player_score_panel and player_score_panel.has_node("BG/PassButton/TextureButton"):
		var pass_button = player_score_panel.get_node("BG/PassButton/TextureButton")
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
			"transparentBG/Buttons/PlayAgainButton/TextureButton",
			"transparentBG/Buttons/PlayAgainButton/Button",
			"transparentBG/Buttons/PlayAgainButton"
		]
		
		for path in button_paths:
			if game_over_screen.has_node(path):
				play_again_btn = game_over_screen.get_node(path)
				print("SETUP: Found Play Again button at: ", path)
				break
		
		if play_again_btn and play_again_btn.has_signal("pressed"):
			if not play_again_btn.is_connected("pressed", Callable(self, "_on_play_again_pressed")):
				play_again_btn.connect("pressed", Callable(self, "_on_play_again_pressed"))
				print("SETUP: Connected Play Again button")
		else:
			print("SETUP: Could not find Play Again button or it doesn't have pressed signal")


## Starts the game
func start_game() -> void:
	
	# Reset all scores and stats
	current_round = 1
	player_game_score = 0
	opponent_game_score = 0
	best_player_round_score = 0
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
	
	# Small delay to let cards settle
	await get_tree().create_timer(0.5).timeout


## Starts a new round
func start_round() -> void:
	print("=== ROUND ", current_round, " START ===")
	
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
		# Wait for the full animation to complete
		# fade_in (0.2) + display (1.0) + fade_out (0.2) = 1.4 seconds
		await get_tree().create_timer(1.4).timeout
	else:
		await get_tree().create_timer(game_state_pause_duration).timeout
	
	# Start the first turn based on who goes first
	print("TURN: player_goes_first = ", player_goes_first)
	if player_goes_first:
		print("TURN: Starting PLAYER turn")
		start_player_turn()
	else:
		print("TURN: Starting OPPONENT turn")
		start_opponent_turn()


## Starts the player's turn
func start_player_turn() -> void:
	current_turn_state = TurnState.PLAYER_TURN
	
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
			print("TURN: Found ", locked_cards.size(), " permanently locked cards, unlocking...")
			for card in locked_cards:
				if card and is_instance_valid(card):
					effects_manager.unlock_card(card)
					print("TURN: Unlocked permanently locked card: ", card.name)
	
	# Force unlock all cards in player hand (regardless of how they were locked)
	if player_hand and "_held_cards" in player_hand:
		print("TURN: Force unlocking all player hand cards...")
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
				print("TURN: Force unlocked card: ", card.name, " - can_interact: ", card.can_be_interacted_with)
		
		# Force hand UI update to apply the changes
		if player_hand.has_method("update_card_ui"):
			print("TURN: Updating hand UI after unlocking...")
			player_hand.update_card_ui()
	
	print("TURN: All cards force unlocked for player turn")
	
	# Debug: Check card states
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("debug_card_states"):
		main.debug_card_states()
	
	# Test sound manager
	if has_node("/root/SoundManager"):
		var sound_manager = get_node("/root/SoundManager")
		print("TURN: Testing SoundManager - playing card touch")
		sound_manager.play_card_touch(-1.0)
	else:
		print("TURN: SoundManager not found!")


## Starts the opponent's turn
func start_opponent_turn() -> void:
	print("TURN: Opponent's turn starting")
	current_turn_state = TurnState.OPPONENT_TURN
	
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
	
	# TODO: Implement AI opponent logic
	# For now, just simulate opponent taking actions
	await _simulate_opponent_turn()
	
	# After opponent's turn, decide what happens next
	_end_opponent_turn()


## Simulates opponent's turn (placeholder for AI)
func _simulate_opponent_turn() -> void:
	# Simulate 2 actions with delays
	for i in range(actions_per_turn):
		await get_tree().create_timer(1.0).timeout
		if opponent_score_panel:
			opponent_score_panel.use_action()


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
	
	print("TURN: Player passed")
	total_passes_taken += 1
	
	# Clear any remaining actions when player passes
	if player_score_panel:
		player_score_panel.clear_actions()
	
	_end_player_turn()


## Called when a card effect is executed (from EffectsManager signal)
func _on_card_effect_executed(_card: Card, effect_type: String, _result: Dictionary) -> void:
	if current_turn_state != TurnState.PLAYER_TURN:
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
	print("PLAY_AGAIN: Button pressed, restarting game...")
	
	# Hide game over screen
	if game_over_screen:
		game_over_screen.hide_screen()
	
	# Wait a moment then restart
	await get_tree().create_timer(0.5).timeout
	print("PLAY_AGAIN: Starting new game...")
	start_game()


## Ends the player's turn
func _end_player_turn() -> void:
	print("TURN: Ending player turn")
	player_turn_completed = true
	
	# Disable player controls
	if player_score_panel:
		player_score_panel.hide_pass_button()
	if player_hand:
		player_hand.cards_interactable = false
	
	# Check if both players have completed their turns
	if opponent_turn_completed:
		print("TURN: Both players finished, ending round")
		end_round()
		return
	
	# Small delay before opponent's turn
	await get_tree().create_timer(0.5).timeout
	
	# Start opponent's turn
	start_opponent_turn()


## Ends the opponent's turn and determines next phase
func _end_opponent_turn() -> void:
	print("TURN: Ending opponent turn")
	opponent_turn_completed = true
	
	# Check if both players have completed their turns
	if player_turn_completed:
		print("TURN: Both players finished, ending round")
		end_round()
		return
	
	# If player hasn't had their turn yet, start it
	print("TURN: Opponent finished, starting player turn")
	start_player_turn()


## Ends the current round and shows results
func end_round() -> void:
	print("=== ROUND ", current_round, " END ===")
	current_turn_state = TurnState.ROUND_END
	
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
		print("RoundManager: round_total_screen is null!")
		await get_tree().create_timer(2.0).timeout
	
	# Get round results
	var totals = {}
	if round_total_screen:
		totals = round_total_screen.get_round_totals()
	var player_round_total = totals.get("player", 0)
	var opponent_round_total = totals.get("opponent", 0)
	
	# Award points to winner (lower score wins the round)
	if player_round_total < opponent_round_total:
		player_game_score += player_round_total
		if player_score_panel:
			player_score_panel.set_score(player_game_score)
		
		# Track best round
		if player_round_total > best_player_round_score:
			best_player_round_score = player_round_total
			best_player_round_cards = player_cards.duplicate()
	elif opponent_round_total < player_round_total:
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
		print("TURN: Starting player alternated for round ", current_round + 1, ": player_goes_first = ", player_goes_first)
		
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
	print("RoundManager: Game over")
	current_turn_state = TurnState.GAME_END
	
	# Determine winner
	var player_won = player_game_score > opponent_game_score
	
	# Show game over screen
	if game_over_screen:
		print("RoundManager: Calling game_over_screen.show_game_over()")
		print("RoundManager: player_won=", player_won, " scores=", player_game_score, "-", opponent_game_score)
		print("RoundManager: best_round_score=", best_player_round_score, " best_cards_count=", best_player_round_cards.size())
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
		print("RoundManager: game_over_screen is null!")


## Helper function to get all cards from a hand as an array
func _get_hand_cards(hand: Node) -> Array:
	var cards = []
	if hand and "_held_cards" in hand:
		cards = hand._held_cards.duplicate()
	return cards

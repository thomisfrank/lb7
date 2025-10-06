extends Node

# Sound effects organized by type
var card_touch_sounds: Array[AudioStream] = []
var hand_fill_sounds: Array[AudioStream] = []
var hand_discard_sounds: Array[AudioStream] = []
var single_discard_sounds: Array[AudioStream] = []
var card_played_sound: AudioStream = null
var new_round_sound: AudioStream = null
var count_beep_sound: AudioStream = null
var button_click_sound: AudioStream = null
var button_hover_sound: AudioStream = null
var deck_load_sound: AudioStream = null
var deck_load2_sound: AudioStream = null
var game_win_sound: AudioStream = null
var game_lost_sound: AudioStream = null
var game_tied_sound: AudioStream = null
var pass_sound: AudioStream = null
var opponent_turn_sound: AudioStream = null
var player_turn_sound: AudioStream = null
var reveal_sounds: Array[AudioStream] = []
var round_won_sound: AudioStream = null
var round_lost_sound: AudioStream = null
var round_tied_sound: AudioStream = null
var score_beep_sound: AudioStream = null
var selecting_swap_sound: AudioStream = null

# Global options
@export var ui_sounds_enabled: bool = true  # enable UI button sounds by default
@export var normalize_volumes: bool = true
@export var global_sfx_db: float = -6.0

# Audio player pool for concurrent sounds
var audio_players: Array[AudioStreamPlayer] = []
const MAX_AUDIO_PLAYERS = 10

# RNG for randomizing sound selection
var rng = RandomNumberGenerator.new()

# Track connected buttons to avoid duplicate connections
var connected_buttons: Array = []

# Track reveal sound index for sequential playback
var current_reveal_index: int = 0


func _ready() -> void:
	rng.randomize()
	_load_sounds()
	_create_audio_players()
	
	# Connect to scene changes to wire up new buttons
	get_tree().node_added.connect(_on_node_added)
	
	# Also scan existing nodes in the tree (for the initial scene)
	call_deferred("_scan_existing_nodes")


func _scan_existing_nodes() -> void:
	# Recursively find and connect all existing buttons/sliders in the scene tree
	_scan_node_tree(get_tree().root)


func _scan_node_tree(node: Node) -> void:
	# Check this node
	if node is BaseButton or node is Button or node is TextureButton:
		_connect_button_signals(node)
	elif node is HSlider or node is VSlider:
		_connect_slider_signals(node)
	
	# Check all children recursively
	for child in node.get_children():
		_scan_node_tree(child)


func _on_node_added(node: Node) -> void:
	# When any new node is added to the tree, check if it's a button and connect to it
	if node is BaseButton or node is Button or node is TextureButton:
		_connect_button_signals(node)
	
	# Also check for HSlider (for volume sliders)
	if node is HSlider or node is VSlider:
		_connect_slider_signals(node)


func _connect_button_signals(button: Control) -> void:
	if not ui_sounds_enabled:
		return
	
	# Avoid duplicate connections
	if button in connected_buttons:
		return
	
	connected_buttons.append(button)
	
	# Connect hover sound
	if button.has_signal("mouse_entered") and not button.is_connected("mouse_entered", _on_button_hover):
		button.mouse_entered.connect(_on_button_hover)
	
	# Connect click sound
	if button.has_signal("pressed") and not button.is_connected("pressed", _on_button_click):
		button.pressed.connect(_on_button_click)


func _connect_slider_signals(slider: Control) -> void:
	if not ui_sounds_enabled:
		return
	
	# Avoid duplicate connections
	if slider in connected_buttons:
		return
	
	connected_buttons.append(slider)
	
	# Connect hover sound for sliders
	if slider.has_signal("mouse_entered") and not slider.is_connected("mouse_entered", _on_button_hover):
		slider.mouse_entered.connect(_on_button_hover)
	
	# Connect click/drag sound for sliders (when value changes via user interaction)
	if slider.has_signal("drag_started") and not slider.is_connected("drag_started", _on_button_click):
		slider.drag_started.connect(_on_button_click)


func _on_button_hover() -> void:
	play_button_hover()


func _on_button_click() -> void:
	play_button_click()


func _load_sounds() -> void:
	# Load CardTouch sounds (1-5, updated based on your changes)
	for i in range(1, 6):
		var sound = load("res://Assets/sounds/sfx/CardTouch%d.mp3" % i)
		if sound:
			card_touch_sounds.append(sound)
	
	# Load CardPlayed sound
	card_played_sound = load("res://Assets/sounds/sfx/CardPlayed.mp3")
	
	# Load NewRound sound
	new_round_sound = load("res://Assets/sounds/sfx/NewRound.mp3")
	
	# Load HandFill sounds
	var hand_fill = load("res://Assets/sounds/sfx/HandFill.mp3")
	if hand_fill:
		hand_fill_sounds.append(hand_fill)
	var hand_fill2 = load("res://Assets/sounds/sfx/HandFill2.mp3")
	if hand_fill2:
		hand_fill_sounds.append(hand_fill2)
	
	# Load HandDiscard sound
	var hand_discard = load("res://Assets/sounds/sfx/HandDiscard1.mp3")
	if hand_discard:
		hand_discard_sounds.append(hand_discard)
	
	# Load SingleDiscard sounds (1-2, updated based on your changes)
	for i in range(1, 3):
		var sound = load("res://Assets/sounds/sfx/SingleDiscard%d.mp3" % i)
		if sound:
			single_discard_sounds.append(sound)

	# Load CountBeep (used for pitched counting sequences)
	count_beep_sound = load("res://Assets/sounds/sfx/CountBeep.mp3")

	# UI button sounds
	button_click_sound = load("res://Assets/sounds/sfx/ButtonClick.mp3")
	button_hover_sound = load("res://Assets/sounds/sfx/HoverButton.mp3")

	# Deck sounds
	deck_load_sound = load("res://Assets/sounds/sfx/DeckLoad.mp3")
	deck_load2_sound = load("res://Assets/sounds/sfx/DeckLoad2.mp3")

	# Game outcome sounds
	game_win_sound = load("res://Assets/sounds/sfx/GameWin.mp3")
	game_lost_sound = load("res://Assets/sounds/sfx/GameLost.mp3")
	game_tied_sound = load("res://Assets/sounds/sfx/GameTied.mp3")

	# Turn/pass sounds
	pass_sound = load("res://Assets/sounds/sfx/Pass.mp3")
	opponent_turn_sound = load("res://Assets/sounds/sfx/OpponentTurn.mp3")
	player_turn_sound = load("res://Assets/sounds/sfx/PlayerTurn.mp3")

	# Reveal sounds (multiple variations)
	for i in range(1, 5):
		var r = load("res://Assets/sounds/sfx/Reveal_%d.mp3" % i)
		if r:
			reveal_sounds.append(r)

	# Round result sounds
	round_won_sound = load("res://Assets/sounds/sfx/RoundWon.mp3")
	round_lost_sound = load("res://Assets/sounds/sfx/RoundLost.mp3")
	round_tied_sound = load("res://Assets/sounds/sfx/RoundTied.mp3")

	# Score beep (short single beep)
	score_beep_sound = load("res://Assets/sounds/sfx/ScoreBeep.mp3")
	
	# Swap selection sound
	selecting_swap_sound = load("res://Assets/sounds/sfx/SelectingSwap.mp3")


func _create_audio_players() -> void:
	for i in range(MAX_AUDIO_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		audio_players.append(player)


func _get_available_player() -> AudioStreamPlayer:
	# Find a player that's not currently playing
	for player in audio_players:
		if not player.playing:
			return player
	# If all players are busy, return the first one (will interrupt)
	return audio_players[0]


func _play_random_from_array(sound_array: Array[AudioStream], volume_db: float = 0.0) -> void:
	if sound_array.is_empty():
		return
	
	var sound = sound_array[rng.randi_range(0, sound_array.size() - 1)]
	var player = _get_available_player()
	player.stream = sound
	# Apply optional normalization offset
	var out_db = volume_db
	if normalize_volumes:
		out_db = global_sfx_db
	player.volume_db = out_db
	player.play()


func _play_sound(sound: AudioStream, volume_db: float = 0.0) -> void:
	if not sound:
		return
	
	var player = _get_available_player()
	player.stream = sound
	# Apply optional normalization offset
	var out_db = volume_db
	if normalize_volumes:
		out_db = global_sfx_db
	player.volume_db = out_db
	player.play()


# Public API for playing sounds

## Play a random card touch sound (for hover/click interactions)
func play_card_touch(volume_db: float = 0.0) -> void:
	_play_random_from_array(card_touch_sounds, volume_db)


## Play the card played sound (when placing a card on the play area)
func play_card_played(volume_db: float = 0.0) -> void:
	_play_sound(card_played_sound, volume_db)


## Play a random hand fill sound (when drawing multiple cards)
func play_hand_fill(volume_db: float = 0.0) -> void:
	_play_random_from_array(hand_fill_sounds, volume_db)


## Play hand discard sound (discarding multiple cards)
func play_hand_discard(volume_db: float = 0.0) -> void:
	_play_random_from_array(hand_discard_sounds, volume_db)


## Play a random single discard sound
func play_single_discard(volume_db: float = 0.0) -> void:
	_play_random_from_array(single_discard_sounds, volume_db)


## Play the new round sound
func play_new_round(volume_db: float = 0.0) -> void:
	_play_sound(new_round_sound, volume_db)


## UI Sounds
func play_button_click(volume_db: float = -4.0) -> void:
	if not ui_sounds_enabled:
		return
	_play_sound(button_click_sound, volume_db)

func play_button_hover(volume_db: float = -10.0) -> void:
	if not ui_sounds_enabled:
		return
	_play_sound(button_hover_sound, volume_db)


## Deck / shuffle sounds
func play_deck_load(volume_db: float = -6.0) -> void:
	_play_sound(deck_load_sound, volume_db)

func play_deck_load2(volume_db: float = -6.0) -> void:
	_play_sound(deck_load2_sound, volume_db)


## Game outcome sounds
func play_game_win(volume_db: float = -2.0) -> void:
	_play_sound(game_win_sound, volume_db)

func play_game_lost(volume_db: float = -4.0) -> void:
	_play_sound(game_lost_sound, volume_db)

func play_game_tied(volume_db: float = -6.0) -> void:
	_play_sound(game_tied_sound, volume_db)


## Turn / pass sounds
func play_pass(volume_db: float = -6.0) -> void:
	# Pass sound is important gameplay feedback - always play it
	_play_sound(pass_sound, volume_db)

func play_opponent_turn(volume_db: float = -8.0) -> void:
	_play_sound(opponent_turn_sound, volume_db)

func play_player_turn(volume_db: float = -8.0) -> void:
	_play_sound(player_turn_sound, volume_db)


## Reveal / round result sounds
func play_reveal(volume_db: float = -6.0) -> void:
	# Play reveal sounds in sequence (1→2→3→4) - they already have correct pitches
	if reveal_sounds.is_empty():
		return
	
	var sound = reveal_sounds[current_reveal_index % reveal_sounds.size()]
	current_reveal_index += 1
	
	var player = _get_available_player()
	player.stream = sound
	# Apply optional normalization offset
	var out_db = volume_db
	if normalize_volumes:
		out_db = global_sfx_db
	player.volume_db = out_db
	player.play()

func play_round_won(volume_db: float = -2.0) -> void:
	_play_sound(round_won_sound, volume_db)

func play_round_lost(volume_db: float = -6.0) -> void:
	_play_sound(round_lost_sound, volume_db)

func play_round_tied(volume_db: float = -6.0) -> void:
	_play_sound(round_tied_sound, volume_db)

func play_score_beep(volume_db: float = -6.0) -> void:
	_play_sound(score_beep_sound, volume_db)


## Play a single CountBeep with a pitch scale (1.0 = normal, 2.0 = one octave up, etc.)
func play_count_beep(pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if not count_beep_sound:
		return
	# Use an available player but we need to set pitch_scale per-player.
	var player = _get_available_player()
	player.stream = count_beep_sound
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()


## Play a sequence of pitched CountBeep sounds for numeric feedback.
## start_pitch: base pitch scale, step: amount to multiply per step (e.g. 1.05),
## count: number of beeps, delay_sec: seconds between beeps.
func play_count_sequence(start_pitch: float = 1.0, step: float = 1.05, count: int = 5, delay_sec: float = 0.08, volume_db: float = 0.0) -> void:
	# Play sequentially using await to space them out. Uses short-lived players.
	for i in range(count):
		var pitch = start_pitch * pow(step, i)
		play_count_beep(pitch, volume_db)
		# Yield for a short duration between beeps
		await get_tree().create_timer(delay_sec).timeout


## Play SelectingSwap sound with variable pitch for card highlight feedback
func play_selecting_swap(pitch_scale: float = 1.0, volume_db: float = -12.0) -> void:
	if not selecting_swap_sound:
		return
	var player = _get_available_player()
	player.stream = selecting_swap_sound
	player.pitch_scale = pitch_scale
	# Apply optional normalization offset
	var out_db = volume_db
	if normalize_volumes:
		out_db = global_sfx_db
	player.volume_db = out_db
	player.play()

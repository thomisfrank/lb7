extends Node

# Sound effects organized by type
var card_touch_sounds: Array[AudioStream] = []
var hand_fill_sounds: Array[AudioStream] = []
var hand_discard_sounds: Array[AudioStream] = []
var single_discard_sounds: Array[AudioStream] = []
var card_played_sound: AudioStream = null
var new_round_sound: AudioStream = null

# Audio player pool for concurrent sounds
var audio_players: Array[AudioStreamPlayer] = []
const MAX_AUDIO_PLAYERS = 10

# RNG for randomizing sound selection
var rng = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_sounds()
	_create_audio_players()


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
	player.volume_db = volume_db
	player.play()


func _play_sound(sound: AudioStream, volume_db: float = 0.0) -> void:
	if not sound:
		return
	
	var player = _get_available_player()
	player.stream = sound
	player.volume_db = volume_db
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

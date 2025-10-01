extends Node

@onready var cm: CardManager = $SubViewportContainer/SubViewport/GameLayer/CardManager
@onready var deck: Pile = cm.get_node("Deck") if cm else null
@onready var player_hand: Hand = cm.get_node("PlayerHand") if cm else null
@onready var opponent_hand: Hand = cm.get_node("OpponentHand") if cm else null
@export var desired_deck_size: int = 0 # 0 = create one of each available card

func _ready():
	# Ensure CardManager is ready.
	if cm == null:
		push_error("CardManager not found at expected path")
		return
	
	# Defer card creation to ensure all nodes and resources are fully initialized.
	call_deferred("_create_test_cards")

func _create_test_cards():
	if deck == null:
		# Try to find the Deck container under CardManager
		deck = cm.get_node("Deck") if cm else null
		if deck == null:
			push_error("Deck container not found")
			return

	# Diagnostics: print factory and deck state
	print("DEBUG: card_factory =", cm.card_factory)
	if cm.card_factory:
		print("DEBUG: factory.card_info_dir =", cm.card_factory.card_info_dir)
		print("DEBUG: factory.card_asset_dir =", cm.card_factory.card_asset_dir)
		if cm.card_factory.preloaded_cards != null:
			var keys = cm.card_factory.preloaded_cards.keys()
			print("DEBUG: preloaded card keys count=", keys.size(), " sample=", keys.slice(0,10))

	# Build list of available card names from factory cache if possible.
	var available_names: Array = []
	if cm.card_factory and cm.card_factory.preloaded_cards != null:
		# preloaded_cards stores entries like { "info": {...}, "texture": ... }
		for key in cm.card_factory.preloaded_cards.keys():
			var info = cm.card_factory.preloaded_cards[key].get("info", {})
			# Skip the dedicated back card (either by name or by suit)
			if key.to_lower() == "back":
				continue
			if info and info.has("suit") and String(info.get("suit", "")).to_lower() == "back":
				continue
			available_names.append(key)
	else:
		# Fallback: scan the card_info_dir for JSON filenames
		if cm.card_factory and cm.card_factory.card_info_dir:
			var dir = DirAccess.open(cm.card_factory.card_info_dir)
			if dir:
				dir.list_dir_begin()
				var fn = dir.get_next()
				while fn != "":
					if fn.ends_with(".json"):
						var card_name_local = fn.get_basename()
						if card_name_local.to_lower() != "back":
							available_names.append(card_name_local)
					fn = dir.get_next()
				dir.list_dir_end()

	# Create cards. If desired_deck_size > 0, create that many cards (allow duplicates
	# by sampling available_names). Otherwise, create one instance of each available
	# card (excluding the back).
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	if desired_deck_size > 0 and available_names.size() > 0:
		for i in range(desired_deck_size):
			var pick = available_names[rng.randi_range(0, available_names.size() - 1)]
			var card = null
			if cm.card_factory:
				card = cm.card_factory.create_card(pick, deck)
			if card:
				if deck and deck.card_face_up == false:
					card.show_front = false
				print("created:", pick, " node_path=", card.get_path(), " parent=", card.get_parent())
				print("  -> show_front=", card.show_front, " icon_texture=", card.icon_texture, " card_size=", card.card_size)
			else:
				push_warning("create_card returned null for: " + pick)
				if cm.card_factory:
					print("  factory.card_info_dir=", cm.card_factory.card_info_dir)
					print("  Looking for file:", cm.card_factory.card_info_dir + "/" + pick + ".json")
	else:
		# Create one instance of each available card (excluding the back)
		for card_name in available_names:
			var card = null
			if cm.card_factory:
				card = cm.card_factory.create_card(card_name, deck)
			if card:
				# Make the card face match the pile's setting (face-up/face-down)
				if deck and deck.card_face_up == false:
					card.show_front = false

				print("created:", card_name, " node_path=", card.get_path(), " parent=", card.get_parent())
				# Additional runtime checks
				print("  -> show_front=", card.show_front, " icon_texture=", card.icon_texture, " card_size=", card.card_size)
			else:
				push_warning("create_card returned null for: " + card_name)
				# If create failed, show why by listing the files checked
				if cm.card_factory:
					print("  factory.card_info_dir=", cm.card_factory.card_info_dir)
					print("  Looking for file:", cm.card_factory.card_info_dir + "/" + card_name + ".json")
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

func _input(event):
	# Press R to clear and recreate test cards while running
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if deck:
			deck.clear_cards()
			_create_test_cards()

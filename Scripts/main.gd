extends Node

@onready var cm: CardManager = $SubViewportContainer/SubViewport/GameLayer/CardManager
@onready var deck: Pile = cm.get_node("Deck") if cm else null
@onready var player_hand: Hand = cm.get_node("PlayerHand") if cm else null
@onready var opponent_hand: Hand = cm.get_node("OpponentHand") if cm else null
@export var desired_deck_size: int = 0 # 0 = create one of each available card
@export var debug_deck_counter: bool = false

var deck_counter: Control
var deck_counter_label: Label

func _ready():
	# Ensure CardManager is ready.
	if cm == null:
		push_error("CardManager not found at expected path")
		return
	
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

	# Connect deck signals to update counter when deck changes
	# We'll try to connect after creation as well, but connect here in case deck is already present
	if deck:
		if not deck.is_connected("count_changed", Callable(self, "_update_deck_counter")):
			deck.connect("count_changed", Callable(self, "_update_deck_counter"))
	# If a Discard pile exists, optionally connect to it for mirror updates
	var discard = null
	if cm:
		discard = cm.get_node_or_null("Discard")
		if discard and not discard.is_connected("count_changed", Callable(self, "_update_deck_counter")):
			discard.connect("count_changed", Callable(self, "_update_deck_counter"))

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
				print("created:", card_name, " node_path=", card.get_path(), " parent=", card.get_parent())
				print("  -> show_front=", card.show_front, " icon_texture=", card.icon_texture, " card_size=", card.card_size)
			# Diagnostic: print deck counts after each create (only when debug enabled)
			if debug_deck_counter and deck:
				print("DEBUG: deck.get_card_count() after create=", deck.get_card_count())
				var cards_node = deck.get_node_or_null("Cards")
				if cards_node:
					print("DEBUG: deck.Cards child count=", cards_node.get_child_count())
		else:
			push_warning("create_card returned null for: " + card_name)
			if cm.card_factory and debug_deck_counter:
				print("  factory.card_info_dir=", cm.card_factory.card_info_dir)
				print("  Looking for file:", cm.card_factory.card_info_dir + "/" + card_name + ".json")

	# Diagnostic: dump final deck stats after creating all cards
	if deck:
		print("DEBUG: final deck.get_card_count()=", deck.get_card_count())
		print("DEBUG: deck child count=", deck.get_child_count())
		var cards_node = deck.get_node_or_null("Cards")
		if cards_node:
			print("DEBUG: deck.Cards child count=", cards_node.get_child_count())

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
		print("DEBUG: _update_deck_counter() received override count=", override_count)

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
				print("DEBUG: _update_deck_counter() - found DeckCounter via recursive search ->", found)
				deck_counter = found
				# Prefer direct child path first, then any Label named 'Count'
				deck_counter_label = deck_counter.get_node_or_null("Box/Count")
				if not deck_counter_label:
					var found_label = _find_node_recursive(deck_counter, "Count")
					if found_label and found_label is Label:
						deck_counter_label = found_label
						print("DEBUG: _update_deck_counter() - found Count label via recursive search ->", found_label)
			# Final fallback: search globally for a Label named 'Count' (risky)
			if not deck_counter_label:
				var found_any = _find_node_recursive(search_root, "Count")
				if not found_any and root != search_root:
					found_any = _find_node_recursive(root, "Count")
				if found_any and found_any is Label:
					deck_counter_label = found_any
					print("DEBUG: _update_deck_counter() - fallback found a Label named 'Count' ->", found_any)

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
				print("DEBUG: _update_deck_counter() - deck.get_card_count()=", count, ", deck.Cards child count=", visual_count)
			# If internal count is zero but visual children exist, use visual count
			if count == 0 and visual_count > 0:
				count = visual_count
		else:
			if debug_deck_counter:
				print("DEBUG: _update_deck_counter() - deck has no 'Cards' child, get_card_count()=", count)
		if deck_counter_label:
			# concise print only when debug enabled
			if debug_deck_counter:
				print("DEBUG: _update_deck_counter() - updating label from ", deck_counter_label.text, " to ", str(count))
			# Always update the label silently
			deck_counter_label.text = str(count)
		else:
			if debug_deck_counter:
				print("DEBUG: _update_deck_counter() - deck_counter_label is still null after all attempts")
	else:
		if debug_deck_counter:
			print("DEBUG: _update_deck_counter() - deck is null")

func _input(event):
	# Press R to clear and recreate test cards while running
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if deck:
			deck.clear_cards()
			_create_test_cards()

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
				print("DEBUG: _sync_deck_internal_state() - adding missing child to deck._held_cards: ", child.name)
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
		print("DEBUG: _sync_deck_internal_state() - removing stale held card: ", r)
		deck._held_cards.erase(r)
		changed = true
	# After sync, update visuals
	deck.update_card_ui()
	if changed:
		deck.emit_signal("count_changed", deck.get_card_count())

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

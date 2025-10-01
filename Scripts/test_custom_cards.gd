extends Node

@onready var card_manager: CardManager = $CardManager
@onready var test_pile: Pile = $CardManager/TestPile

func _ready():
	print("Testing custom card system...")
	_create_test_cards()

func _create_test_cards():
	var card_factory = card_manager.card_factory
	
	# Create a few test cards
	var test_cards = ["Draw_2", "Draw_4", "Swap_2", "Swap_4"]
	
	for i in range(test_cards.size()):
		var card_name = test_cards[i]
		var card = card_factory.create_card(card_name, test_pile)
		if card:
			print("Successfully created card: ", card_name)
			# Show back face for even-indexed cards (every other card)
			if i % 2 == 1:
				card.show_front = false
				print("Set card to show back: ", card_name)
			else:
				print("Card showing front: ", card_name)
		else:
			print("Failed to create card: ", card_name)
	
	# Also create a proper back card
	var back_card = card_factory.create_card("Back", test_pile)
	if back_card:
		back_card.show_front = false
		print("Created back card")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			print("Recreating test cards...")
			test_pile.clear_cards()
			_create_test_cards()
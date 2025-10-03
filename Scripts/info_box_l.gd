extends Control

@onready var label: Label = $AspectRatioContainer/Label
@onready var aspect_container: AspectRatioContainer = $AspectRatioContainer

## Horizontal offset from card position
@export var offset_x: float = 0.0
## Vertical offset from card position (negative = above card)
@export var offset_y: float = -200.0
## Z-index for rendering order (higher = on top)
@export var box_z_index: int = 2000
## Minimum size of the info box container
@export var container_size: Vector2 = Vector2(300, 100)

var player_hand: Hand = null
var tracked_card: Card = null  # The card we're currently showing info for

# Card descriptions
const CARD_DESCRIPTIONS = {
	"Draw": "Discard this card, then draw 1 card.",
	"Swap": "Choose a card from your opponent's hand and swap it with this card."
}

func _ready() -> void:
	# Start hidden
	visible = false
	
	# Find the player hand in the scene
	call_deferred("_find_player_hand")


func _process(_delta: float) -> void:
	# Update info box position every frame to follow the tracked card
	if visible and tracked_card and is_instance_valid(tracked_card):
		_update_info_box_position()


func _find_player_hand() -> void:
	# Try to find PlayerHand in the scene tree
	var root = get_tree().get_root()
	player_hand = _find_node_recursive(root, "PlayerHand")
	
	if player_hand:
		# Connect to all cards in the hand
		_connect_to_hand_cards()
		# Listen for when cards are added/removed
		if player_hand.has_signal("count_changed"):
			player_hand.connect("count_changed", Callable(self, "_on_hand_changed"))
	else:
		push_warning("InfoBoxL: Could not find PlayerHand")


func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_recursive(child, target_name)
		if result:
			return result
	return null


func _connect_to_hand_cards() -> void:
	if not player_hand:
		return
	
	for card in player_hand._held_cards:
		_connect_to_card(card)


func _connect_to_card(card: Card) -> void:
	if not card:
		return
	
	# Connect to mouse signals
	if not card.is_connected("mouse_entered", Callable(self, "_on_card_hover_start")):
		card.connect("mouse_entered", Callable(self, "_on_card_hover_start").bind(card))
	
	if not card.is_connected("mouse_exited", Callable(self, "_on_card_hover_end")):
		card.connect("mouse_exited", Callable(self, "_on_card_hover_end").bind(card))
	
	# Connect to gui_input to detect when dragging starts
	if not card.is_connected("gui_input", Callable(self, "_on_card_input")):
		card.connect("gui_input", Callable(self, "_on_card_input"))


func _on_hand_changed(_count: int) -> void:
	# Reconnect to all cards when hand changes
	call_deferred("_connect_to_hand_cards")


func _on_card_hover_start(card: Card) -> void:
	if not card or not card.card_container == player_hand:
		return
	
	# Get the card type from card_name (e.g., "Draw_2" -> "Draw")
	var card_type = _get_card_type(card.card_name)
	
	if CARD_DESCRIPTIONS.has(card_type):
		show_description(CARD_DESCRIPTIONS[card_type], card)


func _on_card_hover_end(_card: Card) -> void:
	hide_description()


func _on_card_input(event: InputEvent) -> void:
	# Hide info box when user starts dragging (mouse button pressed)
	if event is InputEventMouseButton and event.pressed:
		hide_description()


func _get_card_type(card_name: String) -> String:
	# Extract the effect type from card name (e.g., "Draw_2" -> "Draw")
	var parts = card_name.split("_")
	if parts.size() > 0:
		return parts[0]
	return ""


func show_description(description: String, card: Card) -> void:
	if not label or not aspect_container:
		return
	
	# Set the description text
	label.text = description
	
	# Track this card for continuous position updates
	tracked_card = card
	
	# Size the container using exported size
	aspect_container.custom_minimum_size = container_size
	
	# Ensure high z-index so it appears above cards
	z_index = box_z_index
	
	# Position the info box and show it
	_update_info_box_position()
	visible = true


func _update_info_box_position() -> void:
	# Update position based on tracked card's current position
	if tracked_card and is_instance_valid(tracked_card) and aspect_container:
		var card_global_pos = tracked_card.global_position
		aspect_container.global_position = card_global_pos + Vector2(offset_x, offset_y)


func hide_description() -> void:
	visible = false
	tracked_card = null  # Clear the tracked card reference

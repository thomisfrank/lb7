class_name FreeCell
extends Pile


var freecell_game: FreecellGame


func is_empty() -> bool:
	return _held_cards.is_empty()


func get_top_card() -> PlayingCard:
	if is_empty():
		return null
	return _held_cards[0] as PlayingCard


func get_string() -> String:
	var card_info := ""
	if not is_empty():
		var card = _held_cards[0]
		card_info = card.get_string()
	return "Freecell: %d, Top Card: %s" % [unique_id, card_info]


func move_cards(cards: Array, index: int = -1, with_history: bool = true) -> bool:
	var result = super.move_cards(cards, index, with_history)
	if result:
		freecell_game.move_count += 1
		freecell_game.update_all_tableaus_cards_can_be_interactwith(true)
	return result


func undo(cards: Array, from_indices: Array = []) -> void:
	super.undo(cards, from_indices)
	freecell_game.undo_count += 1
	freecell_game.update_all_tableaus_cards_can_be_interactwith(false)


func _card_can_be_added(_cards: Array) -> bool:
	if _cards.size() != 1:
		return false
	var _card = _cards[0]
	var playing_card = _card as PlayingCard
	if playing_card == null:
		return false

	if not is_empty():
		return false

	return true

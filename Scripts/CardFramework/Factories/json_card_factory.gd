@tool
## JSON-based card factory implementation with asset management and caching.
##
## JsonCardFactory extends CardFactory to provide JSON-based card creation with
## sophisticated asset loading, data caching, and error handling. It manages
## card definitions stored as JSON files and automatically loads corresponding
## image assets from specified directories.
##
## Key Features:
## - JSON-based card data definition with flexible schema
## - Automatic asset loading and texture management  
## - Performance-optimized data caching for rapid card creation
## - Comprehensive error handling with detailed logging
## - Directory scanning for bulk card data preloading
## - Configurable asset and data directory paths
##
## File Structure Requirements:
## [codeblock]
## project/
## ├── card_assets/          # card_asset_dir
## │   ├── ace_spades.png
## │   └── king_hearts.png
## ├── card_data/            # card_info_dir  
## │   ├── ace_spades.json   # Matches asset filename
## │   └── king_hearts.json
## [/codeblock]
##
## JSON Schema Example:
## [codeblock]
## {
##   "name": "ace_spades",
##   "front_image": "ace_spades.png", 
##   "suit": "spades",
##   "value": "ace"
## }
## [/codeblock]
class_name JsonCardFactory
extends CardFactory

const LOG = preload("res://Scripts/logger.gd")

@export_group("card_scenes")
## Base card scene to instantiate for each card (must inherit from Card class)
@export var default_card_scene: PackedScene

@export_group("asset_paths") 
## Directory path containing card image assets (PNG, JPG, etc.)
@export var card_asset_dir: String
## Directory path containing card information JSON files
@export var card_info_dir: String

@export_group("default_textures")
## Common back face texture used for all cards when face-down
@export var back_image: Texture2D


## Validates configuration and default card scene on initialization.
## Ensures default_card_scene references a valid Card-inherited node.
func _ready() -> void:
	if default_card_scene == null:
		push_error("default_card_scene is not assigned!")
		return
		
	# Validate that default_card_scene produces Card instances
	var temp_instance = default_card_scene.instantiate()
	if not (temp_instance is Card):
		push_error("Invalid node type! default_card_scene must reference a Card.")
		default_card_scene = null
	temp_instance.queue_free()


## Creates a new card instance with JSON data and adds it to the target container.
## Uses cached data if available, otherwise loads from JSON and asset files.
## @param card_name: Identifier matching JSON filename (without .json extension)
## @param target: CardContainer to receive the new card
## @returns: Created Card instance or null if creation failed
func create_card(card_name: String, target: CardContainer) -> Card:
	# Use cached data for optimal performance
	if preloaded_cards.has(card_name):
		var card_info = preloaded_cards[card_name]["info"]
		var icon_texture = preloaded_cards[card_name]["texture"]
		return _create_card_node(card_info.name, icon_texture, target, card_info)
	else:
		# Load card data on-demand (slower but supports dynamic loading)
		LOG.log_args(["Loading card info for:", card_name, " from:", card_info_dir])
		var card_info = _load_card_info(card_name)
		if card_info == null or card_info == {}:
			push_error("Card info not found for card: %s" % card_name)
			LOG.log_args(["Checked path:", card_info_dir + "/" + card_name + ".json"]) 
			return null

		# Load icon texture if specified
		var icon_texture: Texture2D = null
		if card_info.has("icon_path"):
			var icon_path = card_asset_dir + "/" + card_info["icon_path"]
			icon_texture = _load_image(icon_path)
			if icon_texture == null:
				push_warning("Icon image not found: %s" % icon_path)

		return _create_card_node(card_info.name, icon_texture, target, card_info)


## Scans card info directory and preloads all JSON data and textures into cache.
## Significantly improves card creation performance by eliminating file I/O during gameplay.
## Should be called during game initialization or loading screens.
func preload_card_data() -> void:
	LOG.log_args(["preload_card_data called with card_info_dir:", card_info_dir])
	var dir = DirAccess.open(card_info_dir)
	if dir == null:
		push_error("Failed to open directory: %s" % card_info_dir)
		return

	# Scan directory for all JSON files
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# Skip non-JSON files
		if !file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue

		# Extract card name from filename (without .json extension)
		var card_name = file_name.get_basename()
		var card_info = _load_card_info(card_name)
		if card_info == null:
			push_error("Failed to load card info for %s" % card_name)
			continue

		# Load corresponding icon texture asset (if available)
		var icon_texture: Texture2D = null
		if card_info.has("icon_path"):
			var icon_path = card_asset_dir + "/" + card_info.get("icon_path", "")
			icon_texture = _load_image(icon_path)
			if icon_texture == null:
				push_warning("Failed to load card icon: %s" % icon_path)

		# Cache both JSON data and texture for fast access
		preloaded_cards[card_name] = {
			"info": card_info,
			"texture": icon_texture
		}
		LOG.log_args(["Preloaded card data:", preloaded_cards[card_name]])
		
		file_name = dir.get_next()


## Loads and parses JSON card data from file system.
## @param card_name: Card identifier (filename without .json extension)
## @returns: Dictionary containing card data or empty dict if loading failed
func _load_card_info(card_name: String) -> Dictionary:
	var json_path = card_info_dir + "/" + card_name + ".json"
	if !FileAccess.file_exists(json_path):
		return {}

	# Read JSON file content
	var file = FileAccess.open(json_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()

	# Parse JSON with error handling
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse JSON: %s" % json_path)
		return {}

	return json.data


## Loads image texture from file path with error handling.
## @param image_path: Full path to image file
## @returns: Loaded Texture2D or null if loading failed
func _load_image(image_path: String) -> Texture2D:
	var texture = load(image_path) as Texture2D
	if texture == null:
		push_error("Failed to load image resource: %s" % image_path)
		return null
	return texture


## Creates and configures a card node with icon texture and adds it to target container.
## @param card_name: Card identifier for naming and reference
## @param icon_texture: Texture for card icon
## @param target: CardContainer to receive the card
## @param card_info: Dictionary of card data from JSON
## @returns: Configured Card instance or null if addition failed
func _create_card_node(card_name: String, icon_texture: Texture2D, target: CardContainer, card_info: Dictionary) -> Card:
	var card = _generate_card(card_info)
	
	# Validate container can accept this card
	if !target._card_can_be_added([card]):
		LOG.log_args(["Card cannot be added:", card_name])
		card.queue_free()
		return null
	
	# Configure card properties (keep data assignment but defer visuals until node is added)
	card.card_size = card_size
	card.icon_texture = icon_texture

	# Add to scene tree first so _ready() has run and visuals can be updated immediately
	var cards_node = target.get_node("Cards")
	cards_node.add_child(card)

	# Set card data from JSON (this will update all visuals now that the node is in tree)
	card.set_card_data(card_info, icon_texture)

	# Always set up the standardized back face (Back.json) so the logo/frame
	# is applied for all cards, including the dedicated "Back" card.
	LOG.log_args(["Setting up back face for card:", card_info.get("name", "unknown")])
	var back_data = _load_card_info("Back")
	if back_data != null and back_data != {}:
		LOG.log_args(["Loaded back data:", back_data])
		card.setup_card_back(back_data)
	else:
		LOG.log("Failed to load Back.json data")

	# Finally register card with the container's logic
	target.add_card(card)

	return card


## Instantiates a new card from the default card scene.
## @param _card_info: Card data dictionary (reserved for future customization)
## @returns: New Card instance or null if scene is invalid
func _generate_card(_card_info: Dictionary) -> Card:
	if default_card_scene == null:
		push_error("default_card_scene is not assigned!")
		return null
	return default_card_scene.instantiate()

extends Node3D

enum GameItems { POTION, SCROLL }
enum Weather { RAIN, CLEAR }

const SAVE_PATH : String = "user://api_hash.sav"

@export var starting_board_id: String = "starting_dialogue_elements" # pending--no CustomId implemented in Boards yet
@export var starting_board_name: String = "Starting Board"

var current_npc: CharacterBody3D = null
var starting_board: Object = null
var is_dialogue_end: bool = false
var dialogue_unique_option: Object = null
var dialogue_state: bool = false

@onready var arcweave_node: Node = $ArcweaveNode
@onready var player: CharacterBody3D = $Characters/Player
@onready var dialogue: Control = $UI/Dialogue
@onready var dialogue_rich_text: RichTextLabel = $UI/Dialogue/Content
@onready var options_container: VBoxContainer = $UI/Dialogue/OptionsContainer
@onready var avatar: TextureRect = $UI/Dialogue/Avatar
@onready var settings: Control = $UI/Settings
@onready var audio_player: AudioStreamPlayer = $UI/Settings/AudioStreamPlayer


func _ready() -> void:
	load_api_hash()
	prepare_game()
	fetch_data_via_displayed_api() # In case we want to fetch upon game start.
	turn_on_settings()


func prepare_game() -> void:
	prep_all_characters()
	prep_all_character_animations()
	prep_weather()
	starting_board = get_starting_board() # Saving the board where all dialogues start.


func prep_all_character_animations() -> void:
	var character: CharacterBody3D = $Characters/Healer
	character.animation_player.play("idle")
	

func prep_weather() -> void:
	var environment_component : Object = get_component_by_name("environment")
	var weather: Object = environment_component.GetAttribute("Weather")
	match Weather.get(weather.data.to_upper()):
		0: player.rain()
		1: player.rain(false)
		_: push_aw_error("Unrecognised weather value in Environment component.")



func load_file_exists()-> bool:
	if FileAccess.file_exists(SAVE_PATH):
		print("Saved file found.")
		return true
	print("No saved file found to load.")
	return false

# Checks for saved api & hash to display.
# If nothing to load, it displays values from ArcweaveNode's editor.
# Note: it does NOT assign values to ArcweaveAsset.
func load_api_hash() -> void:
	if not load_file_exists():
		display_editor_api_hash() # Load editor's values.
		return
		
	print("Saved API key & project hash found.")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var loaded: Dictionary = file.get_var()
	file.close()
	$UI/Settings/GridContainer/APILineEdit.text = loaded.api_key
	$UI/Settings/GridContainer/HashLineEdit.text = loaded.project_hash


func save_api_hash() -> void: # Saves displayed values in local file
	var current_api_key: String = $UI/Settings/GridContainer/APILineEdit.text
	var current_project_hash : String = $UI/Settings/GridContainer/HashLineEdit.text
	
	var saved: Dictionary = {
		'api_key': current_api_key,
		'project_hash': current_project_hash
	}
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(saved) #store_string(JSON.stringify(saveObject, '\t'))
	file.close()


func _unhandled_input(event: InputEvent) -> void:
	if current_npc is CharacterBody3D:
		if event.is_action_pressed("talk"):
			evaluate_dialogue_input()
		
	if event.is_action_pressed("toggle_settings"):
		if settings.visible:
			turn_on_settings(false)
			return
		turn_on_settings()

# Toggles between showing mouse and letting camera pivot.
func show_cursor(yes: bool = true) -> void:
	if not yes:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func turn_on_settings(state: bool = true) -> void:
	settings.visible = state
	$UI/Inventory.visible = not state
	if dialogue_state:
		state = true
	player.is_pivotable = not state
	show_cursor(state)


func evaluate_dialogue_input() -> void:
	if not dialogue_state:
		dialogue_start()
		return
	if is_dialogue_end:
		dialogue_end()
		return
	if dialogue_unique_option != null:
		select_unique_path()
		dialogue_unique_option = null
	dialogue_continue()


# Pushes error related to the Arcweave side of the workflow
func push_aw_error(error_text: String) -> void:
	var error_msg: String = "ARCWEAVE PROJECT ERROR: " + error_text
	push_error(error_msg)


func push_aw_warning(warning_text: String) -> void:
	var warning_msg: String = "ARCWEAVE PROJECT WARNING: " + warning_text
	push_warning(warning_msg)


# Checks and finds board that contains all dialogue starting elements
func get_starting_board() -> Object:
	for board: Object in arcweave_node.Story.Project.Boards.values():
		if board.Name == starting_board_name:
			return board
	push_aw_error("Project lacking starting board with name: [" + starting_board_name + "].")
	return null


func dialogue_start() -> void: # Called from Input "ENTER/SPACE" when near NPC.
	dialogue_state = true
	player.is_pivotable = false
	show_cursor()
	if dialogue.visible:
		push_warning("Dialogue modal already visible before starting dialogue.")
	dialogue.visible = true
	# First we look for current NPC's starting element.
	set_npc_starting_element()
	var current_element: Object = arcweave_node.Story.GetCurrentElement()
	render_options(current_element) # sets dialogue_unique_option to the unique path
	select_unique_path()
	dialogue_continue()
	
	#select_unique_path() # Starting elements MUST have unique output connection.
	#render_current_options()

func dialogue_continue() -> void:
	# Turning NPC to face player:
	if current_npc.is_healthy:
		# We don't want a lying Wanda to turn, so only "idle."
		current_npc.look_at(player.position)
	# Current element is already set
	render_current_content()
	var current_element: Object = arcweave_node.Story.GetCurrentElement()
	show_speaker_avatar(current_element)
	render_options(current_element)
	update_health_bar(current_npc)
	handle_variable_changes()


func dialogue_end() -> void:
	dialogue_state = false
	show_cursor(false)
	if current_npc.is_healthy:
		current_npc.rotation.y = current_npc.initial_facing_direction
	player.is_pivotable = true
	is_dialogue_end = false # Resetting the "dialogue ending" directive.
	dialogue.visible = false
	dialogue_rich_text.text = ""


func handle_variable_changes() -> void:
	var changed_variables: Dictionary = arcweave_node.Story.GetVariableChanges()
	if changed_variables.is_empty():
		return
	print("Variable changes:")
	print(changed_variables)
	# OK, gotta check the form of the Dictionary
	for changed_variable: String in changed_variables.keys():
		if changed_variable.begins_with("have_"): 
			var item_as_string: String = changed_variable.split("_", 1)[1].to_upper()
			var item_enum: int = GameItems.get(item_as_string)
			var new_item_state: bool = changed_variables[changed_variable].newValue
			inventory_io(item_enum, new_item_state)
		if changed_variable == "wanda_health":
			if changed_variables[changed_variable].oldValue < changed_variables[changed_variable].newValue:
				var wanda: CharacterBody3D = $Characters/Wanda
				wanda.is_healthy = true
				wanda.animation_player.play("get_up")
				wanda.animation_player.queue("idle")
		

func inventory_io(game_item: int, new_state: bool) -> void:
	var inventory_container: BoxContainer = $UI/Inventory/InventoryContainer
	audio_player.play()
	if new_state:
		var Icon: PackedScene = load("res://scenes/inventory_item.tscn")
		var icon: TextureRect = Icon.instantiate()
		icon.texture = load("res://assets/items_icons/" + GameItems.keys()[game_item].to_lower() + ".png")
		inventory_container.add_child(icon)
		return
	
	var items: Array[Node] = inventory_container.get_children()
	for item: TextureRect in items:
		var item_filename: String = item.texture.resource_path.split("/", -1)[-1]
		if item_filename != GameItems.keys()[game_item].to_lower() + ".png":
			continue
		item.queue_free()


func set_npc_starting_element() -> void:
	for element: Object in starting_board.Elements:
		if element.Components.size() != 1:
			continue
		var attached_component: Object = element.Components[0]
		var obj_id_attribute: Object = attached_component.GetAttribute("obj_id")
		if obj_id_attribute == null:
			push_aw_error("Element in Starting Board found without obj_id attribute: " + element.Title)
		if obj_id_attribute.data.to_upper() == current_npc.obj_id:
			print("set_npc_starting_element: starting dialogue of " + current_npc.name)
			arcweave_node.Story.SetCurrentElement(element)
			return
	push_aw_error("Starting element not found.")


func select_unique_path() -> void:
	arcweave_node.Story.SelectPath(dialogue_unique_option)


func render_current_content() -> void:
	var text: String = arcweave_node.Story.GetCurrentRuntimeContent()
	dialogue_rich_text.text = text


func show_speaker_avatar(element: Object) -> void:
	if element.Components.size() == 0 or element.Components == null:
		push_aw_error("Element (Title: [" + element.Title + "]) with id (" + element.Id + ") has no speaker component.")
		return
	if element.Components.size() > 1:
		push_aw_warning("Element (Title: [" + element.Title + "]) with id (" 
			+ element.Id + ") has multiple components. The first one will be considered as the speaker's.")
	var speaker_component: Object = element.Components[0]
	var speaker_obj_id: String = speaker_component.GetAttribute("obj_id").data
	speaker_obj_id = speaker_obj_id.to_lower()
	avatar.texture = load("res://assets/avatars/" + speaker_obj_id + ".png")


func clear_options() -> void:
	for option in options_container.get_children():
		option.queue_free()


# Checking if given element has attribute "tag: dialogue_end"
func has_dialogue_end_tag(element: Object) -> bool:
	var element_tag_attribute: Object = element.GetAttribute("tag")
	if element_tag_attribute != null and element_tag_attribute.data == "dialogue_end":
		print("Last element of dialogue, due to dialogue_end tag.")
		return true
	return false


func render_options(element: Object) -> void:
	clear_options()
	var options: Object = arcweave_node.Story.GenerateCurrentOptions()
	if not options.HasPaths or has_dialogue_end_tag(element):
		is_dialogue_end = true
		return
	var paths: Array = options.Paths # Note: this doesn't work with static typing if .Paths == null
	if paths.size() == 1:
		dialogue_unique_option = paths[0]
		return
	for path: Object in paths:
		create_option_button(path)


func create_option_button(path: Object) -> void:
	var button: Button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = path.label
	options_container.add_child(button)
	button.pressed.connect(_on_option_button_pressed.bind(path))


func get_component_by_obj_id(obj_id: String) -> Object:
	obj_id = obj_id.to_upper()
	for component: Object in arcweave_node.Story.Project.Components.values():
		var obj_id_attribute: Object = component.GetAttribute("obj_id")
		if obj_id_attribute == null:
			continue
		if obj_id_attribute.data.to_upper() == obj_id:
			return component
	print("No match found for obj_id " + obj_id + ".")
	return null


func get_component_by_name(component_name: String) -> Object:
	component_name = component_name.to_upper()
	for component: Object in arcweave_node.Story.Project.Components.values():
		if component.Name.to_upper() == component_name:
			return component
	push_aw_error("Component not found by name: " + component_name)
	return null

func prep_all_characters() -> void:
	for character: CharacterBody3D in $Characters.get_children():
		# Reading the npc's 'obj_id' value and looking it up in Arcweave components as attribute:
		var component: Object = get_component_by_obj_id(character.obj_id)
		# Assigning the colour from Arcweave component:
		var colour_attribute: String = component.GetAttribute("Color").data
		var colour_string: String = get_colour_string_from_colour_attribute(colour_attribute)
		print("Component colour for " + character.name + " is: " + colour_string)
		paint_character(character, colour_string)
		# Assigning the character's name from Arcweave component:
		character.aw_name = component.Name


func get_colour_string_from_colour_attribute(colour_attribute: String) -> String:
	colour_attribute = colour_attribute.to_upper() # Turning "rebecca purple" to "REBECCA PURPLE"
	colour_attribute = colour_attribute.replace("\t", " ") # Turning "REBECCA[--TAB--][--TAB--]PURPLE" to "REBECCA[SPACE][SPACE]PURPLE"
	var colour_name_breakdown: PackedStringArray = colour_attribute.split(" ", false) # Splitting at spaces
	var colour_string: String = "_".join(colour_name_breakdown) # rejoining with single underscores, as in "REBECCA_PURPLE"
	return colour_string


func paint_character(character: CharacterBody3D, colour_string: String) -> void:
	var colour: Color = Color.from_string(colour_string, Color.WHITE)
	if character != player:
		character.aw_colour = colour # This is for the health bar to easily get its colour from each approached npc.
	character.get_node_or_null("Dummy/Armature/Skeleton3D/Beta_Surface").get_active_material(0).albedo_color = colour


func release_all_focus() -> void:
	$UI/Settings/GridContainer/APILineEdit.release_focus()
	$UI/Settings/GridContainer/HashLineEdit.release_focus()


func npc_label_show(npc: CharacterBody3D) -> void:
	if npc == null:
		$UI/CharacterInfo.visible = false
		return
	$UI/CharacterInfo/CharacterValues.text = npc.aw_name
	$UI/CharacterInfo.visible = true
#theme_override_styles/fill


func update_health_bar(npc: CharacterBody3D) -> void:
	var health_bar: ProgressBar = $UI/CharacterInfo/HealthBar
	# Add colour of progress bar
	if npc == null:
		health_bar.value = 0.0
		return
	health_bar.get_theme_stylebox("fill").set("bg_color", npc.aw_colour)
	health_bar.value = get_health(npc)


func get_health(character_node: CharacterBody3D) -> float:
	var character_name: String = character_node.obj_id.to_lower()
	return arcweave_node.Story.Project.GetVariable(character_name + "_health").Value


func display_editor_api_hash() -> void:
	$UI/Settings/GridContainer/APILineEdit.text = arcweave_node.ArcweaveAsset.api_key
	$UI/Settings/GridContainer/HashLineEdit.text = arcweave_node.ArcweaveAsset.project_hash
	$UI/Settings/GridContainer/ProjectNameValueLabel.text = arcweave_node.ArcweaveAsset.project_settings.name


func _on_option_button_pressed(path: Object) -> void:
	clear_options()
	arcweave_node.Story.SelectPath(path)
	dialogue_continue()

func _on_player_npc_approached(npc: CharacterBody3D) -> void:
	current_npc = npc
	update_health_bar(npc)
	npc_label_show(npc)


func _on_player_npc_left(npc: CharacterBody3D) -> void:
	var _character_left: CharacterBody3D = npc # Do something with that?
	dialogue_end()
	current_npc = null
	update_health_bar(null)
	npc_label_show(null)


func _on_fetch_button_pressed() -> void:
	release_all_focus()
	fetch_data_via_displayed_api()

# Fetches the data based on the values in the LineEdit fields,
# then updates the story.
func fetch_data_via_displayed_api() -> void:
	arcweave_node.ArcweaveAsset.api_key = $UI/Settings/GridContainer/APILineEdit.text
	arcweave_node.ArcweaveAsset.project_hash = $UI/Settings/GridContainer/HashLineEdit.text
	arcweave_node.UpdateStory() # sending API Request


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_play_button_pressed() -> void:
	turn_on_settings(false)
	# check for dialogue state.


func _on_save_api_button_pressed() -> void:
	release_all_focus()
	save_api_hash() # Saves displayed values in local file


func _on_arcweave_node_project_updated() -> void:
	audio_player.play()
	$UI/UpdateNotification/AnimationPlayer.play("fade_out")
	$UI/Settings/GridContainer/ProjectNameValueLabel.text = arcweave_node.ArcweaveAsset.project_settings.name
	prepare_game()


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()

extends Node3D

enum GameItems { POTION, SCROLL } # SCROLL is an extra item to experiment with.
enum Weather { RAIN, CLEAR } # Refers to Arcweave project's "Environment" component.

const SAVE_PATH : String = "user://project_info.sav" # Saves API key, project hash, and project name locally.

@export var starting_board_name: String = "Starting Board" # Corresponds to Arcweave project's "Starting Board"

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
	display_project_info() # From saved file, else from ArcweaveNode's ArcweaveAsset.
	prepare_game() # Preps sprites & sets starting Arcweave board for dialogues.
	turn_on_settings() # The Settings Menu.


func _unhandled_input(event: InputEvent) -> void:
	# If player is close to NPC and triggers "talk" action (SPACE/ENTER/LEFT-MOUSE-BUTTON).
	if current_npc is CharacterBody3D:
		if event.is_action_pressed("talk"):
			evaluate_dialogue_input() # Hence, the dialogue begins/continues/ends.
	# Pressing ESC anytime displays/hides the settings menu.
	if event.is_action_pressed("toggle_settings"):
		if settings.visible:
			turn_on_settings(false)
			return
		turn_on_settings()


# Returns whether there is a locally saved API/hash file.
func saved_project_info_file_exists()-> bool:
	if FileAccess.file_exists(SAVE_PATH):
		print("Saved file found.")
		return true
	print("No saved file found to load.")
	return false

func arcweave_asset_inspector_has_project_info() -> bool:
	if arcweave_node.ArcweaveAsset.api_key != "" and arcweave_node.ArcweaveAsset.project_hash != "":
		print("Non-empty api key and hash found in inspector.")
		# This doesn't necessarily mean that inspector has valid values for those.
		return true
	print("Inspector has empty api key and/or hash.")
	return false


# Checks for existing api, hash, and project name to display;
# 1. if saved file exists, displays from that;
# 2. else if inspector has api key & hash, displays from inspector;
# 3. else displays nothing--and user cannot fetch.
# Note: this function only displays!
# * it does NOT assign values to ArcweaveAsset.
# * it does NOT fetch.
func display_project_info() -> void:
	# Since we can only fetch via WebAPI from the exported game, we first
	# force ArcweaveAsset's receive method to WebAPI:
	arcweave_node.ArcweaveAsset.receive_method = "WebAPI"
	var api_field: LineEdit = $UI/Settings/GridContainer/APILineEdit
	var project_hash_field: LineEdit = $UI/Settings/GridContainer/HashLineEdit
	var project_name_label: Label = $UI/Settings/GridContainer/ProjectNameValueLabel
	# Let's first clean those from any previous remains:
	# Display project name from ArcweaveAsset's inspector--will get refreshed if saved file exists:
	# If there is saved file with api/hash/project_name display from that:
	if saved_project_info_file_exists():
		print("Saved API key & project hash found.")
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var loaded: Dictionary = file.get_var()
		file.close()
		api_field.text = loaded.api_key
		project_hash_field.text = loaded.project_hash
		project_name_label.text = loaded.project_name
		return
	# Else, display api/hash/project_name from ArcweaveNode's ArcweaveAsset:
	api_field.text = arcweave_node.ArcweaveAsset.api_key
	project_hash_field.text = arcweave_node.ArcweaveAsset.project_hash
	project_name_label.text = arcweave_node.ArcweaveAsset.project_settings.name


# Saves displayed API/hash values in local file.
func save_project_info() -> void:
	var current_api_key: String = $UI/Settings/GridContainer/APILineEdit.text
	var current_project_hash: String = $UI/Settings/GridContainer/HashLineEdit.text
	var current_project_name: String = $UI/Settings/GridContainer/ProjectNameValueLabel.text
	var saved: Dictionary = {
		'api_key': current_api_key,
		'project_hash': current_project_hash,
		'project_name': current_project_name
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(saved) #store_string(JSON.stringify(saveObject, '\t'))
	file.close()


func prepare_game() -> void:
	prep_all_characters()
	prep_all_character_animations()
	prep_weather()
	starting_board = get_starting_board() # Stores the board where all dialogues start for quick access.


func prep_all_character_animations() -> void:
	# Assigns animation to each character
	# Ad hoc solution implemented: only Healer gets "idle."
	var character: CharacterBody3D = $Characters/Healer
	character.animation_player.play("idle")
	

# De/activates player's rain cloud, based on "Environment" Arcweave component.
func prep_weather() -> void:
	var environment_component : Object = get_component_by_name("environment")
	var weather: Object = environment_component.GetAttribute("Weather")
	match Weather.get(weather.data.to_upper()):
		0: player.rain()
		1: player.rain(false)
		_: push_aw_error("Unrecognised weather value in Environment component.")


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


# Pushes error related to the Arcweave side of the workflow.
func push_aw_error(error_text: String) -> void:
	var error_msg: String = "ARCWEAVE PROJECT ERROR: " + error_text
	push_error(error_msg)


# Pushes warning related to the Arcweave side of the workflow.
func push_aw_warning(warning_text: String) -> void:
	var warning_msg: String = "ARCWEAVE PROJECT WARNING: " + warning_text
	push_warning(warning_msg)


####################################################################################################
####### DIALOGUE-RELATED ###########################################################################
####################################################################################################

# Checks and finds Starting Board, which contains every dialogue's starting element.
func get_starting_board() -> Object:
	for board: Object in arcweave_node.Story.Project.Boards.values():
		if board.Name == starting_board_name:
			return board
	push_aw_error("Project lacking starting board with name: [" + starting_board_name + "].")
	return null


# Called from _unhandled_input() "talk" action, when near NPC.
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


func dialogue_start() -> void:
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
	select_unique_path() # Starting elements MUST have unique output connection.
	dialogue_continue()


func dialogue_continue() -> void:
	# Turning NPC to face player:
	if current_npc.is_healthy:
		# We don't want a lying Wanda to turn, so only the healthy ones do that.
		current_npc.look_at(player.position)
	# Note: current element is already set from select_unique_path()...
	render_current_content()
	# We also get the current element from Story, to display speaker avatar etc.
	var current_element: Object = arcweave_node.Story.GetCurrentElement()
	show_speaker_avatar(current_element)
	render_options(current_element)
	update_health_bar(current_npc)
	handle_variable_changes()


func dialogue_end() -> void:
	dialogue_state = false
	show_cursor(false)
	if current_npc.is_healthy: # Again: only healthy NPCs rotate to face someone.
		current_npc.rotation.y = current_npc.initial_facing_direction
	player.is_pivotable = true
	is_dialogue_end = false # Resetting the "dialogue ending" directive.
	dialogue.visible = false
	dialogue_rich_text.text = ""


# We check for any variables that changed during the dialogue turn
# and perform some specific actions, like inventory I/O and health +/-
func handle_variable_changes() -> void:
	var changed_variables: Dictionary = arcweave_node.Story.GetVariableChanges()
	if changed_variables.is_empty():
		return
	print("Variable changes:")
	print(changed_variables)
	for changed_variable: String in changed_variables.keys():
		if changed_variable.begins_with("have_"): 
			var item_as_string: String = changed_variable.split("_", 1)[1].to_upper()
			var item_enum: int = GameItems.get(item_as_string)
			var new_item_state: bool = changed_variables[changed_variable].newValue
			inventory_io(item_enum, new_item_state)
		if changed_variable == "wanda_health": # Yep, it's cheap, but does the job.
			if changed_variables[changed_variable].oldValue < changed_variables[changed_variable].newValue:
				var wanda: CharacterBody3D = $Characters/Wanda
				wanda.is_healthy = true
				wanda.animation_player.play("get_up")
				wanda.animation_player.queue("idle")
		

# Performs inventory actions: add/remove an item.
func inventory_io(game_item: int, new_state: bool) -> void:
	var inventory_container: BoxContainer = $UI/Inventory/InventoryContainer
	audio_player.play()
	# Adding item:
	if new_state:
		var Icon: PackedScene = load("res://scenes/inventory_item.tscn")
		var icon: TextureRect = Icon.instantiate()
		icon.texture = load("res://assets/items_icons/" + GameItems.keys()[game_item].to_lower() + ".png")
		inventory_container.add_child(icon)
		return
	# Removing item:
	var items: Array[Node] = inventory_container.get_children()
	for item: TextureRect in items:
		var item_filename: String = item.texture.resource_path.split("/", -1)[-1]
		if item_filename != GameItems.keys()[game_item].to_lower() + ".png":
			continue
		# You can add a check, if item not found, and push an arcweave error.
		item.queue_free()


# Finds the current NPC's starting element and sets it as current.
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


# This is called when an element has only one output connection to follow
# so no option buttons to be displayed.
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


# Clears previous option buttons.
func clear_options() -> void:
	for option in options_container.get_children():
		option.queue_free()


# Checking if given element has attribute "tag: dialogue_end"
# If yes, this means this is dialogue's last element.
func has_dialogue_end_tag(element: Object) -> bool:
	var element_tag_attribute: Object = element.GetAttribute("tag")
	if element_tag_attribute != null and element_tag_attribute.data == "dialogue_end":
		print("Last element of dialogue, due to dialogue_end tag.")
		return true
	return false


func render_options(element: Object) -> void:
	clear_options()
	var options: Object = arcweave_node.Story.GenerateCurrentOptions()
	# If no output connections or "tag: dialogue_end" found,
	# dialogue is marked for ending, at the next call of evaluate_dialogue_input():
	if not options.HasPaths or has_dialogue_end_tag(element):
		is_dialogue_end = true # For next call of evaluate_dialogue_input()
		return
	var paths: Array = options.Paths
	# Note: this doesn't work with static typing if options.Paths == null
	if paths.size() == 1:
		dialogue_unique_option = paths[0] # For next call of evaluate_dialogue_input()
		return
	for path: Object in paths:
		create_option_button(path)


func create_option_button(path: Object) -> void:
	var button: Button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = path.label
	options_container.add_child(button)
	button.pressed.connect(_on_option_button_pressed.bind(path))


####################################################################################################
####### PREPPING-RELATED ###########################################################################
####################################################################################################


# Returns a Component (as Object) from given obj_id Component attribute.
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


# Returns a Component (as Object) from given component name.
func get_component_by_name(component_name: String) -> Object:
	component_name = component_name.to_upper()
	for component: Object in arcweave_node.Story.Project.Components.values():
		if component.Name.to_upper() == component_name:
			return component
	push_aw_error("Component not found by name: " + component_name)
	return null


# Assigns Arcweave components' full name & colour to all character nodes.
func prep_all_characters() -> void:
	for character: CharacterBody3D in $Characters.get_children():
		# Reading the npc's 'obj_id' value and looking it up in Arcweave components as attribute:
		var component: Object = get_component_by_obj_id(character.obj_id)
		# Assigning the colour from Arcweave component:
		var colour_attribute: String = component.GetAttribute("Color").data
		var colour: Color = Color.from_string(colour_attribute, Color.NAVAJO_WHITE)
		print("Component colour for " + character.name + " is: " + colour_attribute)
		paint_character(character, colour)
		# Assigning the character's name from Arcweave component:
		character.aw_name = component.Name


# Paints a character's albedo_color to the given colour--sorry for use of both "o" and "ou" in colour!
func paint_character(character: CharacterBody3D, colour: Color) -> void:
	#var colour: Color = Color.from_string(colour_string, Color.WHITE)
	if character != player:
		character.aw_colour = colour # This is for the health bar to easily get its colour from each approached npc.
	character.get_node_or_null("Dummy/Armature/Skeleton3D/Beta_Surface").get_active_material(0).albedo_color = colour


func release_all_focus() -> void:
	$UI/Settings/GridContainer/APILineEdit.release_focus()
	$UI/Settings/GridContainer/HashLineEdit.release_focus()


# Displays the NPC's label with their name.
func npc_label_show(npc: CharacterBody3D) -> void:
	if npc == null:
		$UI/CharacterInfo.visible = false
		return
	$UI/CharacterInfo/CharacterValues.text = npc.aw_name
	$UI/CharacterInfo.visible = true


# Updates NPC's health bar.
func update_health_bar(npc: CharacterBody3D) -> void:
	var health_bar: ProgressBar = $UI/CharacterInfo/HealthBar
	# Add colour of progress bar
	if npc == null:
		health_bar.value = 0.0
		return
	health_bar.get_theme_stylebox("fill").set("bg_color", npc.aw_colour)
	health_bar.value = get_health(npc)


# Gets NPC's health by reading relevant "_health" Arcweave variable.
func get_health(character_node: CharacterBody3D) -> float:
	var character_name: String = character_node.obj_id.to_lower()
	return arcweave_node.Story.Project.GetVariable(character_name + "_health").Value



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
	fetch_data_via_displayed_project_info()


# Fetches the data based on the values in the LineEdit fields,
# then updates the story.
func fetch_data_via_displayed_project_info() -> void:
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
	save_project_info() # Saves displayed API key, project hash, and project name in local file


func _on_arcweave_node_project_updated() -> void:
	audio_player.play()
	$UI/UpdateNotification/AnimationPlayer.play("fade_out")
	$UI/Settings/GridContainer/ProjectNameValueLabel.text = arcweave_node.ArcweaveAsset.project_settings.name
	$UI/Settings/DataButtons/SaveAPIButton.disabled = false
	prepare_game()


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_api_line_edit_text_changed(_new_text: String) -> void:
	$UI/Settings/DataButtons/SaveAPIButton.disabled = true


func _on_hash_line_edit_text_changed(_new_text: String) -> void:
	$UI/Settings/DataButtons/SaveAPIButton.disabled = true

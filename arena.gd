extends Node3D

const CYAN := Color("#55f9ef")
const RED := Color("#ff526d")
const GOLD := Color("#ffd070")
const MAX_LEVEL := 100
const SHIELD_NAMES := ["Guardian", "Swift", "Nova"]
const SHIELD_COLORS := [Color("#55f9ef"), Color("#a9f16c"), Color("#e0a3ff")]
const SHIELD_WINDOWS := [0.58, 0.38, 0.47]
const SHIELD_COOLDOWNS := [0.74, 0.48, 0.95]
const SHIELD_RANGES := [2.65, 2.15, 2.35]
const POWER_NAMES := ["Aegis", "Dash", "Shockwave"]
const SHIELD_UNLOCKS := [1, 5, 12]
const SAVE_PATH := "user://ricochet_forest.cfg"
const LIMIT := 15.0
const HEIGHT := 1.05

enum State { TITLE, BETWEEN, FIGHT, PAUSED, WON, LOST }

class Drone:
	var node: Node3D
	var hp: int
	var cooldown: float
	var heavy: bool
	var charge: MeshInstance3D
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	var boss := false
	var strafe := 1.0
	var tag: Label3D

class Shot:
	var node: MeshInstance3D
	var velocity: Vector3
	var returned := false
	var perfect := false
	var heavy := false
	var trail: MeshInstance3D

var state := State.TITLE
var resume_state := State.FIGHT
var camera: Camera3D
var player: Node3D
var shield: MeshInstance3D
var player_shell: MeshInstance3D
var hud: Control
var banner: PanelContainer
var title: Label
var detail: Label
var action: Button
var stats: Label
var round_label: Label
var feedback_label: Label
var shield_meter: ProgressBar
var mute_button: Button
var sounds: Dictionary = {}
var drones: Array[Drone] = []
var shots: Array[Shot] = []
var materials: Dictionary = {}
var wave := 0
var health := 5
var score := 0
var best := 0
var combo := 0
var perfect_count := 0
var delay := 0.0
var parry_age := 1.0
var cooldown := 0.0
var invulnerable := 0.0
var feedback_time := 0.0
var aim := Vector3(0, HEIGHT, -5)
var shake := 0.0
var beat := 0.0
var muted := false
var assist := true
var loadout := 0
var shield_level := 1
var max_health := 5
var power := 0.0
var aegis := 0.0
var dash := 0.0
var highest_level := 1
var checkpoint := 1
var preferred_start := 1
var camera_yaw := 0.0
var camera_pitch := 0.20
var player_legs: Array[Node3D] = []
var player_arms: Array[Node3D] = []
var loadout_label: Label
var reticle_ui: Label
var shield_disc: MeshInstance3D
var equipment: OptionButton
var world_environment: Environment
var sun: DirectionalLight3D
var scenery := RandomNumberGenerator.new()
var lit_materials: Dictionary = {}


func _ready() -> void:
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) == OK:
		best = int(save.get_value("scores", "best", 0))
	highest_level = clampi(int(save.get_value("progress", "level", 1)), 1, MAX_LEVEL)
	checkpoint = clampi(int(save.get_value("progress", "checkpoint", 1)), 1, highest_level)
	preferred_start = checkpoint
	build_arena()
	build_hud()
	sounds["parry"] = synth(490, 1030, 0.14)
	sounds["perfect"] = synth(640, 1480, 0.24)
	sounds["hit"] = synth(170, 54, 0.22)
	sounds["blast"] = synth(112, 34, 0.30)
	sounds["fire"] = synth(280, 115, 0.09)
	sounds["clear"] = synth(330, 880, 0.40)
	refresh_hud()
	show_title()


func show_title() -> void:
	show_panel("RICOCHET\nPROTOCOL", "WOODLAND CAMPAIGN\nReturn incoming shots. Reach level 100 and defeat the Warden.\nWASD move  •  Mouse look  •  Click / Space return  •  Q power\n1 / 2 / 3 switch shields  •  N restarts at level 1 from this screen", "START LEVEL %d" % preferred_start)


func build_arena() -> void:
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#367ab2")
	sky_material.sky_horizon_color = Color("#c7e2e8")
	sky_material.ground_horizon_color = Color("#a6b9ad")
	sky.sky_material = sky_material
	world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("#c0daf6")
	world_environment.ambient_light_energy = 0.68
	world_environment.fog_enabled = true
	world_environment.fog_light_color = Color("#a6c4c7")
	world_environment.fog_density = 0.009
	var environment_node := WorldEnvironment.new()
	environment_node.environment = world_environment
	add_child(environment_node)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -34, 0)
	sun.light_color = Color("#ffe1ac")
	sun.light_energy = 1.16
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 53.0
	add_child(sun)
	terrain()

	player = Node3D.new()
	add_child(player)
	player.position = Vector3(0, HEIGHT, 9)
	player_shell = avatar(player, Color("#3e7898"), CYAN, player_legs, player_arms)
	shield_disc = solid(player, cylinder(0.43, 0.060, 8), Vector3(-0.65, 0.06, -0.24), CYAN)
	shield_disc.rotation.x = PI / 2.0
	shield = ring(self, 1.0, CYAN)
	shield.hide()
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 73.0
	camera.current = true
	update_camera()


func terrain() -> void:
	scenery.seed = 38812
	var ground := SurfaceTool.new()
	ground.begin(Mesh.PRIMITIVE_TRIANGLES)
	var soil := StandardMaterial3D.new()
	soil.vertex_color_use_as_albedo = true
	ground.set_material(soil)
	for x in range(-36, 36, 2):
		for z in range(-36, 36, 2):
			var a := terrain_vertex(x, z)
			var b := terrain_vertex(x + 2, z)
			var c := terrain_vertex(x, z + 2)
			var d := terrain_vertex(x + 2, z + 2)
			var field_color := Color("#779344").lerp(Color("#486832"), scenery.randf_range(0.02, 0.74))
			if absf(x + sin(z * 0.13) * 3) <= 2 or Vector2(x, z + 7).length() < 4.2:
				field_color = Color("#a3885b").lerp(Color("#766543"), scenery.randf_range(0.0, 0.45))
			for vertex in [a, b, c, b, d, c]:
				ground.set_color(field_color)
				ground.add_vertex(vertex)
	ground.generate_normals()
	var meadow := MeshInstance3D.new()
	meadow.mesh = ground.commit()
	add_child(meadow)

	for i in range(64):
		var angle := TAU * (i + scenery.randf_range(-0.25, 0.25)) / 64.0
		var distance := scenery.randf_range(20.0, 33.0)
		var point := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		point.y = terrain_vertex(point.x, point.z).y
		if maxf(absf(point.x), absf(point.z)) < 18.0:
			continue
		tree(point, scenery.randf_range(0.80, 1.55), i % 3 == 0)
	for i in range(26):
		var edge := Vector3(scenery.randf_range(-29, 29), 0, scenery.randf_range(-29, 29))
		if maxf(absf(edge.x), absf(edge.z)) < 16.8:
			continue
		edge.y = terrain_vertex(edge.x, edge.z).y
		var rock := solid(self, sphere(0.62, 5), edge, Color("#657169"))
		rock.scale = Vector3(1.8, 0.8, 1.0)

	for color in [Color("#9db757"), Color("#527f43"), Color("#778e3f")]:
		grass_batch(color)
	for i in range(54):
		var x := scenery.randf_range(-15.5, 15.5)
		var z := scenery.randf_range(-15.5, 15.5)
		if absf(x + sin(z * 0.13) * 3) > 2.4:
			var blossom := solid(self, sphere(0.065, 5), Vector3(x, 0.13, z), Color("#e8cf78") if i % 2 else Color("#c2a3df"))
			blossom.scale.y = 0.52

	for x in [-14.5, 14.5]:
		for z in [-13.5, 13.5]:
			for i in range(3):
				var stake := Vector3(x + i * 0.27, 0.22 + i * 0.035, z)
				solid(self, cylinder(0.085, 0.50 + i * 0.07, 5), stake, Color("#9c8461"))
	for x in [-4.0, 4.0]:
		solid(self, cylinder(0.17, 2.4, 6), Vector3(x, 1.2, -16.3), Color("#634a33"))
		solid(self, sphere(0.29, 7), Vector3(x, 2.45, -16.3), Color("#ffc778"))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(8.4, 0.32, 0.26)
	solid(self, lintel, Vector3(0, 2.15, -16.3), Color("#68553a"))


func terrain_vertex(x: float, z: float) -> Vector3:
	var edge := maxf(absf(x), absf(z))
	var elevation := clampf((edge - 16) / 10, 0, 1) * (0.65 + 0.48 * sin(x * 0.24) + 0.50 * cos(z * 0.23))
	return Vector3(x, elevation, z)


func grass_batch(color: Color) -> void:
	var patch := MultiMesh.new()
	patch.transform_format = MultiMesh.TRANSFORM_3D
	var shape := QuadMesh.new()
	shape.size = Vector2(0.20, 0.30)
	patch.mesh = shape
	patch.instance_count = 520
	for i in patch.instance_count:
		var x := scenery.randf_range(-25, 25)
		var z := scenery.randf_range(-25, 25)
		if absf(x + sin(z * 0.13) * 3) < 2.1:
			x += 3.8
		var scale_factor := scenery.randf_range(0.45, 1.2)
		var basis := Basis(Vector3.UP, scenery.randf_range(0, TAU)).scaled(Vector3.ONE * scale_factor)
		patch.set_instance_transform(i, Transform3D(basis, terrain_vertex(x, z) + Vector3.UP * 0.14 * scale_factor))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = patch
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.roughness = 1.0
	grass.material_override = surface
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)


func tree(at: Vector3, size: float, broadleaf: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	root.scale = Vector3.ONE * size
	solid(root, cylinder(0.21, 3.75, 7, 0.12), Vector3(0, 1.85, 0), Color("#584432"))
	if broadleaf:
		for crown in [Vector3(0, 4.4, 0), Vector3(0.8, 3.75, 0.3), Vector3(-0.86, 3.86, -0.18)]:
			var foliage := solid(root, sphere(1.35, 7), crown, Color("#4c783c").lightened(scenery.randf_range(0.0, 0.23)))
			foliage.scale.y = 0.81
	else:
		for i in range(3):
			var radius := 1.6 - i * 0.34
			solid(root, cylinder(radius, 1.9, 8, 0.02), Vector3(0, 2.2 + i * 0.9, 0), Color("#315e43").lightened(i * 0.065))


func avatar(parent: Node3D, outfit: Color, trim: Color, legs: Array[Node3D], arms: Array[Node3D]) -> MeshInstance3D:
	var skin := Color("#bf8562")
	var boots := Color("#2b302e")
	var torso := solid(parent, cylinder(0.31, 0.57, 7, 0.43), Vector3(0, 0.22, 0), outfit)
	solid(parent, cylinder(0.36, 0.105, 7), Vector3(0, -0.08, 0), boots)
	solid(parent, cylinder(0.12, 0.16, 8), Vector3(0, 0.54, 0), skin)
	solid(parent, sphere(0.25, 10), Vector3(0, 0.75, -0.008), skin)
	var hair := solid(parent, sphere(0.257, 9), Vector3(0, 0.85, 0.035), boots)
	hair.scale = Vector3(1, 0.62, 0.98)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		parent.add_child(leg)
		leg.position = Vector3(side * 0.165, -0.12, 0)
		solid(leg, cylinder(0.106, 0.54, 7, 0.134), Vector3(0, -0.28, 0), outfit.darkened(0.36))
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.23, 0.23, 0.39)
		solid(leg, shoe, Vector3(0, -0.69, -0.069), boots)
		solid(leg, cylinder(0.106, 0.20, 7), Vector3(0, -0.51, 0), boots)
		legs.append(leg)
		var arm := Node3D.new()
		parent.add_child(arm)
		arm.position = Vector3(side * 0.44, 0.37, 0)
		arm.rotation.z = side * 0.16
		solid(arm, sphere(0.16, 8), Vector3.ZERO, trim.darkened(0.23))
		solid(arm, cylinder(0.097, 0.40, 7, 0.13), Vector3(0, -0.23, 0), outfit)
		solid(arm, sphere(0.105, 7), Vector3(0, -0.48, 0), skin)
		arms.append(arm)
		solid(parent, sphere(0.028, 6), Vector3(side * 0.084, 0.765, -0.239), boots)
	var pack := BoxMesh.new()
	pack.size = Vector3(0.40, 0.44, 0.21)
	solid(parent, pack, Vector3(0, 0.24, 0.27), trim.darkened(0.45))
	return torso


func solid(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if not lit_materials.has(color):
		var paint := StandardMaterial3D.new()
		paint.albedo_color = color
		paint.roughness = 0.95
		lit_materials[color] = paint
	instance.material_override = lit_materials[color]
	instance.position = at
	parent.add_child(instance)
	return instance


func cylinder(bottom: float, height: float, sides: int, top: float = -1.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top if top >= 0.0 else bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


func sphere(radius: float, resolution: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = resolution
	mesh.rings = maxi(4, resolution / 2)
	return mesh


func update_camera() -> void:
	var facing := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var shoulder := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw)) * 0.73
	camera.position = player.position - facing * 4.65 + Vector3.UP * 1.58 + shoulder
	camera.position.x += sin(beat * 87.0) * shake
	var view := facing * cos(camera_pitch) - Vector3.UP * sin(camera_pitch)
	camera.look_at(camera.position + view)
	var crosshair_distance := clampf((camera.position.y - HEIGHT) / maxf(0.035, -view.y), 3.0, 55.0)
	aim = camera.position + view * crosshair_distance
	aim.y = HEIGHT


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := PanelContainer.new()
	hud.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 18
	top.add_theme_stylebox_override("panel", panel_style(Color("#101d31"), Color("#2b536a"), 12))
	var row := HBoxContainer.new()
	top.add_child(row)
	stats = label(20, CYAN)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stats)
	round_label = label(20, GOLD)
	row.add_child(round_label)
	loadout_label = label(16, CYAN)
	row.add_child(loadout_label)
	equipment = OptionButton.new()
	equipment.focus_mode = Control.FOCUS_NONE
	for index in SHIELD_NAMES.size():
		equipment.add_item("%s  [Lv %d]" % [SHIELD_NAMES[index], SHIELD_UNLOCKS[index]])
	equipment.item_selected.connect(func(index: int) -> void:
		equip_shield(index)
		equipment.select(loadout)
	)
	row.add_child(equipment)
	mute_button = Button.new()
	mute_button.text = "SOUND ON"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.pressed.connect(toggle_mute)
	row.add_child(mute_button)

	var bottom := VBoxContainer.new()
	hud.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -275
	bottom.offset_right = 275
	bottom.offset_top = -88
	bottom.offset_bottom = -24
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_label = label(22, GOLD)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.custom_minimum_size.x = 550
	bottom.add_child(feedback_label)
	shield_meter = ProgressBar.new()
	shield_meter.show_percentage = false
	shield_meter.custom_minimum_size = Vector2(190, 7)
	shield_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shield_meter.max_value = 1.0
	shield_meter.add_theme_stylebox_override("fill", panel_style(CYAN, CYAN, 0))
	shield_meter.add_theme_stylebox_override("background", panel_style(Color("#23354d"), Color("#23354d"), 0))
	bottom.add_child(shield_meter)
	var legend := label(13, Color("#a9c4d5"))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.text = "WASD MOVE   •   MOUSE LOOK   •   CLICK / SPACE RETURN   •   Q POWER"
	bottom.add_child(legend)

	reticle_ui = label(26, Color.WHITE)
	reticle_ui.text = "+"
	reticle_ui.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle_ui.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle_ui.add_theme_color_override("font_outline_color", Color.BLACK)
	reticle_ui.add_theme_constant_override("outline_size", 5)
	hud.add_child(reticle_ui)
	reticle_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle_ui.offset_left = -16
	reticle_ui.offset_right = 16
	reticle_ui.offset_top = -16
	reticle_ui.offset_bottom = 16
	reticle_ui.hide()

	banner = PanelContainer.new()
	hud.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -292
	banner.offset_right = 292
	banner.offset_top = -195
	banner.offset_bottom = 195
	banner.add_theme_stylebox_override("panel", panel_style(Color("#101b30"), CYAN.darkened(0.5), 24))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	banner.add_child(column)
	var eyebrow := label(15, GOLD)
	eyebrow.text = "HAVEN GAME JAM   /   BOUNCE BACK"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)
	title = label(49, CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	detail = label(17, Color("#e0eefb"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	action = Button.new()
	action.custom_minimum_size = Vector2(235, 46)
	action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action.focus_mode = Control.FOCUS_NONE
	action.add_theme_font_size_override("font_size", 19)
	action.add_theme_stylebox_override("normal", panel_style(Color("#144157"), CYAN, 9))
	action.add_theme_stylebox_override("hover", panel_style(Color("#226076"), CYAN, 9))
	action.add_theme_stylebox_override("pressed", panel_style(Color("#0d2a3d"), CYAN, 9))
	action.pressed.connect(activate)
	column.add_child(action)


func label(font_size: int, color: Color) -> Label:
	var control := Label.new()
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func panel_style(fill: Color, edge: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func show_panel(heading: String, body: String, button: String) -> void:
	title.text = heading
	detail.text = body
	action.text = button
	banner.show()
	reticle_ui.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func activate() -> void:
	if state == State.PAUSED:
		toggle_pause()
	elif state in [State.TITLE, State.WON, State.LOST]:
		start_run()


func start_run() -> void:
	clear_shots()
	for drone in drones:
		drone.node.queue_free()
	drones.clear()
	wave = preferred_start - 1
	refresh_gear()
	health = max_health
	power = 0.0
	dash = 0.0
	aegis = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.16
	score = 0
	combo = 0
	perfect_count = 0
	player.position = Vector3(0, HEIGHT, 9)
	parry_age = 1.0
	shield.hide()
	shield_meter.value = 1.0
	player_shell.show()
	cooldown = 0.0
	invulnerable = 0.0
	banner.hide()
	reticle_ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_wave()


func start_wave() -> void:
	wave += 1
	var previous_highest := highest_level
	highest_level = maxi(highest_level, wave)
	refresh_gear()
	if wave % 5 == 1 or wave == MAX_LEVEL:
		checkpoint = maxi(checkpoint, wave)
	if wave > previous_highest:
		save_progress()
	state = State.BETWEEN
	delay = 1.0
	var dark := (int((wave - 1) / 10.0) % 2 == 1) or wave == MAX_LEVEL
	var sky := world_environment.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color("#101e46") if dark else Color("#367ab2")
	sky.sky_horizon_color = Color("#576688") if dark else Color("#c7e2e8")
	world_environment.fog_light_color = Color("#534c78") if dark else Color("#a6c4c7")
	world_environment.ambient_light_color = Color("#91a6dc") if dark else Color("#c0daf6")
	sun.light_color = Color("#9bc5ff") if dark else Color("#ffe1ac")
	sun.light_energy = 0.58 if dark else 1.16
	sun.rotation_degrees = Vector3(-34, 49, 0) if dark else Vector3(-48, -34, 0)
	player.position = Vector3(0, HEIGHT, 9)
	camera_yaw = 0.0
	camera_pitch = 0.115
	var positions: Array[Vector2] = [
		Vector2(0, -7), Vector2(-5.8, -3.3), Vector2(5.8, -3.3),
		Vector2(-9, 4), Vector2(9, 4)
	]
	var count := mini(5, 1 + int((wave + 2) / 8.0))
	if wave == MAX_LEVEL:
		count = 3
	for i in range(count):
		var heavy := (wave >= 6 and (wave + i * 3) % 5 == 0) or (wave == MAX_LEVEL and i == 0)
		spawn_drone(positions[i], heavy, i)
	var message := "LEVEL %d  /  %s" % [wave, "MOONLIT WOODS" if dark else "SUNLIT CLEARING"]
	if wave in [5, 12] and wave > previous_highest:
		message += "  •  %s UNLOCKED" % SHIELD_NAMES[1 if wave == 5 else 2].to_upper()
	if wave == MAX_LEVEL:
		message = "FINAL BOSS  /  THE WARDEN"
	announce(message, 2.6)
	refresh_hud()


func spawn_drone(at: Vector2, heavy: bool, order: int) -> void:
	var drone := Drone.new()
	drone.node = Node3D.new()
	add_child(drone.node)
	drone.node.position = Vector3(at.x, HEIGHT, at.y)
	drone.heavy = heavy
	drone.boss = wave == MAX_LEVEL and order == 0
	drone.hp = 22 if drone.boss else (3 if heavy else (1 if wave < 12 else 2))
	drone.cooldown = 0.75 + order * 0.47
	drone.strafe = -1.0 if order % 2 else 1.0
	var accent := GOLD if heavy else RED
	avatar(drone.node, Color("#46244e") if drone.boss else Color("#784839"), accent, drone.legs, drone.arms)
	if drone.boss:
		for child in drone.node.get_children():
			if child is Node3D:
				child.scale *= 1.40
				child.position *= 1.30
	drone.charge = ring(drone.node, 1.65 if drone.boss else 0.86, accent)
	drone.charge.position.y = -1.0
	drone.charge.hide()
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position.y = 2.4 if drone.boss else 1.30
	tag.font_size = 35 if drone.boss else 27
	tag.text = "WARDEN  %d / 22" % drone.hp if drone.boss else ("HEAVY" if heavy else "RAIDER")
	drone.tag = tag
	tag.modulate = accent
	drone.node.add_child(tag)
	drones.append(drone)


func refresh_gear() -> void:
	shield_level = 1 + int((maxi(1, wave) - 1) / 10.0)
	max_health = 5 + int((shield_level - 1) / 2.0)


func equip_shield(index: int) -> void:
	if highest_level < SHIELD_UNLOCKS[index]:
		announce("UNLOCKS AT LEVEL %d" % SHIELD_UNLOCKS[index], 1.5)
		return
	loadout = index
	equipment.select(index)
	shield_disc.material_override = material(SHIELD_COLORS[loadout])
	shield.material_override = material(SHIELD_COLORS[loadout])
	parry_age = 1.0
	announce("%s EQUIPPED" % SHIELD_NAMES[loadout].to_upper(), 1.5)
	refresh_hud()


func use_power() -> void:
	if state != State.FIGHT or power < 1.0:
		return
	power = 0.0
	match loadout:
		0:
			aegis = 3.0
			health = mini(max_health, health + 2)
		1:
			dash = 0.63
			invulnerable = 0.85
		2:
			for shot in shots:
				if not shot.returned and shot.node.position.distance_to(player.position) < 8.0:
					return_shot(shot, 0.0, true)
			power = 0.0
	pulse(player.position, SHIELD_COLORS[loadout], 4.1)
	play_sound("clear", -4)
	announce(POWER_NAMES[loadout].to_upper(), 1.4)
	refresh_hud()


func save_progress() -> void:
	var save := ConfigFile.new()
	save.set_value("scores", "best", best)
	save.set_value("progress", "level", highest_level)
	save.set_value("progress", "checkpoint", checkpoint)
	save.save(SAVE_PATH)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.0032
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.0025, -0.16, 0.83)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				activate()
			KEY_1, KEY_2, KEY_3:
				equip_shield(event.keycode - KEY_1)
			KEY_Q:
				use_power()
			KEY_N:
				if state == State.TITLE:
					preferred_start = 1
					show_title()
			KEY_ESCAPE:
				toggle_pause()
			KEY_M:
				toggle_mute()
			KEY_H:
				assist = not assist
				if state == State.TITLE:
					announce("AIM ASSIST ON" if assist else "AIM ASSIST OFF", 1.6)
				elif state == State.FIGHT or state == State.BETWEEN:
					announce("AIM ASSIST ON" if assist else "AIM ASSIST OFF", 1.6)
			KEY_R:
				if state in [State.WON, State.LOST, State.PAUSED]:
					start_run()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		try_parry()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_parry()


func try_parry() -> void:
	if state != State.FIGHT or cooldown > 0.0:
		return
	parry_age = 0.0
	cooldown = SHIELD_COOLDOWNS[loadout]
	play_sound("parry", -16)


func toggle_pause() -> void:
	if state == State.PAUSED:
		state = resume_state
		banner.hide()
		reticle_ui.show()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif state in [State.BETWEEN, State.FIGHT]:
		resume_state = state
		state = State.PAUSED
		show_panel("PAUSED", "Esc or Enter to resume. R starts a fresh run.", "RESUME")


func toggle_mute() -> void:
	muted = not muted
	mute_button.text = "SOUND OFF" if muted else "SOUND ON"


func _physics_process(delta: float) -> void:
	if state == State.PAUSED:
		return
	beat += delta
	shake = move_toward(shake, 0.0, delta * 1.9)
	feedback_time = maxf(0, feedback_time - delta)
	if feedback_time == 0.0:
		feedback_label.text = ""
	if state in [State.BETWEEN, State.FIGHT]:
		move_player(delta)
	update_camera()
	if state == State.BETWEEN:
		delay -= delta
		if delay <= 0:
			state = State.FIGHT
		return
	if state != State.FIGHT:
		return

	parry_age += delta
	cooldown = maxf(0.0, cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	aegis = maxf(0.0, aegis - delta)
	dash = maxf(0.0, dash - delta)
	shield.visible = parry_age < SHIELD_WINDOWS[loadout] or aegis > 0.0
	shield.scale = Vector3.ONE * (SHIELD_RANGES[loadout] + 0.025 * shield_level)
	shield.position = player.position + Vector3(0, -0.70, 0)
	shield_meter.value = 1.0 - cooldown / maxf(cooldown, SHIELD_COOLDOWNS[loadout])
	player_shell.visible = invulnerable <= 0.0 or int(beat * 26) % 2 == 0
	for drone in drones:
		var offset := player.position - drone.node.position
		if offset.length_squared() > 0.01:
			drone.node.rotation.y = atan2(-offset.x, -offset.z)
		if offset.length_squared() > 0.01 and wave > 1:
			var direction := offset.normalized()
			var travel := direction * clampf((offset.length() - 7.0) / 3.0, -1, 1)
			travel += Vector3(direction.z, 0, -direction.x) * drone.strafe * 0.63
			var movement := travel * (1.10 if drone.heavy else 1.55) * delta
			drone.node.position = (drone.node.position + movement).clamp(Vector3(-LIMIT, HEIGHT, -LIMIT), Vector3(LIMIT, HEIGHT, LIMIT))
			animate_avatar(drone.legs, drone.arms, true, 0.65)
		drone.cooldown -= delta
		drone.charge.visible = drone.cooldown < 0.43
		drone.charge.scale = Vector3.ONE * (1.04 + sin(beat * 25.0) * 0.13)
		if drone.cooldown <= 0.0:
			fire(drone)
			drone.cooldown = (1.42 if drone.hp < 11 else 2.02) if drone.boss else (3.08 if drone.heavy else maxf(1.27, 2.6 - wave * 0.015))

	for index in range(shots.size() - 1, -1, -1):
		step_shot(index, delta)
		if state == State.LOST:
			return
	if drones.is_empty():
		clear_shots()
		player_shell.show()
		shield.hide()
		cooldown = 0.0
		parry_age = 1.0
		aegis = 0.0
		dash = 0.0
		play_sound("clear", -8)
		if wave == MAX_LEVEL:
			end_run(true)
		else:
			health = mini(max_health, health + (2 if wave % 5 == 0 else 1))
			start_wave()


func move_player(delta: float) -> void:
	var direction := Vector3.ZERO
	direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	direction.x -= float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	direction.z = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	direction.z -= float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var movement := Basis(Vector3.UP, camera_yaw) * direction.normalized()
	if dash > 0.0 and movement.is_zero_approx():
		movement = Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var next := player.position + movement * (13.0 if dash > 0.0 else 5.9) * delta
	next.x = clampf(next.x, -LIMIT, LIMIT)
	next.z = clampf(next.z, -LIMIT, LIMIT)
	for drone in drones:
		var offset := next - drone.node.position
		if offset.length_squared() < 1.45 and offset.length_squared() > 0.0001:
			next = drone.node.position + offset.normalized() * sqrt(1.45)
	player.position = next.clamp(Vector3(-LIMIT, HEIGHT, -LIMIT), Vector3(LIMIT, HEIGHT, LIMIT))
	player.rotation.y = camera_yaw
	animate_avatar(player_legs, player_arms, not movement.is_zero_approx(), 1.0)


func animate_avatar(legs: Array[Node3D], arms: Array[Node3D], moving: bool, pace: float) -> void:
	var stride := sin(beat * 13.0 * pace) * (0.49 if moving else 0.0)
	legs[0].rotation.x = stride
	legs[1].rotation.x = -stride
	arms[0].rotation.x = -stride * 0.49
	arms[1].rotation.x = stride * 0.49


func fire(drone: Drone) -> void:
	var direction := drone.node.position.direction_to(player.position)
	launch_shot(drone, direction, drone.heavy)
	if drone.boss:
		launch_shot(drone, direction.rotated(Vector3.UP, -0.40), false)
		launch_shot(drone, direction.rotated(Vector3.UP, 0.40), false)
	play_sound("fire", -17)


func launch_shot(drone: Drone, direction: Vector3, heavy: bool) -> void:
	var shot := Shot.new()
	shot.heavy = heavy
	shot.velocity = direction * (5.1 if shot.heavy else minf(11.0, 5.7 + wave * 0.055))
	var color := GOLD if shot.heavy else RED
	shot.node = orb(self, 0.32 if shot.heavy else 0.19, drone.node.position + direction * 0.65, color)
	shot.trail = box(shot.node, Vector3(0.12, 0.12, 0.70), Vector3(0, 0, 0.57), color.darkened(0.28))
	shots.append(shot)


func step_shot(index: int, delta: float) -> void:
	var shot := shots[index]
	var from := shot.node.position
	var to := from + shot.velocity * delta
	if shot.returned:
		for drone in drones:
			if segment_distance(drone.node.position, from, to) <= (0.96 if drone.heavy else 0.81):
				if shot.heavy:
					blast(to, 3 if shot.perfect else 2)
				else:
					damage_drone(drone, 2 if shot.perfect else 1)
				remove_shot(index)
				return
	else:
		var distance := segment_distance(player.position, from, to)
		if (parry_age < SHIELD_WINDOWS[loadout] or aegis > 0.0) and distance <= SHIELD_RANGES[loadout] + 0.025 * shield_level:
			return_shot(shot, distance)
			to = from
		elif distance <= (0.91 if shot.heavy else 0.66):
			if invulnerable <= 0.0:
				health -= 1
				combo = 0
				invulnerable = 0.85
				shake = 0.28
				announce("SHIELD HIT", 1.0)
				play_sound("hit", -8)
				refresh_hud()
				if health <= 0:
					end_run(false)
			remove_shot(index)
			return
	shot.node.position = to
	shot.node.rotation.y = atan2(-shot.velocity.x, -shot.velocity.z)
	if absf(to.x) > LIMIT + 2.0 or absf(to.z) > LIMIT + 2.0:
		if shot.returned and shot.heavy:
			blast(to, 2)
		remove_shot(index)


func segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var travel := to - from
	var fraction := clampf((point - from).dot(travel) / maxf(travel.length_squared(), 0.00001), 0.0, 1.0)
	return point.distance_to(from + travel * fraction)


func return_shot(shot: Shot, distance: float, force_perfect: bool = false) -> void:
	shot.returned = true
	shot.perfect = force_perfect or (distance < 1.38 and parry_age <= 0.145)
	var direction := (aim - player.position).normalized()
	if direction.length_squared() < 0.001:
		direction = -shot.velocity.normalized()
	var best_alignment := 0.76 if assist else 0.995
	var target := direction
	for drone in drones:
		var candidate := shot.node.position.direction_to(drone.node.position)
		var alignment := direction.dot(candidate)
		if alignment > best_alignment:
			best_alignment = alignment
			target = candidate
	shot.velocity = target * (17.0 if shot.heavy else 22.0)
	var color := GOLD if shot.perfect else CYAN
	shot.node.material_override = material(color)
	shot.trail.material_override = material(color.darkened(0.22))
	combo += 1
	power = minf(1.0, power + (0.34 if shot.perfect else 0.23))
	score += (130 if shot.perfect else 45) * mini(5, combo)
	if shot.perfect:
		perfect_count += 1
		shake = 0.13
	pulse(player.position, color, 2.5)
	announce("PERFECT RETURN   ×%d" % combo if shot.perfect else "RETURNED   ×%d" % combo, 0.85)
	play_sound("perfect" if shot.perfect else "parry", -7)
	refresh_hud()


func blast(at: Vector3, damage: int) -> void:
	pulse(at, GOLD, 3.35)
	shake = 0.25
	play_sound("blast", -6)
	for drone in drones.duplicate():
		if drone.node.position.distance_to(at) <= 3.35:
			damage_drone(drone, damage)


func damage_drone(drone: Drone, damage: int) -> void:
	drone.hp -= damage
	if drone.boss:
		drone.tag.text = "WARDEN  %d / 22" % maxi(0, drone.hp)
	score += 100
	pulse(drone.node.position, RED if drone.hp > 0 else CYAN, 1.7)
	play_sound("hit", -12)
	if drone.hp <= 0:
		score += 250
		drone.node.queue_free()
		drones.erase(drone)
	refresh_hud()


func end_run(won: bool) -> void:
	state = State.WON if won else State.LOST
	shield.hide()
	if score > best:
		best = score
	preferred_start = 1 if won else checkpoint
	save_progress()
	refresh_hud()
	show_panel(
		"WARDEN DEFEATED" if won else "SHIELD BROKEN",
		"Score  %06d    /    Best  %06d\nPerfect returns  %d    /    Level  %d of %d" % [score, best, perfect_count, wave, MAX_LEVEL],
		"PLAY AGAIN" if won else ("RETRY LEVEL %d" % preferred_start)
	)


func remove_shot(index: int) -> void:
	shots[index].node.queue_free()
	shots.remove_at(index)


func clear_shots() -> void:
	for shot in shots:
		shot.node.queue_free()
	shots.clear()


func refresh_hud() -> void:
	stats.text = "HP %d/%d   SCORE %06d   BEST %06d" % [health, max_health, score, maxi(score, best)]
	round_label.text = "LEVEL %03d / %d   " % [maxi(1, wave), MAX_LEVEL]
	loadout_label.text = "%s Lv.%d  •  Q %s %d%%   " % [SHIELD_NAMES[loadout], shield_level, POWER_NAMES[loadout], roundi(power * 100.0)]


func announce(message: String, seconds: float) -> void:
	feedback_label.text = message
	feedback_time = seconds


func pulse(at: Vector3, color: Color, radius: float) -> void:
	var effect := ring(self, 1.0, color)
	effect.position = Vector3(at.x, 0.055, at.z)
	effect.scale = Vector3.ONE * 0.30
	var tween := effect.create_tween().set_parallel()
	tween.tween_property(effect, "scale", Vector3.ONE * radius, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(effect, "transparency", 1.0, 0.28)
	tween.chain().tween_callback(effect.queue_free)


func ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.052
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 6
	return place_mesh(parent, mesh, Vector3.ZERO, color)


func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return place_mesh(parent, mesh, at, color)


func orb(parent: Node3D, radius: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return place_mesh(parent, mesh, at, color)


func place_mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = at
	parent.add_child(instance)
	return instance


func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var surface := StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.albedo_color = color
		materials[color] = surface
	return materials[color]


func synth(start: float, finish: float, duration: float) -> AudioStreamWAV:
	const RATE := 22050
	var samples := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	for i in range(samples):
		var progress := float(i) / float(samples)
		phase += TAU * lerpf(start, finish, progress) / RATE
		var envelope := minf(1.0, progress * 40.0) * pow(1.0 - progress, 2.0)
		var sample := int((sin(phase) + 0.23 * sin(phase * 2.01)) * envelope * 18000)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream


func play_sound(effect: String, volume: float) -> void:
	if muted:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = sounds[effect]
	voice.volume_db = volume
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

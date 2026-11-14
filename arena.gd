extends Node3D

const CYAN := Color("#55f9ef")
const RED := Color("#ff526d")
const GOLD := Color("#ffd070")
const INK := Color("#0c172a")
const WAVE_NAMES := ["Wake-up call", "Crossfire", "Heavy traffic", "The gauntlet", "Lockdown"]
const LIMIT := 9.4
const HEIGHT := 0.8
const PARRY_RADIUS := 2.0

enum State { TITLE, BETWEEN, FIGHT, PAUSED, WON, LOST }

class Drone:
	var node: Node3D
	var hp: int
	var cooldown: float
	var heavy: bool
	var charge: MeshInstance3D

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
var reticle: Node3D
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
var assist := false


func _ready() -> void:
	var save := ConfigFile.new()
	if save.load("user://ricochet.cfg") == OK:
		best = int(save.get_value("scores", "best", 0))
	build_arena()
	build_hud()
	sounds["parry"] = synth(490, 1030, 0.14)
	sounds["perfect"] = synth(640, 1480, 0.24)
	sounds["hit"] = synth(170, 54, 0.22)
	sounds["blast"] = synth(112, 34, 0.30)
	sounds["fire"] = synth(280, 115, 0.09)
	sounds["clear"] = synth(330, 880, 0.40)
	refresh_hud()
	show_panel("RICOCHET\nPROTOCOL", "Survive five waves using their firepower.\nWASD / arrows to move • Mouse to aim • Click / Space to return\nGold hits reward timing. Aim heavy orbs at groups.\n\nPress Enter to start • H toggles aim assist • Esc pauses", "START RUN")


func build_arena() -> void:
	box(self, Vector3(21, 0.4, 21), Vector3(0, -0.24, 0), INK)
	for x in range(-5, 6):
		for z in range(-5, 6):
			var tile_color := Color("#101e33") if (x + z) % 2 == 0 else Color("#14233a")
			box(self, Vector3(1.82, 0.04, 1.82), Vector3(x * 1.9, -0.023, z * 1.9), tile_color)
	for side in [-1.0, 1.0]:
		box(self, Vector3(21, 0.34, 0.55), Vector3(0, 0.08, side * 10.3), Color("#203750"))
		box(self, Vector3(0.55, 0.34, 21), Vector3(side * 10.3, 0.08, 0), Color("#203750"))
		box(self, Vector3(20, 0.035, 0.055), Vector3(0, 0.28, side * 10.3), CYAN.darkened(0.45))
		box(self, Vector3(0.055, 0.035, 20), Vector3(side * 10.3, 0.28, 0), CYAN.darkened(0.45))
		for x in [-10.3, 10.3]:
			box(self, Vector3(0.72, 0.65, 0.72), Vector3(x, 0.3, side * 10.3), GOLD)
	for i in range(18):
		var angle := TAU * i / 18.0
		var mark := box(self, Vector3(0.10, 0.02, 0.44), Vector3(sin(angle) * 3.3, 0.013, cos(angle) * 3.3), Color("#203d55"))
		mark.rotation.y = angle
	player = Node3D.new()
	add_child(player)
	player.position = Vector3(0, HEIGHT, 5)
	box(player, Vector3(0.95, 0.025, 0.95), Vector3(0, -0.78, 0), Color("#1f5465")).rotation.y = PI / 4.0
	player_shell = box(player, Vector3(0.76, 0.49, 0.88), Vector3.ZERO, Color("#207f92"))
	box(player, Vector3(0.48, 0.12, 0.36), Vector3(0, 0.28, -0.13), CYAN)
	box(player, Vector3(0.25, 0.14, 0.4), Vector3(-0.52, -0.10, 0.14), CYAN)
	box(player, Vector3(0.25, 0.14, 0.4), Vector3(0.52, -0.10, 0.14), CYAN)
	shield = ring(self, PARRY_RADIUS, CYAN)
	shield.visible = false
	reticle = Node3D.new()
	add_child(reticle)
	for axis in [Vector3(0.26, 0, 0), Vector3(0, 0, 0.26)]:
		var dimensions := Vector3(0.15, 0.035, 0.044) if axis.x > 0 else Vector3(0.044, 0.035, 0.15)
		box(reticle, dimensions, axis, CYAN)
		box(reticle, dimensions, -axis, CYAN)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 23, 16)
	camera.look_at(Vector3(0, 0, 0.25))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21.5
	camera.current = true


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
	legend.text = "WASD   MOVE     /     MOUSE   AIM     /     CLICK   RETURN"
	bottom.add_child(legend)

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
	wave = 0
	health = 5
	score = 0
	combo = 0
	perfect_count = 0
	player.position = Vector3(0, HEIGHT, 5)
	parry_age = 1.0
	shield.hide()
	shield_meter.value = 1.0
	player_shell.show()
	cooldown = 0.0
	invulnerable = 0.0
	banner.hide()
	start_wave()


func start_wave() -> void:
	wave += 1
	state = State.BETWEEN
	delay = 1.2
	var positions: Array[Vector2] = [
		Vector2(0, -7), Vector2(-6, -4), Vector2(6, -4),
		Vector2(-7, 3), Vector2(7, 3)
	]
	for i in range(wave):
		var is_heavy := (wave >= 3 and i == 0) or (wave == 5 and i == 3)
		spawn_drone(positions[i], is_heavy, i)
	announce("WAVE %02d   /   %s" % [wave, WAVE_NAMES[wave - 1].to_upper()], 2.0)
	refresh_hud()


func spawn_drone(at: Vector2, heavy: bool, order: int) -> void:
	var drone := Drone.new()
	drone.node = Node3D.new()
	add_child(drone.node)
	drone.node.position = Vector3(at.x, HEIGHT, at.y)
	drone.heavy = heavy
	drone.hp = 3 if heavy else (1 if wave <= 2 else 2)
	drone.cooldown = 0.35 + order * 0.65
	var accent := GOLD if heavy else RED
	var width := 1.45 if heavy else 0.94
	box(drone.node, Vector3(width + 0.35, 0.035, width + 0.35), Vector3(0, -0.77, 0), Color("#442a42")).rotation.y = PI / 4
	box(drone.node, Vector3(width, 0.63, width * 0.92), Vector3.ZERO, Color("#51263f"))
	box(drone.node, Vector3(width * 0.66, 0.13, 0.25), Vector3(0, 0.37, -0.18), accent)
	box(drone.node, Vector3(width * 0.33, 0.29, 0.43), Vector3(0, -0.01, -width * 0.52), accent)
	drone.charge = ring(drone.node, width * 0.83, accent)
	drone.charge.position.y = -0.72
	drone.charge.hide()
	drones.append(drone)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				activate()
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
	cooldown = 0.50
	play_sound("parry", -16)


func toggle_pause() -> void:
	if state == State.PAUSED:
		state = resume_state
		banner.hide()
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
	camera.position.x = sin(beat * 87.0) * shake
	var origin := camera.project_ray_origin(get_viewport().get_mouse_position())
	var ray := camera.project_ray_normal(get_viewport().get_mouse_position())
	aim = origin + ray * ((HEIGHT - origin.y) / ray.y)
	reticle.position = Vector3(clampf(aim.x, -LIMIT, LIMIT), 0.08, clampf(aim.z, -LIMIT, LIMIT))
	reticle.visible = not banner.visible
	feedback_time = maxf(0, feedback_time - delta)
	if feedback_time == 0.0:
		feedback_label.text = ""
	if state in [State.BETWEEN, State.FIGHT]:
		move_player(delta)
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
	shield.visible = parry_age < 0.22
	shield.position = player.position + Vector3(0, -0.70, 0)
	shield_meter.value = 1.0 - cooldown / 0.50
	player_shell.visible = invulnerable <= 0.0 or int(beat * 26) % 2 == 0
	for drone in drones:
		var offset := player.position - drone.node.position
		if offset.length_squared() > 0.01:
			drone.node.rotation.y = atan2(-offset.x, -offset.z)
		drone.cooldown -= delta
		drone.charge.visible = drone.cooldown < 0.43
		drone.charge.scale = Vector3.ONE * (1.04 + sin(beat * 25.0) * 0.13)
		if drone.cooldown <= 0.0:
			fire(drone)
			drone.cooldown = 3.35 if drone.heavy else 2.15 - wave * 0.13

	for index in range(shots.size() - 1, -1, -1):
		step_shot(index, delta)
		if state == State.LOST:
			return
	if drones.is_empty():
		clear_shots()
		player_shell.show()
		shield.hide()
		play_sound("clear", -8)
		if wave == WAVE_NAMES.size():
			end_run(true)
		else:
			health = mini(5, health + 1)
			start_wave()


func move_player(delta: float) -> void:
	var direction := Vector3.ZERO
	direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	direction.x -= float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	direction.z = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	direction.z -= float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var next := player.position + direction.normalized() * 6.7 * delta
	next.x = clampf(next.x, -LIMIT, LIMIT)
	next.z = clampf(next.z, -LIMIT, LIMIT)
	for drone in drones:
		var offset := next - drone.node.position
		if offset.length_squared() < 1.45 and offset.length_squared() > 0.0001:
			next = drone.node.position + offset.normalized() * sqrt(1.45)
	player.position = next.clamp(Vector3(-LIMIT, HEIGHT, -LIMIT), Vector3(LIMIT, HEIGHT, LIMIT))
	var offset := aim - player.position
	if offset.length_squared() > 0.03:
		player.rotation.y = atan2(-offset.x, -offset.z)


func fire(drone: Drone) -> void:
	var direction := drone.node.position.direction_to(player.position)
	var shot := Shot.new()
	shot.heavy = drone.heavy
	shot.velocity = direction * (5.1 if shot.heavy else 7.0 + wave * 0.66)
	var color := GOLD if shot.heavy else RED
	shot.node = orb(self, 0.32 if shot.heavy else 0.19, drone.node.position + direction * 0.65, color)
	shot.trail = box(shot.node, Vector3(0.12, 0.12, 0.70), Vector3(0, 0, 0.57), color.darkened(0.28))
	shots.append(shot)
	play_sound("fire", -19)


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
		if parry_age < 0.22 and distance <= PARRY_RADIUS:
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
	if absf(to.x) > 11 or absf(to.z) > 11:
		if shot.returned and shot.heavy:
			blast(to, 2)
		remove_shot(index)


func segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var travel := to - from
	var fraction := clampf((point - from).dot(travel) / maxf(travel.length_squared(), 0.00001), 0.0, 1.0)
	return point.distance_to(from + travel * fraction)


func return_shot(shot: Shot, distance: float) -> void:
	shot.returned = true
	shot.perfect = distance < 1.29 and parry_age <= 0.105
	var direction := (aim - player.position).normalized()
	if direction.length_squared() < 0.001:
		direction = -shot.velocity.normalized()
	var best_alignment := 0.89 if assist else 0.98
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
		var save := ConfigFile.new()
		save.set_value("scores", "best", best)
		save.save("user://ricochet.cfg")
	refresh_hud()
	show_panel(
		"RUN COMPLETE" if won else "SHIELD BROKEN",
		"Score  %06d    /    Best  %06d\nPerfect returns  %d    /    Wave  %d of %d" % [score, best, perfect_count, wave, WAVE_NAMES.size()],
		"PLAY AGAIN"
	)


func remove_shot(index: int) -> void:
	shots[index].node.queue_free()
	shots.remove_at(index)


func clear_shots() -> void:
	for shot in shots:
		shot.node.queue_free()
	shots.clear()


func refresh_hud() -> void:
	stats.text = "SHIELD  %d/5     SCORE  %06d     BEST  %06d" % [health, score, maxi(score, best)]
	round_label.text = "WAVE  %02d / %02d   " % [wave, WAVE_NAMES.size()]


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

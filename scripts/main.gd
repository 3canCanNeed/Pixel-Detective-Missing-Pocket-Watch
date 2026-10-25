extends Node2D
# 《像素侦探：消失的怀表》主引擎
# 移动碰撞（网格 AABB）+ 对话/线索簿/指认 UI 全部代码构建
# 测试接口：current_map / flags / clues / collect_clue / resolve_accusation / _restart

const Case := preload("res://scripts/case.gd")
const T := 16
const SPEED := 90.0
const INTERACT_R := 20.0

const COL_BG := Color("0d1017")
const COL_PANEL := Color("161d2b")
const COL_TEXT := Color("d8dee9")
const COL_ACCENT := Color("ffd54f")
const COL_DIM := Color("6b7686")

var current_map := "street"
var map_rows: Array = []
var map_w := 0
var map_h := 0
var player: Node2D
var player_sprite: Sprite2D
var camera: Camera2D
var npc_nodes := {}          # id -> Node2D
var sparkle_nodes := {}      # id -> Node2D
var flags := {}              # 剧情旗标
var clues := []              # 已收集线索 id
var accused := false

# UI
var ui_layer: CanvasLayer
var ui_theme: Theme
var dialogue_panel: PanelContainer
var dialogue_text: RichTextLabel
var dialogue_choices: VBoxContainer
var dialogue_open := false
var typing := false
var _dlg_gen := 0      # 对话代际令牌：新对话使旧协程失效
var _skip_typing := false
var notebook_panel: PanelContainer
var notebook_list: RichTextLabel
var accuse_panel: PanelContainer
var accuse_stage := ""
var accuse_suspect := ""
var accuse_picked := []
var ending_panel: PanelContainer
var prompt_label: Label
var intro_panel: PanelContainer

# 雨
var rain_layer: CanvasLayer
var rain_drops := []
var time_acc := 0.0

var tex := {}                 # 贴图缓存


func _ready() -> void:
	_load_textures()
	_build_ui()
	_enter_map("street", Case.MAPS["street"]["spawn"]["x"], Case.MAPS["street"]["spawn"]["y"])
	_show_intro()


func _show_intro() -> void:
	intro_panel.visible = true


func _close_dialogue() -> void:
	_dlg_gen += 1
	typing = false
	dialogue_open = false
	dialogue_panel.visible = false


func _load_textures() -> void:
	for n in ["tile_road", "tile_sidewalk", "tile_wall", "tile_floor", "tile_counter",
			"tile_door", "tile_puddle", "tile_grass", "player_down", "player_up",
			"player_side", "npc_wang", "npc_chen", "npc_zhou", "npc_li", "sparkle"]:
		tex[n] = load("res://assets/%s.png" % n)


# ============ 地图 ============
func _tile_char(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return "#"
	return map_rows[y][x]


func _is_solid(x: int, y: int) -> bool:
	var ch := _tile_char(x, y)
	return ch == "#" or ch == "C"


func _enter_map(map_id: String, tx: int, ty: int) -> void:
	for c in get_children():
		if c.name != "UI":
			remove_child(c)
			c.queue_free()
	npc_nodes.clear()
	sparkle_nodes.clear()
	current_map = map_id
	var data: Dictionary = Case.MAPS[map_id]
	map_rows = data["rows"]
	map_w = map_rows[0].length()
	map_h = map_rows.size()

	var tiles := Node2D.new()
	tiles.name = "Tiles"
	tiles.set_script(load("res://scripts/tile_layer.gd"))
	tiles.main = self
	add_child(tiles)

	for npc in data.get("npcs", []):
		var n := Node2D.new()
		n.name = "NPC_" + npc["id"]
		n.position = Vector2(npc["x"] * T + 8, npc["y"] * T + 8)
		var s := Sprite2D.new()
		s.texture = tex[npc["sprite"]]
		s.scale = Vector2(1, 1)
		n.add_child(s)
		n.set_meta("npc_id", npc["id"])
		add_child(n)
		npc_nodes[npc["id"]] = n

	for sp in data.get("sparkles", []):
		if sp["clue"] in clues:
			continue
		var n2 := Node2D.new()
		n2.name = "SP_" + sp["id"]
		n2.position = Vector2(sp["x"] * T + 8, sp["y"] * T + 8)
		var s2 := Sprite2D.new()
		s2.texture = tex["sparkle"]
		n2.add_child(s2)
		n2.set_meta("spark_id", sp["id"])
		n2.set_meta("clue", sp["clue"])
		add_child(n2)
		sparkle_nodes[sp["id"]] = n2

	player = Node2D.new()
	player.name = "Player"
	player.position = Vector2(tx * T + 8, ty * T + 8)
	player_sprite = Sprite2D.new()
	player_sprite.texture = tex["player_down"]
	player.add_child(player_sprite)
	add_child(player)

	camera = Camera2D.new()
	# 自适应缩放：地图小于视口时缩小 zoom 让整图可见（避免黑边）
	var vp := get_viewport_rect().size
	var z: float = min(2.0, vp.x / (map_w * T), vp.y / (map_h * T))
	camera.zoom = Vector2(z, z)
	if map_w * T * z >= vp.x:
		camera.limit_left = 0
		camera.limit_right = map_w * T
	else:
		camera.limit_left = -100000000
		camera.limit_right = 100000000
	if map_h * T * z >= vp.y:
		camera.limit_top = 0
		camera.limit_bottom = map_h * T
	else:
		camera.limit_top = -100000000
		camera.limit_bottom = 100000000
	player.add_child(camera)
	camera.make_current()


func _physics_process(delta: float) -> void:
	if player == null or dialogue_open or _overlay_open() or notebook_panel.visible:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	var target := player.position + dir * SPEED * delta
	# 分轴移动 + 脚部 AABB 碰撞（脚部两点检测）
	var feet := [Vector2(-5, 4), Vector2(5, 4)]
	if dir.x != 0:
		var ok_x := true
		for f in feet:
			var px: float = target.x + f.x
			var py: float = player.position.y + f.y
			if _is_solid(int(px / T), int(py / T)):
				ok_x = false
		if ok_x:
			player.position.x = target.x
	if dir.y != 0:
		var ok_y := true
		for f in feet:
			var px2: float = player.position.x + f.x
			var py2: float = target.y + f.y
			if _is_solid(int(px2 / T), int(py2 / T)):
				ok_y = false
		if ok_y:
			player.position.y = target.y

	# 朝向贴图
	if dir.x > 0:
		player_sprite.texture = tex["player_side"]
		player_sprite.flip_h = false
	elif dir.x < 0:
		player_sprite.texture = tex["player_side"]
		player_sprite.flip_h = true
	elif dir.y > 0:
		player_sprite.texture = tex["player_down"]
		player_sprite.flip_h = false
	elif dir.y < 0:
		player_sprite.texture = tex["player_up"]

	# 摄像机跟随：地图小于视口时固定在地图中心
	var vw: float = get_viewport_rect().size.x / camera.zoom.x
	var vh: float = get_viewport_rect().size.y / camera.zoom.y
	player.position.x = clamp(player.position.x, 8, map_w * T - 8)
	player.position.y = clamp(player.position.y, 8, map_h * T - 8)
	if map_w * T <= vw or map_h * T <= vh:
		camera.position = Vector2(map_w * T / 2.0 - player.position.x, map_h * T / 2.0 - player.position.y)
	else:
		camera.position = Vector2.ZERO

	# 踩上门 → 切换地图
	var ti := wrap_i(int(player.position.x / T), int(player.position.y / T))
	for door in Case.MAPS[current_map].get("doors", []):
		if door["x"] == ti.x and door["y"] == ti.y:
			_enter_map(door["to"], door["tx"], door["ty"])
			return


func wrap_i(x: int, y: int) -> Vector2i:
	return Vector2i((x % map_w + map_w) % map_w, (y % map_h + map_h) % map_h)


func _on_dialogue_input(event: InputEvent) -> void:
	if typing and event is InputEventMouseButton and event.pressed:
		_skip_typing = true


# ============ 交互 ============
func nearest_interactable() -> Dictionary:
	var best := {}
	var best_d := INTERACT_R * INTERACT_R
	for id in sparkle_nodes:
		var n: Node2D = sparkle_nodes[id]
		var d: float = player.position.distance_squared_to(n.position)
		if d < best_d:
			best_d = d
			best = {"type": "sparkle", "id": id, "node": n}
	for id in npc_nodes:
		var n2: Node2D = npc_nodes[id]
		var d2: float = player.position.distance_squared_to(n2.position)
		if d2 < best_d:
			best_d = d2
			best = {"type": "npc", "id": id, "node": n2}
	return best


func interact() -> void:
	if dialogue_open or _overlay_open() or player == null:
		return
	var target := nearest_interactable()
	if target.is_empty():
		return
	if target["type"] == "sparkle":
		_collect_clue(target["node"].get_meta("clue"))
		sparkle_nodes[target["id"]].queue_free()
		sparkle_nodes.erase(target["id"])
	elif target["type"] == "npc":
		_talk(target["id"])


func _collect_clue(clue_id: String) -> void:
	if clue_id in clues:
		return
	clues.append(clue_id)
	var c: Dictionary = Case.CLUES[clue_id]
	_dialogue("侦探笔记", ["[color=#ffd54f][b]获得线索：%s[/b][/color]\n\n%s" % [c["name"], c["text"]]], [])


func _talk(npc_id: String) -> void:
	var data: Dictionary = Case.NPCS[npc_id]
	for entry in data["dialogues"]:
		var blocked := false
		for f in entry.get("not_flags", []):
			if flags.get(f, false):
				blocked = true
				break
		if blocked:
			continue
		_dialogue(npc_id, entry["lines"], entry.get("choices", []))
		return


func _apply_choice(choice: Dictionary) -> void:
	for f in choice.get("set", []):
		flags[f] = true
	if choice.has("give_clue"):
		_collect_clue(choice["give_clue"])
		return  # 线索弹窗已展示，不叠加对话
	if choice.has("accuse"):
		open_accusation()
		return
	if choice.has("lines"):
		_dialogue(_last_npc, choice["lines"], [])


var _last_npc := ""

# ============ 对话 UI ============
func _dialogue(speaker: String, lines: Array, choices: Array) -> void:
	_dlg_gen += 1
	var g := _dlg_gen
	dialogue_open = true
	typing = true
	_skip_typing = false
	_last_npc = speaker
	dialogue_panel.visible = true
	var full := ""
	for l in lines:
		full += l + "\n\n"
	dialogue_text.text = "[color=#ffd54f][b]" + speaker + "[/b][/color]\n\n" + full
	for c in dialogue_choices.get_children():
		c.queue_free()
	# 打字机
	dialogue_text.visible_characters = 0
	var total := dialogue_text.get_total_character_count()
	while dialogue_text.visible_characters < total:
		if g != _dlg_gen:
			return  # 已有新对话接管，旧协程立即退出
		if _skip_typing:
			break
		await get_tree().process_frame
		dialogue_text.visible_characters += 3
	if g != _dlg_gen:
		return
	dialogue_text.visible_characters = -1
	typing = false
	# 选项
	if choices.is_empty():
		_add_choice_button("离开", Callable())
	else:
		for ch in choices:
			var disabled := false
			var label: String = ch["t"]
			if ch.get("accuse", false):
				if clues.size() < Case.ACCUSATION["unlock_clues"]:
					disabled = true
					label += "  [线索不足 %d/%d]" % [clues.size(), Case.ACCUSATION["unlock_clues"]]
			_add_choice_button(label, Callable(self, "_apply_choice").bind(ch), disabled)


func _add_choice_button(label: String, action: Callable, disabled: bool = false) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = disabled
	btn.add_theme_font_size_override("font_size", 16)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("222c3f") if not disabled else Color("161c28")
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_disabled_color", COL_DIM)
	if action.is_valid():
		btn.pressed.connect(func():
			dialogue_panel.visible = false
			dialogue_open = false
			action.call())
	else:
		btn.pressed.connect(func():
			dialogue_panel.visible = false
			dialogue_open = false)
	dialogue_choices.add_child(btn)


# ============ 指认 ============
func open_accusation() -> void:
	accuse_panel.visible = true
	accuse_stage = "suspect"
	accuse_picked = []
	_render_accuse()


func _render_accuse() -> void:
	for c in accuse_panel.get_node("VBox/Body").get_children():
		c.queue_free()
	var body := accuse_panel.get_node("VBox/Body") as VBoxContainer
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", COL_ACCENT)
	body.add_child(title)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_DIM)
	body.add_child(hint)

	if accuse_stage == "suspect":
		title.text = "指出真凶"
		hint.text = "谁偷走了怀表？"
		for name in ["老周", "小陈", "王阿姨", "李先生"]:
			var b := Button.new()
			b.text = name
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func():
				accuse_suspect = name
				accuse_stage = "evidence"
				_render_accuse())
			body.add_child(b)
	elif accuse_stage == "evidence":
		title.text = "出示证据（选择两条）"
		hint.text = "已选 %d/2　嫌疑人：%s" % [accuse_picked.size(), accuse_suspect]
		for cid in clues:
			var c: Dictionary = Case.CLUES[cid]
			var b := Button.new()
			b.text = ("[√] " if cid in accuse_picked else "[　] ") + c["name"]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 15)
			b.pressed.connect(func():
				if cid in accuse_picked:
					accuse_picked.erase(cid)
				elif accuse_picked.size() < 2:
					accuse_picked.append(cid)
				_render_accuse())
			body.add_child(b)
		var confirm := Button.new()
		confirm.text = "确认指认"
		confirm.disabled = accuse_picked.size() != 2
		confirm.add_theme_font_size_override("font_size", 16)
		confirm.pressed.connect(func(): resolve_accusation(accuse_suspect, accuse_picked))
		body.add_child(confirm)
	var close := Button.new()
	close.text = "先不指认"
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func(): accuse_panel.visible = false)
	body.add_child(close)


func resolve_accusation(suspect: String, picked: Array) -> void:
	accused = true
	accuse_panel.visible = false
	var acc: Dictionary = Case.ACCUSATION
	var must_ok := true
	for e in acc["must_evidence"]:
		if not (e in picked):
			must_ok = false
	var any_ok := false
	for e in acc["any_evidence"]:
		if e in picked:
			any_ok = true
	if suspect == acc["culprit"] and must_ok and any_ok:
		_ending("good")
	elif suspect == acc["culprit"]:
		_ending("weak_evidence")
	else:
		_ending("wrong_suspect")


func _ending(kind: String) -> void:
	ending_panel.visible = true
	ending_panel.get_node("VBox/Text").text = Case.ENDINGS[kind]
	# 按钮随结局变化：好结局重开；错误结局可继续调查（保留线索进度）
	var old := ending_panel.get_node("VBox").get_child(ending_panel.get_node("VBox").get_child_count() - 1) as Button
	var vbx := ending_panel.get_node("VBox") as VBoxContainer
	if old:
		vbx.remove_child(old)
		old.queue_free()
	if kind == "good":
		_add_ending_button("重新开始", _restart)
	else:
		_add_ending_button("继续调查", func():
			ending_panel.visible = false)
		_add_ending_button("重新开始", _restart)


func _add_ending_button(label: String, action: Callable) -> void:
	var eb := Button.new()
	eb.text = label
	eb.pressed.connect(action)
	ending_panel.get_node("VBox").add_child(eb)


func _restart() -> void:
	flags = {}
	clues = []
	accused = false
	ending_panel.visible = false
	accuse_panel.visible = false
	dialogue_panel.visible = false
	dialogue_open = false
	_enter_map("street", Case.MAPS["street"]["spawn"]["x"], Case.MAPS["street"]["spawn"]["y"])
	_show_intro()


# ============ 输入 ============
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if ending_panel.visible or intro_panel.visible:
		return
	if accuse_panel.visible:
		if event.keycode == KEY_ESCAPE:
			accuse_panel.visible = false
		return
	if event.keycode == KEY_E and not dialogue_open and not _overlay_open() and not notebook_panel.visible:
		interact()
	elif event.keycode == KEY_N and not dialogue_open:
		notebook_panel.visible = not notebook_panel.visible
	elif event.keycode == KEY_ESCAPE:
		notebook_panel.visible = false
		if dialogue_open:
			_close_dialogue()


func _overlay_open() -> bool:
	return accuse_panel.visible or ending_panel.visible or intro_panel.visible


# ============ UI 构建 ============
func _build_ui() -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "sans-serif"])
	var th := Theme.new()
	th.default_font = sys_font
	th.default_font_size = 16
	ui_theme = th

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = COL_PANEL
	panel_sb.set_corner_radius_all(10)
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = Color("2a3a52")
	panel_sb.content_margin_left = 18
	panel_sb.content_margin_right = 18
	panel_sb.content_margin_top = 12
	panel_sb.content_margin_bottom = 12

	# 对话面板
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.visible = false
	dialogue_panel.add_theme_stylebox_override("panel", panel_sb)
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_left = 20
	dialogue_panel.offset_right = -20
	dialogue_panel.offset_top = -240
	dialogue_panel.offset_bottom = -16
	var dv := VBoxContainer.new()
	dialogue_panel.add_child(dv)
	dialogue_text = RichTextLabel.new()
	dialogue_text.bbcode_enabled = true
	dialogue_text.fit_content = true
	dialogue_text.scroll_active = false
	dv.add_child(dialogue_text)
	dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_choices = VBoxContainer.new()
	dialogue_choices.add_theme_constant_override("separation", 6)
	dv.add_child(dialogue_choices)
	dialogue_panel.gui_input.connect(_on_dialogue_input)
	ui_layer.add_child(dialogue_panel)

	# 线索簿
	notebook_panel = PanelContainer.new()
	notebook_panel.name = "NotebookPanel"
	notebook_panel.visible = false
	notebook_panel.add_theme_stylebox_override("panel", panel_sb)
	notebook_panel.set_anchors_preset(Control.PRESET_CENTER)
	notebook_panel.custom_minimum_size = Vector2(480, 360)
	var nv := VBoxContainer.new()
	notebook_panel.add_child(nv)
	var nt := Label.new()
	nt.text = "🔍 侦探笔记"
	nt.add_theme_font_size_override("font_size", 20)
	nt.add_theme_color_override("font_color", COL_ACCENT)
	nv.add_child(nt)
	notebook_list = RichTextLabel.new()
	notebook_list.bbcode_enabled = true
	notebook_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nv.add_child(notebook_list)
	var nb_hint := Label.new()
	nb_hint.text = "按 N 或 ESC 关闭"
	nb_hint.add_theme_font_size_override("font_size", 12)
	nb_hint.add_theme_color_override("font_color", COL_DIM)
	nv.add_child(nb_hint)
	ui_layer.add_child(notebook_panel)

	# 指认面板
	accuse_panel = PanelContainer.new()
	accuse_panel.name = "AccusePanel"
	accuse_panel.visible = false
	accuse_panel.add_theme_stylebox_override("panel", panel_sb)
	accuse_panel.set_anchors_preset(Control.PRESET_CENTER)
	accuse_panel.custom_minimum_size = Vector2(420, 420)
	var av := VBoxContainer.new()
	av.name = "VBox"
	accuse_panel.add_child(av)
	var abody := VBoxContainer.new()
	abody.name = "Body"
	abody.add_theme_constant_override("separation", 8)
	av.add_child(abody)
	ui_layer.add_child(accuse_panel)

	# 结局面板
	ending_panel = PanelContainer.new()
	ending_panel.name = "EndingPanel"
	ending_panel.visible = false
	ending_panel.add_theme_stylebox_override("panel", panel_sb)
	ending_panel.set_anchors_preset(Control.PRESET_CENTER)
	ending_panel.custom_minimum_size = Vector2(560, 420)
	var ev := VBoxContainer.new()
	ev.name = "VBox"
	ending_panel.add_child(ev)
	var et := RichTextLabel.new()
	et.name = "Text"
	et.bbcode_enabled = true
	et.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ev.add_child(et)
	var eb := Button.new()
	eb.text = "重新开始"
	eb.pressed.connect(_restart)
	ev.add_child(eb)
	ui_layer.add_child(ending_panel)

	# 开场说明
	intro_panel = PanelContainer.new()
	intro_panel.name = "IntroPanel"
	intro_panel.add_theme_stylebox_override("panel", panel_sb)
	intro_panel.set_anchors_preset(Control.PRESET_CENTER)
	intro_panel.custom_minimum_size = Vector2(560, 320)
	var iv := VBoxContainer.new()
	intro_panel.add_child(iv)
	var it := RichTextLabel.new()
	it.bbcode_enabled = true
	it.text = Case.INTRO
	it.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(it)
	var ib := Button.new()
	ib.text = "开始调查"
	ib.pressed.connect(func(): intro_panel.visible = false)
	iv.add_child(ib)
	ui_layer.add_child(intro_panel)

	# 交互提示
	prompt_label = Label.new()
	prompt_label.text = ""
	prompt_label.add_theme_font_size_override("font_size", 13)
	prompt_label.add_theme_color_override("font_color", COL_ACCENT)
	prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_label.offset_left = 24
	prompt_label.offset_top = -30
	prompt_label.theme = ui_theme
	ui_layer.add_child(prompt_label)

	# 主题挂到每个根 Control（CanvasLayer 不传播主题）
	for root_ctl in [dialogue_panel, notebook_panel, accuse_panel, ending_panel, intro_panel, prompt_label]:
		root_ctl.theme = ui_theme

	# 雨
	rain_layer = CanvasLayer.new()
	rain_layer.name = "Rain"
	rain_layer.layer = 5
	add_child(rain_layer)
	var rain_ctl := Control.new()
	rain_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	rain_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain_ctl.set_script(load("res://scripts/rain.gd"))
	rain_layer.add_child(rain_ctl)


func _process(_delta: float) -> void:
	if player == null or notebook_panel == null:
		return
	# 交互提示
	var target := nearest_interactable()
	if target.is_empty():
		prompt_label.text = ""
	else:
		var verb := "交谈" if target["type"] == "npc" else "调查"
		var name2: String = target["id"] if target["type"] == "npc" \
			else Case.CLUES[target["node"].get_meta("clue")]["name"]
		prompt_label.text = "[E] %s · %s　　[N] 笔记（%d 条线索）" % [verb, name2, clues.size()]
	# 线索簿内容
	if notebook_panel.visible:
		var txt := ""
		if clues.is_empty():
			txt = "[i]（还没有收集任何线索）[/i]"
		else:
			for cid in clues:
				var c: Dictionary = Case.CLUES[cid]
				txt += "[color=#ffd54f][b]· %s[/b][/color]\n%s\n\n" % [c["name"], c["text"]]
		notebook_list.text = txt

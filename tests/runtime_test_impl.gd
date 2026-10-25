# 运行时测试：实例化主场景，直接调用引擎接口走完取证与指认全流程
extends Node

var main: Node2D
var passed := 0
var failed := 0
var frame := 0
var _last_logged := -1
var _t0 := 0
var steps: Array = []
var step_idx := 0


func _ready() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_parent().add_child.call_deferred(main)
	_t0 = Time.get_ticks_msec()
	steps = _build_steps()
	print("TEST_READY: 步骤数 %d" % steps.size())


func _build_steps() -> Array:
	# 依次收集全部 6 条线索（各线索的地图与坐标来自 case.gd 的闪光点）
	return [
		{"do": "wait_ready"},
		{"do": "assert_map", "id": "street"},
		# --- 走位踩门传送：从 shop 门口向下一格踩门应回到 street ---
		{"do": "goto_map", "map": "shop", "tx": 11, "ty": 13, "rain": false},
		{"do": "teleport", "x": 11, "y": 13},
		{"do": "hold_move", "key": KEY_S, "frames": 30},
		{"do": "assert_map", "id": "street"},
		# --- NPC 阻挡：按住 A 向小陈走，不应穿过 ---
		{"do": "goto_map", "map": "street", "tx": 7, "ty": 7, "rain": true},
		{"do": "teleport", "x": 7, "y": 7},
		{"do": "hold_move", "key": KEY_A, "frames": 30},
		{"do": "assert_min_x", "min": 100},
		{"do": "key_release", "key": KEY_A},
		{"do": "goto_map", "map": "street", "tx": 2, "ty": 6, "rain": true},
		# --- 老周对话取证链路（按钮 → give_clue）---
		{"do": "goto_map", "map": "shop", "tx": 11, "ty": 13, "rain": false},
		{"do": "talk", "npc": "老周", "pick": 0, "give_clue": "clue_lock"},
		{"do": "assert_flag", "k": "met_zhou", "v": true},
		{"do": "talk", "npc": "老周", "pick": 0, "give_clue": "clue_lock"},
		{"do": "talk", "npc": "老周", "pick": 1, "give_clue": "clue_ledger"},
		# 商店: 虚掩的柜门 + 台账
		{"do": "goto_map", "map": "shop", "tx": 11, "ty": 13, "rain": false},
		{"do": "collect", "clue": "clue_lock", "at": Vector2(4, 3)},
		{"do": "collect", "clue": "clue_ledger", "at": Vector2(18, 3)},
		# 街道: 湿脚印 + 目击
		{"do": "goto_map", "map": "street", "tx": 2, "ty": 6, "rain": true},
		{"do": "collect", "clue": "clue_prints", "at": Vector2(6, 9)},
		{"do": "talk", "npc": "李先生", "give_clue": "clue_witness"},
		# 楼道: 扫帚 + 当票
		{"do": "goto_map", "map": "stairwell", "tx": 8, "ty": 14, "rain": false},
		{"do": "collect", "clue": "clue_broom", "at": Vector2(14, 2)},
		{"do": "collect", "clue": "clue_pawn", "at": Vector2(14, 15)},
		{"do": "talk_pick", "npc": "王阿姨", "pick": 0, "flag": "wang_confronted"},
		{"do": "assert_flag", "k": "wang_confronted", "v": true},
		{"do": "assert_clues", "n": 6},
		# 错误指认（错误嫌疑人）→ 可继续游戏
		{"do": "accuse", "suspect": "小陈", "evidence": ["clue_pawn", "clue_broom"], "expect": "wrong_suspect"},
		{"do": "accuse", "suspect": "王阿姨", "evidence": ["clue_broom", "clue_prints"], "expect": "weak_evidence"},
		# 正确指认
		{"do": "accuse", "suspect": "王阿姨", "evidence": ["clue_pawn", "clue_broom"], "expect": "good"},
		{"do": "restart_check"},
		{"do": "done"},
	]


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _t0 > 120000:
		printerr("TIMEOUT at step %d" % step_idx)
		get_tree().quit(1)
		return
	if step_idx >= steps.size():
		return
	var s: Dictionary = steps[step_idx]
	if step_idx != _last_logged:
		_last_logged = step_idx
		print("STEP %d: %s" % [step_idx, str(s)])
	match s.get("do"):
		"wait_ready":
			if main != null and is_instance_valid(main) and main.player != null:
				print("READY: 场景已实例化（关闭开场说明）")
				main.intro_panel.visible = false
				step_idx += 1
		"assert_map":
			if main.current_map == s["id"]:
				_pass("当前地图 " + s["id"])
			else:
				_fail("期望地图 %s 实际 %s" % [s["id"], main.current_map])
			step_idx += 1
		"goto_map":
			# 直接调用引擎切图（等价于走门）
			if main.current_map != s["map"]:
				main._enter_map(s["map"], s["tx"], s["ty"])
			if main.current_map == s["map"]:
				if s.has("rain") and main.rain_layer.visible != s["rain"]:
					_fail("%s 雨天显示错误: 期望%s" % [s["map"], str(s["rain"])])
				else:
					if s.has("rain"):
						_pass("切图 %s 雨天=%s" % [s["map"], str(main.rain_layer.visible)])
				step_idx += 1
		"collect":
			if main.dialogue_open:
				main.dialogue_panel.visible = false
				main.dialogue_open = false
			# 把玩家移到线索旁并收集
			main.player.position = Vector2(s["at"].x * 16 + 8, s["at"].y * 16 + 8 + 2)
			var clue: String = s["clue"]
			if clue in main.clues:
				_pass("已收集(重复调用安全): " + clue)
				step_idx += 1
				return
			main._collect_clue(clue)
			if clue in main.clues:
				_pass("收集线索 " + clue)
				step_idx += 1
			else:
				_fail("收集失败: " + clue)
		"talk":
			if s["give_clue"] in main.clues:
				_pass("对话获得线索 " + str(s["give_clue"]))
				main._close_dialogue()
				step_idx += 1
				return
			if main.typing:
				return  # 打字机进行中，等下一帧（不消耗尝试次数）
			s["_tries"] = s.get("_tries", 0) + 1
			if s["_tries"] > 10:
				_fail("对话未给出线索 " + str(s["give_clue"]) + "（尝试10轮）")
				step_idx += 1
				return
			if main.dialogue_open and main.dialogue_choices.get_child_count() > 0:
				# 点击指定序号的选项
				var idx: int = s.get("pick", 0)
				var btn := main.dialogue_choices.get_child(idx) as Button
				if btn.disabled:
					_fail("选项被禁用: " + btn.text)
					step_idx += 1
					return
				main.dialogue_panel.visible = false
				main.dialogue_open = false
				btn.pressed.emit()
			elif not main.dialogue_open:
				main._talk(s["npc"])
		"assert_clues":
			if main.clues.size() == s["n"]:
				_pass("线索总数 = %d" % s["n"])
			else:
				_fail("线索数期望 %d 实际 %d" % [s["n"], main.clues.size()])
			step_idx += 1
		"accuse":
			if main.dialogue_open:
				main.dialogue_panel.visible = false
				main.dialogue_open = false
			main.resolve_accusation(s["suspect"], s["evidence"])
			var shown: bool = main.ending_panel.visible
			var text: String = main.ending_panel.get_node("VBox/Text").text
			var kind_ok := false
			var vbx: VBoxContainer = main.ending_panel.get_node("VBox")
			var want: String = "重新开始" if s["expect"] == "good" else "继续调查"
			var btn_found: Button = null
			for c in vbx.get_children():
				if c is Button and c.text == want:
					btn_found = c
			if s["expect"] == "good":
				kind_ok = shown and text.begins_with("[b]真相大白") and btn_found != null
			elif s["expect"] == "wrong_suspect":
				kind_ok = shown and "指认错误" in text and btn_found != null
			elif s["expect"] == "weak_evidence":
				kind_ok = shown and "证据不足" in text and btn_found != null
			if kind_ok:
				_pass("指认 %s → %s（按钮=%s）" % [s["suspect"], s["expect"], want])
			else:
				_fail("指认 %s 期望 %s, shown=%s 找到按钮=%s" % [s["suspect"], s["expect"], str(shown), str(btn_found != null)])
			# 非 good 结局：点[继续调查]后应保留全部线索并可继续指认
			if s["expect"] != "good":
				btn_found.pressed.emit()
				if main.ending_panel.visible or main.clues.size() != 6:
					_fail("继续调查后状态异常: 面板=%s 线索数=%d" % [str(main.ending_panel.visible), main.clues.size()])
			step_idx += 1
		"talk_pick":
			if main.flags.get(s["flag"], false) and not main.dialogue_open:
				_pass("对质旗标 %s 已设置" % s["flag"])
				step_idx += 1
				return
			if main.typing:
				return
			if main.dialogue_open and main.dialogue_choices.get_child_count() > 0:
				var pidx: int = s["pick"]
				var pbtn := main.dialogue_choices.get_child(pidx) as Button
				main.dialogue_panel.visible = false
				main.dialogue_open = false
				pbtn.pressed.emit()
			elif not main.dialogue_open:
				main._talk(s["npc"])
		"assert_flag":
			if main.flags.get(s["k"], false) == s["v"]:
				_pass("旗标 %s = %s" % [s["k"], str(s["v"])])
			else:
				_fail("旗标 %s 期望 %s 实际 %s" % [s["k"], str(s["v"]), str(main.flags.get(s["k"]))])
			step_idx += 1
		"restart_check":
			main._restart()
			var rs_ok: bool = main.current_map == "street" and main.clues.size() == 0 and main.intro_panel.visible
			if rs_ok:
				_pass("重开流程: 地图/线索/开场说明 全部复位")
			else:
				_fail("重开异常: map=%s clues=%d intro=%s" % [main.current_map, main.clues.size(), str(main.intro_panel.visible)])
			main.intro_panel.visible = false
			step_idx += 1
		"teleport":
			main.player.position = Vector2(s["x"] * 16 + 8, s["y"] * 16 + 8)
			step_idx += 1
		"hold_move":
			if s.get("_f", 0) == 0:
				var ev := InputEventKey.new()
				ev.keycode = s["key"]
				ev.physical_keycode = s["key"]
				ev.pressed = true
				Input.parse_input_event(ev)
			s["_f"] = s.get("_f", 0) + 1
			if s["_f"] >= s["frames"]:
				var ev2 := InputEventKey.new()
				ev2.keycode = s["key"]
				ev2.physical_keycode = s["key"]
				ev2.pressed = false
				Input.parse_input_event(ev2)
				step_idx += 1
		"key_release":
			var ev3 := InputEventKey.new()
			ev3.keycode = s["key"]
			ev3.physical_keycode = s["key"]
			ev3.pressed = false
			Input.parse_input_event(ev3)
			step_idx += 1
		"assert_min_x":
			if main.player.position.x >= s["min"]:
				_pass("NPC 阻挡生效: x=%.1f >= %d" % [main.player.position.x, s["min"]])
			else:
				_fail("穿模! x=%.1f < %d" % [main.player.position.x, s["min"]])
			step_idx += 1
		"done":
			print("RUNTIME_TEST_RESULT: %d 通过 / %d 失败" % [passed, failed])
			get_tree().quit(1 if failed > 0 else 0)
			s["_q"] = s.get("_q", 0) + 1
			if s["_q"] > 240:  # ~4s 后强制结束
				OS.kill(OS.get_process_id())
			step_idx += 1 if s["_q"] <= 1 else 0


func _pass(msg: String) -> void:
	passed += 1
	print("  ✓ " + msg)


func _fail(msg: String) -> void:
	failed += 1
	printerr("  ✗ " + msg)

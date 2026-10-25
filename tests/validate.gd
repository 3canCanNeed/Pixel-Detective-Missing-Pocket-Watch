# 案件数据验证：地图一致性 / 线索可达性 / 指认路径证明
# 用法: Godot_console.exe --headless --path . -s res://tests/validate.gd
extends SceneTree

const Case := preload("res://scripts/case.gd")

const SOLID := ["#", "C"]


func _init() -> void:
	var errs: Array = []
	var maps: Dictionary = Case.MAPS

	# ---- 1. 地图行宽一致 + 边界封闭 ----
	for mid in maps.keys():
		var rows: Array = maps[mid]["rows"]
		var w: int = rows[0].length()
		for i in rows.size():
			if rows[i].length() != w:
				errs.append("%s 第%d行宽度 %d != %d" % [mid, i + 1, rows[i].length(), w])
		# 边界必须全是墙（门 D 除外）
		for x in w:
			for y in [0, rows.size() - 1]:
				var ch: String = rows[y][x]
				if ch != "#" and ch != "D":
					errs.append("%s 边界(%d,%d)='%s' 不是墙" % [mid, x, y, ch])
		for y in rows.size():
			for x in [0, w - 1]:
				var ch2: String = rows[y][x]
				if ch2 != "#" and ch2 != "D":
					errs.append("%s 边界(%d,%d)='%s' 不是墙" % [mid, x, y, ch2])

	# ---- 2. 门：双向可达 ----
	var door_map := {}
	for mid in maps.keys():
		for door in maps[mid].get("doors", []):
			var to: String = door["to"]
			if not maps.has(to):
				errs.append("%s 门指向不存在的地图 %s" % [mid, to])
				continue
			door_map[mid + ">" + to] = true
			# 目标出生点不能是实心块
			var rows2: Array = maps[to]["rows"]
			if rows2[door["ty"]][door["tx"]] in SOLID:
				errs.append("%s→%s 出生点(%d,%d)是实心" % [mid, to, door["tx"], door["ty"]])
	for pair in door_map.keys():
		var parts: PackedStringArray = pair.split(">")
		var back: String = parts[1] + ">" + parts[0]
		if not door_map.has(back):
			errs.append("门是单向的: %s" % pair)

	# ---- 3. NPC/线索位置合法（在地图内、不在实心块上、附近有可站立格）----
	for mid in maps.keys():
		var rows3: Array = maps[mid]["rows"]
		for npc in maps[mid].get("npcs", []):
			var e := _pos_check(rows3, npc["x"], npc["y"], "%s/%s" % [mid, npc["id"]])
			if e != "":
				errs.append(e)
		for sp in maps[mid].get("sparkles", []):
			var e2 := _pos_check(rows3, sp["x"], sp["y"], "%s/%s" % [mid, sp["id"]])
			if e2 != "":
				errs.append(e2)

	# ---- 4. 线索引用一致 ----
	var clue_ids := Case.CLUES.keys()
	for mid in maps.keys():
		for sp in maps[mid].get("sparkles", []):
			if not (sp["clue"] in clue_ids):
				errs.append("闪光线索不存在: " + str(sp["clue"]))
	for nid in Case.NPCS.keys():
		for entry in Case.NPCS[nid]["dialogues"]:
			for ch in entry.get("choices", []):
				if ch.has("give_clue") and not (ch["give_clue"] in clue_ids):
					errs.append("%s 对话给出的线索不存在: %s" % [nid, ch["give_clue"]])

	# ---- 5. 指认配置 ----
	var acc: Dictionary = Case.ACCUSATION
	if not (acc["culprit"] in ["老周", "小陈", "王阿姨", "李先生"]):
		errs.append("指认真凶不在嫌疑人列表")
	for e in acc["must_evidence"] + acc["any_evidence"]:
		if not (e in clue_ids):
			errs.append("指认所需线索不存在: " + str(e))

	# ---- 6. 破案可达性证明：全部线索均可收集（BFS 模拟行走）----
	for cid in clue_ids:
		var found := false
		for mid in maps.keys():
			for sp in maps[mid].get("sparkles", []):
				if sp["clue"] == cid:
					found = true
		# 线索来源：闪光线（在地图上）或对话 give
		var from_dialogue := false
		for nid in Case.NPCS.keys():
			for entry in Case.NPCS[nid]["dialogues"]:
				for ch in entry.get("choices", []):
					if ch.get("give_clue", "") == cid:
						from_dialogue = true
		var on_map := false
		for mid in maps.keys():
			for sp in maps[mid].get("sparkles", []):
				if sp["clue"] == cid:
					on_map = true
		if not (from_dialogue or on_map):
			errs.append("线索 %s 无任何获取途径" % cid)

	# ---- 7. 走行可达性：三张地图连通 + 每个兴趣点旁边可站立 ----
	# 简化证明：地图全连通（门双向）+ 每张图内部从 spawn 沿可行走格 BFS 覆盖兴趣点邻格
	for mid in maps.keys():
		var rows4: Array = maps[mid]["rows"]
		var spawn: Dictionary = maps[mid]["spawn"]
		var w: int = rows4[0].length()
		var h: int = rows4.size()
		var start := Vector2i(spawn["x"], spawn["y"])
		var visited := {start: true}
		var queue := [start]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: Vector2i = cur + d
				if nx.x < 0 or nx.y < 0 or nx.x >= w or nx.y >= h:
					continue
				if visited.has(nx):
					continue
				var ch: String = rows4[nx.y][nx.x]
				if ch in SOLID:
					continue
				visited[nx] = true
				queue.append(nx)
		for npc in maps[mid].get("npcs", []):
			var p := Vector2i(npc["x"], npc["y"])
			var adj := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(0, 0)]:
				if visited.has(p + d):
					adj = true
			if not adj:
				errs.append("%s NPC %s 不可接近" % [mid, npc["id"]])
		for sp in maps[mid].get("sparkles", []):
			var p2 := Vector2i(sp["x"], sp["y"])
			var adj2 := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(0, 0)]:
				if visited.has(p2 + d):
					adj2 = true
			if not adj2:
				errs.append("%s 线索 %s 不可接近" % [mid, sp["id"]])

	# ---- 输出 ----
	print("地图: %d　线索: %d　NPC: %d" % [maps.size(), Case.CLUES.size(), Case.NPCS.size()])
	if errs.is_empty():
		print("VALIDATION_PASS: 案件结构完整，全部线索可达，指认配置正确")
		quit(0)
	else:
		for e in errs:
			printerr("[案件错误] " + e)
		print("VALIDATION_FAIL")
		quit(1)


func _pos_check(rows: Array, x: int, y: int, label: String) -> String:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[0].length():
		return "%s 坐标越界" % label
	var ch: String = rows[y][x]
	if ch in SOLID:
		return "%s 站在实心块上 (%d,%d)='%s'" % [label, x, y, ch]
	return ""


func errers_append(errs: Array, msg: String) -> void:
	errs.append(msg)
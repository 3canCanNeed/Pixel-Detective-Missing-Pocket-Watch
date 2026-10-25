extends Control
# 雨夜效果：斜向雨丝 + 微风摆动

var drops := []
var t := 0.0


func _ready() -> void:
	for i in range(90):
		drops.append({
			"x": randf() * 1200,
			"y": randf() * 700,
			"len": randf_range(10, 22),
			"spd": randf_range(420, 640),
			"a": randf_range(0.10, 0.26),
		})


func _process(delta: float) -> void:
	t += delta
	for d in drops:
		d["y"] += d["spd"] * delta
		d["x"] += d["spd"] * 0.12 * delta
		if d["y"] > 660:
			d["y"] = -20
			d["x"] = randf() * 1200
	queue_redraw()


func _draw() -> void:
	for d in drops:
		var p := Vector2(d["x"], d["y"])
		var v: Vector2 = Vector2(0.12, 1).normalized() * d["len"]
		draw_line(p, p + v, Color(0.6, 0.7, 0.9, d["a"]), 1.0)

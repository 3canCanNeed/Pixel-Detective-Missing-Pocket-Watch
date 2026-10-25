extends Node2D
# 地图块绘制层：main 每帧引用 main.map_rows 绘制一次静态地图

var main: Node2D

const TILE_TEX := {
	"#": "tile_wall", "_": "tile_floor", "C": "tile_counter",
	"D": "tile_door", ",": "tile_sidewalk", "G": "tile_grass",
}
const BASE_ROAD := "tile_road"


func _draw() -> void:
	if main == null:
		return
	var rows: Array = main.map_rows
	var tex: Dictionary = main.tex
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var pos := Vector2(x * 16, y * 16)
			# 基础块
			var base: String = TILE_TEX.get(ch, BASE_ROAD)
			draw_texture(tex[base], pos)
			# 叠加：水洼画在路面/人行道上
			if ch == "~":
				draw_texture(tex["tile_puddle"], pos)

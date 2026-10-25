# 像素侦探：消失的怀表（Godot 4 探案游戏）

像素风顶视角探案冒险游戏。雨夜，钟表铺的红宝石怀表失窃——走访四名嫌疑人、收集六条线索、在侦探笔记里拼出证据链，然后指出真凶。

## 运行

1. 打开 Godot 4（本机：`D:\coc\Godot_v4.7.2-stable_win64.exe`）
2. 「导入」→ 选择本文件夹的 `project.godot`
3. 按 **F5** 开始

## 玩法

| 按键 | 功能 |
|---|---|
| WASD / 方向键 | 移动 |
| E | 交谈 / 调查发光点 |
| N | 侦探笔记（已收集线索） |
| ESC | 关闭窗口面板 |

收集 **3 条线索**后，回到钟表铺找老周可解锁"指出真凶"。指认时需要选对嫌疑人并出示 **2 条证据**——证据链不对，对方会矢口否认。

- **3 张地图**（雨夜街道 / 二楼钟表铺 / 一楼楼道），门相互连通
- **4 名嫌疑人**，各有证词与说谎点
- **6 条线索**（虚掩的柜门 / 修表台账 / 湿脚印 / 雨夜目击 / 揉皱的当票 / 铺子里的扫帚）
- **3 种结局**：真相大白 / 证据不足 / 指认错误
- 全部美术为脚本程序生成的 16×16 像素贴图（`tools/gen_assets.py`），雨夜氛围为代码绘制

## 工程结构

```
project.godot            工程配置
scenes/main.tscn         主场景（根 Node2D + 脚本）
scripts/main.gd          引擎：地图构建/移动碰撞/对话/线索簿/指认/结局
scripts/case.gd          案件数据：地图ASCII/对话树/线索/指认（改内容只动这个文件）
scripts/tile_layer.gd    地图块绘制层
scripts/rain.gd          雨夜效果
tools/gen_assets.py      像素贴图生成器（PIL）
tests/validate.gd        案件验证：地图/线索/NPC/门/指认配置 + 可达性
tests/runtime_test.gd    运行时自动化测试（取证→指认全流程 11 项断言）
```

## 测试（全绿交付）

```
# 案件验证
Godot_console.exe --headless --path . -s res://tests/validate.gd
# 运行时用例（约 30 秒）
Godot_console.exe --headless --path . -s res://tests/runtime_test.gd
```

最近一次结果：验证 PASS；运行时 **11/11 通过**（6 线索收集、对话取证、错误指认/证据不足/正确指认三分支）；冒烟运行 0 脚本错误。

## License

MIT

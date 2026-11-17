extends StaticBody3D
## Interaction hotspot on the RV (seat, stove, fridge, hood...).

var rv: Node
var action := ""
var highlight_root: Node3D
var _hl := false

func aim_name() -> String:
	return {"fridge": "Fridge door", "cabinet": "Pantry cupboard", "overhead": "Overhead cupboard"}.get(action, action.replace("_", " ").capitalize()) if highlight_root else ""

func set_highlight(on: bool) -> void:
	if on == _hl:
		return
	_hl = on
	if is_instance_valid(highlight_root):
		Items.set_outline(highlight_root, on)


func get_prompt() -> String:
	return rv.prompt_for(action)

func interact(player: Node) -> void:
	rv.do_action(action, player)

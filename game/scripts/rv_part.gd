extends StaticBody3D
## Interaction hotspot on the RV (seat, stove, fridge, hood...).

var rv: Node
var action := ""

func get_prompt() -> String:
	return rv.prompt_for(action)

func interact(player: Node) -> void:
	rv.do_action(action, player)

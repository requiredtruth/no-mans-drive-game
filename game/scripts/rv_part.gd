extends StaticBody3D
## Interaction hotspot on the RV (seat, stove, fridge, hood...).

var rv: Node
var action := ""

func get_prompt() -> String:
	return rv.prompt_for(action)

func interact(player: Node) -> void:
	rv.do_action(action, player)

func transfer_info() -> Dictionary:
	return rv.transfer_info(action) if rv.has_method("transfer_info") else {}

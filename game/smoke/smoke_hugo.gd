extends Node
## Scripted capture of Hugo's sprite inside the forge (--smoke-script=hugo; run it through `grimoire heavy` with the
## engine's --always-on-top): scenario forge_upgrades, Hugo walks into the forge and forges a sword at the anvil; with
## the job under way the game pauses and the interior is shot at camera zoom 2 and zoom 1:
## reports/shots/hugo_forja_z<zoom>[_<tag>].png (--shot-tag=<tag>, e.g. antes / despues). Made to compare two
## versions of the same sprite with the same camera. Quits when done, or after `timeout` seconds.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 90.0
var tag: String = ""
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot-tag="):
			tag = a.substr(11)
	if OS.is_debug_build():
		print("[SmokeHugo] start (tag=%s)" % tag)


func _go(step: String) -> void:
	if OS.is_debug_build():
		print("[SmokeHugo] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _zoom(z: int) -> void:
	var iv: Node = app.interior()
	iv.set("_zoom", z)
	var cam: Camera2D = iv.camera()
	cam.zoom = Vector2.ONE * z
	cam.position = iv.call("_camera_position")


func _shot(zoom: int) -> void:
	app.save_shot("hugo_forja_z%d%s" % [zoom, ("_" + tag) if tag != "" else ""])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeHugo] TIMEOUT in step %s" % _step)
		get_tree().quit(1)
		return
	var card: Node = app.get_node_or_null("CardsLayer/EventCard")
	if card != null and card is CanvasItem and (card as CanvasItem).visible:
		card.call("close")  # a fiesta's herald or an event card over the room: not what is compared
	match _step:
		"start":
			if _t > 0.5:
				var r := NewGame.from_scenario("forge_upgrades")
				r["state"].characters[HUGO]["position"] = r["state"].buildings[BLD]["door"]
				r["state"].characters[HUGO]["path"] = []
				r["state"].buildings[BLD]["queue"]["entries"] = []
				Game.start(r["state"])
				app.world().select(HUGO)
				app.world().command_enter(BLD)
				_go("entering")
		"entering":
			if str(Game.sim.state.characters[HUGO]["location"]) == BLD and app.interior_building == BLD and _t > 0.6:
				app.interior().open_station_menu("anvil", app.interior().station_screen("anvil"))
				app.interior().station_menu().choose_mode("normal")
				app.interior().station_menu().choose_recipe("forge_sword")
				_go("forging")
		"forging":
			var job := Production.job_view(Game.sim, BLD, "anvil")
			if not job.is_empty() and float(job.get("progress", 0.0)) >= 0.15:
				Game.set_paused(true)
				_zoom(2)
				_go("z2")
		"z2":
			if _t > 0.8:
				_shot(2)
				_zoom(1)
				_go("z1")
		"z1":
			if _t > 0.8:
				_shot(1)
				_go("done")
				print("[SmokeHugo] done")
				get_tree().quit(0)

extends "res://game/smoke/smoke_economia.gd"
## The forge end to end in the 3D town (--smoke-script=forja3d, docs/3d/plan.md M3D-4; through `grimoire heavy` with
## --always-on-top): smoke_economia's whole run (a real new game as the blacksmith: the station's menu, the bar and the
## master touch, production with two employees, the storage, buying and selling at the Resources stall, the book's
## debts and paying, hiring and firing, the upgrade tree, a build and its works) played over the 3D town with the forge
## open in place and today's UI, its checks included. Shots: reports/shots/forja3d_<shot>.png.


func _init() -> void:
	shot_prefix = "forja3d_"

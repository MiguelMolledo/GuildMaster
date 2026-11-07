extends PenLook
## H12 Patrón (04d 4.22.4.2): the cattle fair of the plaza: a small fenced pen with two sheep and a pig (the greybox
## of PenLook at half size) until its PixelLab art (4.22.9 #4).


func _ready() -> void:
	scale = Vector2(0.55, 0.55)
	herd = {"sheep": 2, "pig": 1}
	queue_redraw()

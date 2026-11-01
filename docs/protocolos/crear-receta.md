# Crear una receta

1. `python3 tools/new_content.py receta --id <edificio>_<producto> --en "<Name>" --es "<Nombre>"`
2. Rellena `data/recipes/<id>.json`: `building` y `zone` (un puesto que exista en ese edificio), `inputs`, `output`,
   `duration_hours` (**horas de juego**, nunca segundos), `min_craft` (1-10) y, si hace falta, `requires_upgrade`.
3. Comprueba que el precio de la salida compensa las entradas y la duración (los bots lo medirán en H3).
4. Rituales: `python3 tools/validate_content.py` · pruebas de reglas · `sim_runner` si cambia la economía.

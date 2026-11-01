# Generar arte con PixelLab (vía PixelLab Pip)

Solo con encargo del owner: generar gasta créditos. Pip (plugin de Claude Code, instalado en este repo con
`.claude/settings.json`) elige la herramienta de PixelLab, enseña el plan y el coste antes de gastar y revisa animaciones.

## Antes de pedir nada
1. El asset está en `assets/inventario.json` con su tipo, tamaño y animaciones (si no, añádelo en `falta`).
2. La petición se escribe contra `docs/style/biblia.md`. Pip lee además `pixellab-pip-style.json` (estilo `guildmaster`,
   activo); si cambia la biblia, se actualiza también ese perfil:
   `python <skill>/assets/project_style.py save guildmaster --from <estilo.json> --replace --use --profile pixellab-pip-style.json`.
3. Apunta el saldo antes en `assets/art/MANIFEST.md` (`get_balance`, gratis).

## Generar
- Invoca `/pixellab-pip <petición>`. Modo «auto» apagado: Pip enseña cada llamada, el texto exacto y el coste estimado y
  espera el sí. Para tandas grandes, con tope: `/pixellab-pip auto plan <generaciones> <reintentos> <petición>`.
- Las descargas en bruto caen en `pixellab-pip-generations/<tanda>/` (fuera de git y de Godot), con su registro de
  trabajos, semilla y coste.

## Revisar (gratis, local)
Python de los ayudantes: `~/.pixellab-pip-venv/bin/python` (Pillow 13, NumPy, SciPy). `<skill>` =
`~/.claude/plugins/cache/pixellab-pip-plugins/pixellab-pip/<versión>/skills/pixellab-pip`.
- Animaciones: `<py> <skill>/assets/fix.py <frames...> --move walk --check-only --out <dir>` → `fix_report.txt`.
  Un veredicto «ready» no basta: mira los frames con la lista `look` del informe. Las reparaciones locales (sin
  `--check-only`) se hacen sobre copias y solo si se aceptan.
- Mira cada imagen contra la biblia: perspectiva 2:1, contorno negro, paleta, tamaño, nada de texto.

## Promover al juego
1. Copia lo aprobado a su ruta de `docs/ASSETS.md` dentro de `assets/art/`.
2. Animaciones: hoja + `SpriteFrames` de Godot por animación y dirección:
   `<py> <skill>/assets/make_sheet.py assets/art/<ruta>/<anim>_<dir> <frames...> --fps 8 [--loop] --godot assets/art/<ruta>`
   (`--godot` va **sin** `res://`: el script lo añade).
3. Sube el estado en `assets/inventario.json` (`sprite` / `animado`) y guarda el id de PixelLab del personaje.
4. Apunta el saldo después en `assets/art/MANIFEST.md`.
5. Rituales: `python3 tools/arte.py`, `godot --headless --path . --import`, `python3 tools/cuaderno.py`.

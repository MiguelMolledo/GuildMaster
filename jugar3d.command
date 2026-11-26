#!/bin/zsh
# Doble clic para jugar a GuildMaster en 3D (rama 3d), tal como está ahora en esta carpeta.
# jugar.command (la última versión sellada en tmp/jugar/) todavía no copia el kit 3D, que está fuera de git.
# Opciones: ./jugar3d.command --view=2d  (la vista 2D de antes, para comparar)
cd "$(dirname "$0")" || exit 1
[[ -d kit ]] || { echo "Falta el kit 3D: python3 tools/kit3d/kit.py instalar"; exit 1; }
exec /opt/homebrew/bin/godot --path . -- "$@"

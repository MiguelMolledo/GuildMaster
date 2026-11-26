#!/bin/zsh
# Doble clic para jugar a GuildMaster: la última versión sellada en git (copia en tmp/jugar/<commit>, con el kit 3D
# enlazado), no lo que esté a medias. Abre el pueblo en 3D (data/view.json view_mode); --view=2d para el de antes.
# Lo que esté sin sellar se prueba con jugar3d.command (o /opt/homebrew/bin/godot --path <esta carpeta>).
cd "$(dirname "$0")" || exit 1
snap=$(tools/preparar_jugar.sh) || exit 1
touch $snap/.en_uso.$$
[[ "$1" == "--" ]] && shift
if [[ ! -e $snap/kit ]]; then  # the 3D kit is out of git: without it, the 2D view of before
  echo "Falta el kit 3D (python3 tools/kit3d/kit.py instalar): se abre la vista 2D" >&2
  set -- --view=2d "$@"
fi
exec /opt/homebrew/bin/godot --path $snap -- "$@"

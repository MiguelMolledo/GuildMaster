#!/bin/zsh
# Doble clic para jugar a GuildMaster: la última versión sellada en git (copia en tmp/jugar/<commit>), no lo que esté a
# medias. Lo que esté sin sellar se prueba con: /opt/homebrew/bin/godot --path ~/Code/GuildMaster
cd "$(dirname "$0")" || exit 1
snap=$(tools/preparar_jugar.sh) || exit 1
touch $snap/.en_uso.$$
[[ "$1" == "--" ]] && shift
exec /opt/homebrew/bin/godot --path $snap -- "$@"

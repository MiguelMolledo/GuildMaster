#!/bin/zsh
# Prepara la copia jugable de la última versión sellada en git: tmp/jugar/<commit>, la que arranca jugar.command.
# Escribe su ruta en la salida. Si ya está lista, no hace nada. La lanza el hook post-commit en segundo plano.
# Cada versión va en su carpeta; se quedan las 5 más nuevas y las que estén en uso (marcador .en_uso.<pid> vivo).
# La copia guarda en su propia carpeta de usuario («GuildMaster (jugar)»), que ninguna prueba toca.
# El kit 3D (kit/, fuera de git) se enlaza desde esta carpeta y la importación parte de la caché de aquí.
cd "$(dirname "$0")/.." || exit 1
JUGAR_DIR="GuildMaster (jugar)"
head=$(git rev-parse --short=12 HEAD) || exit 1
snap=tmp/jugar/$head
if [[ ! -f $snap/.lista ]]; then
  lock=tmp/jugar/.$head.lock
  mkdir -p tmp/jugar
  if mkdir $lock 2>/dev/null; then
    trap "rmdir $lock 2>/dev/null" EXIT
    echo "Preparando la versión ${head:0:7}…" >&2
    rm -rf $snap && mkdir -p $snap && git archive HEAD | tar -x -C $snap
    sed -i '' "s|^config/custom_user_dir_name=.*|config/custom_user_dir_name=\"$JUGAR_DIR\"|" $snap/project.godot
    if [[ -d kit ]]; then
      # the 3D kit is out of git (docs/3d/plan.md §5): linked, not copied; the import starts from this folder's own
      # imported files (APFS clones: no extra disk) and only redoes what changed (Godot compares each source's md5)
      ln -s "$PWD/kit" $snap/kit
      mkdir -p $snap/.godot && cp -cR .godot/imported $snap/.godot/ 2>/dev/null
    else
      echo "Sin kit 3D en $PWD/kit: la copia solo podrá jugar en 2D (python3 tools/kit3d/kit.py instalar)" >&2
    fi
    mkdir -p tmp/jugar/.home
    for _ in 1 2; do  # the first import creates the translations; the second one leaves everything in place
      env HOME=$PWD/tmp/jugar/.home /opt/homebrew/bin/godot --headless --path $snap --import >/dev/null 2>&1
    done
    touch $snap/.lista
  else
    echo "Terminando de preparar la versión ${head:0:7}…" >&2
    while [[ -d $lock ]]; do sleep 1; done
  fi
fi
for old in $(ls -1dt tmp/jugar/*/ 2>/dev/null | tail -n +6); do
  old=${old%/}
  [[ $old == $snap ]] && continue
  in_use=0
  for mark in $old/.en_uso.*(N); do
    if kill -0 ${mark##*.} 2>/dev/null; then in_use=1; else rm -f $mark; fi
  done
  (( in_use )) || rm -rf $old
done
echo $snap

#!/bin/zsh
# Arranque sin ventana (ritual de CLAUDE.md) con cada variante: sale con 0 y sin ERROR ni SCRIPT ERROR.
#   zsh tools/qa/boot_check.sh [otra-variante …]     (sale con 1 si alguna falla; HOME de pruebas en tmp/boot_check)
# Cada escenario de data/scenarios/ es una variante (--scenario=<id>). Cada opción va en su propio argumento.
cd "$(dirname "$0")/../.." || exit 1
godot=/opt/homebrew/bin/godot
home=$PWD/tmp/boot_check
mkdir -p $home
variants=("" "--dev-time" "--start-city=capital")
for f in data/scenarios/*.json(N); do
  [[ ${f:t} == _* ]] || variants+=("--scenario=${f:t:r}")
done
variants+=("$@")
failed=0
for v in "${variants[@]}"; do
  args=(${(z)v})
  out=$(env HOME=$home $godot --headless --path . --quit-after 120 -- "${args[@]}" 2>&1)
  code=$?
  errors=$(print -r -- "$out" | grep -c "ERROR")
  if (( code == 0 && errors == 0 )); then
    print "  ok    [${v:-sin opciones}]"
  else
    print "  FALLA [${v:-sin opciones}] sale con $code, $errors ERROR"
    print -r -- "$out" | grep -m 3 "ERROR" | sed 's/^/        /'
    failed=1
  fi
done
(( failed )) && print "boot_check: algo falla" || print "boot_check: todo bien"
exit $failed

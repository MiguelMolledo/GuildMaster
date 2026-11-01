# GuildMaster

Simulador de vida y dinastía medieval en pixel art isométrico (Godot 4.7.2). Llegas como un don nadie a una ciudad del
siglo XIV y, generación tras generación, levantas negocios, formas una familia, subes en la escala social y te enfrentas
a familias rivales y a los tribunales.

- Diseño: [`docs/gdd/`](docs/gdd/README.md)
- Reglas para trabajar en el repo (también para agentes): [`CLAUDE.md`](CLAUDE.md)
- Estado: [`docs/hitos.json`](docs/hitos.json) · decisiones: [`docs/decisiones.json`](docs/decisiones.json) ·
  arte: [`assets/inventario.json`](assets/inventario.json) · estilo: [`docs/style/biblia.md`](docs/style/biblia.md)

## Arrancar

```sh
/opt/homebrew/bin/godot --headless --path . --import      # la primera vez (genera las traducciones)
/opt/homebrew/bin/godot --path .                          # jugar lo que hay en el árbol
./jugar.command                                           # jugar la última versión sellada
python3 tools/qa/run_all.py                               # todos los rituales sin ventana
```

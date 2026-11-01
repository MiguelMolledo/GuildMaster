# Contrato de assets

Qué se pide a cada asset para que el juego lo cargue sin tocar código. El estado de cada uno vive en
`assets/inventario.json`; `python3 tools/arte.py --falta` lo compara con este contrato y con el contenido de `data/`.

## Escala de estados

| Estado | Arte | Qué significa |
|---|---|---|
| `falta` | — | No hay nada en este repo (puede haber algo en el repo `guild`: campo `origen_previo`). |
| `greybox` | placeholder | Forma y tamaño correctos, dibujado en código o con un rectángulo/diamante de color y su etiqueta. Sirve para jugar. |
| `concepto` | fal.ai | Hay una imagen de referencia aprobada (no es un sprite del juego). |
| `sprite` | estático | Sprite final o casi, sin animar (o asset que no se anima: tiles, iconos, props quietos). |
| `animado` | animado | Todas las animaciones que pide su tipo, en todas sus direcciones. |
| `final` | integrado | Revisado (`frame_check`), en el juego, con capturas mirándolo en su sitio. |

Audio: `falta` → `provisional` (placeholder o librería) → `generado` (ElevenLabs/Suno/fal) → `final` (niveles revisados, integrado).

Un asset que no se anima pasa de `sprite` a `final` directamente.

## Por tipo

| Tipo | Tamaño | Direcciones | Animaciones | Ruta |
|---|---|---|---|---|
| personaje (controlable) | 48 px de alto, pies en el centro inferior | 8 (`s se e ne n nw w sw`; `w nw sw` pueden ser espejo) | idle, walk, work, carry, talk, sit, death | `assets/art/characters/<id>/<anim>_<dir>.png` (tira horizontal) |
| npc | 48 px | 8 | idle, walk, talk, sit (+ work, carry si trabaja) | `assets/art/npcs/<id>/…` |
| edificio | 192 px de ancho base (escala según D2) | 1 (vista fija) | — (variantes: normal, obras, dañado) | `assets/art/buildings/<id>.png` + `<id>_construction.png` + `<id>_damaged.png` |
| interior | kit modular: suelo, paredes, muebles por puesto | 1 | — | `assets/art/interiors/<edificio>/` |
| tile | diamante 64×32 | — | — | `assets/art/tiles/<id>.png` |
| prop | libre, pies marcados | 1 | opcional (`loop`) | `assets/art/props/<id>.png` |
| icono | 32×32 | — | — | `assets/art/icons/<item_id>.png` |
| ui | 9-patch o pieza suelta | — | — | `assets/art/ui/…` |
| vfx | libre | — | `loop` o `once` | `assets/art/vfx/<id>/` |
| retrato | 64×64 | — | — | `assets/art/portraits/<id>.png` |

- Ancla de los pies: el punto de apoyo va en el centro inferior del fotograma; la ficha visual puede corregirlo con `feet: [x, y]`.
- Fondo transparente, sin halo; contorno negro de un color; filtro `Nearest`.
- Identidad de familia: los personajes se variarán por paleta (pelo, piel, ropa con el color de la familia). Los sprites se
  dibujan con colores clave fáciles de sustituir (ver la biblia de estilo).

## Al generar o traer un asset

1. Mira su entrada en `assets/inventario.json` (si no existe, créala con estado `falta`).
2. Genera o trae el asset a su ruta; apunta `origen` (id de PixelLab o prompt de fal) y `coste_gen`.
3. Apunta el gasto en `assets/art/MANIFEST.md` (saldo antes y después).
4. Sube el estado y pasa `python3 tools/arte.py` (0 errores).

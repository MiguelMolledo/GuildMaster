# Contrato de assets

Qué se pide a cada asset para que el juego lo cargue sin tocar código. El estado de cada uno vive en
`assets/inventario.json`; `python3 tools/arte.py --falta` lo compara con este contrato y con el contenido de `data/`.
Cómo cambiarlos a mano en Godot: `docs/protocolos/editar-a-mano.md`.

## Ids, escenas y ficheros

- **`data/` guarda ids y cifras, nunca rutas.** El validador rechaza `res://`, `assets/`, `.png`, `.ogg`… en `data/`.
- **Cada cosa visible tiene su escena** `game/visuals/<tipo>/<id>.tscn` (`buildings`, `interiors`, `stations`, `props`,
  `characters`), con un `Marker2D` `Feet` (punto de apoyo) y otro `Top` (altura: letrero, barra, nombre, clic). El
  greybox vive dentro (`Greybox`) hasta que llega el sprite; el sprite se pone en la escena, con su textura arrastrada
  en el editor (Godot guarda la referencia por uid). Sin escena, sale `<tipo>/_generic.tscn`.
- **Los ficheros se llaman como su id**, en minúsculas y snake_case, en su carpeta por tipo (tabla de abajo). La
  conversión id → ruta está solo en `game/visuals/visual_paths.gd`. Personajes: `<rol>_<m|f>` con rol `artisan`
  (familia del jugador o rival), `worker` (empleado) o `townsfolk`; sus fotogramas, en `<id>_frames.tres` (SpriteFrames).
- **Audio**: `assets/audio/<music|sfx|ambient|voice>/<id>.ogg|wav` (variantes `<id>_01`, `<id>_02`…), con el id
  declarado en `data/audio.json` (bus, volumen, variación de tono). OGG para música y sonidos largos (bucle en Import),
  WAV para efectos cortos. Buses fijos en `default_bus_layout.tres`: Master, Music, Sfx, Ambient, Voice, Ui.
- **Mover o renombrar, solo en Godot.** Los `.import` y `.uid` van a git. Todas las `.tscn`/`.tres` llevan uid
  (`python3 tools/uids.py [--fix]`).
- El validador da **error** si un asset del inventario en estado `sprite` o más (audio: `generado` o más) no tiene su
  fichero con las mayúsculas exactas, o si un nombre de `assets/art/`, `assets/audio/` o `game/visuals/` lleva mayúsculas.

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
| icono pequeño (listas de la UI) | 16×16 | — | — | `assets/art/icons/small/<item_id>.png` (se deriva del de 32 con `tools/art/derivar_guild.py`) |
| ui | 9-patch o pieza suelta | — | — | `assets/art/ui/…` |
| vfx | libre | — | `loop` o `once` | `assets/art/vfx/<id>/` |
| retrato | 64×64 (busto) y 32×32 (cara) | — | — | `assets/art/portraits/<tipo>.png` y `<tipo>_32.png`: un retrato por tipo de personaje (grupo, etapa, sexo), con fondo transparente y los colores clave codificados como los personajes (se pintan con `identity_swap.gdshader`). Lista y criterio en `assets/art/fal_produccion/LEEME.md` |
| ilustración (ui) | 240×135 (libro y cartas), 192×108 (aviso, `<id>_192.png`), pantallas 960×540 (480×270 ×2) | — | — | `assets/art/illustrations/<id>.png`: `event_<evento>`, `season_<estación>`, `card_<carta>`, `screen_<pantalla>` |

- Ancla de los pies: el punto de apoyo va en el centro inferior del fotograma; se ajusta en su escena visual moviendo el
  sprite (Offset) sobre el `Marker2D` `Feet`.
- Fondo transparente, sin halo; contorno negro de un color; filtro `Nearest`.
- Identidad de familia: los personajes se variarán por paleta (pelo, piel, ropa con el color de la familia). Los sprites se
  dibujan con colores clave fáciles de sustituir (ver la biblia de estilo).

## Al generar o traer un asset

1. Mira su entrada en `assets/inventario.json` (si no existe, créala con estado `falta`).
2. Genera o trae el asset a su ruta; apunta `origen` (id de PixelLab o prompt de fal) y `coste_gen`.
3. Apunta el gasto en `assets/art/MANIFEST.md` (saldo antes y después).
4. Sube el estado y pasa `python3 tools/arte.py` (0 errores).

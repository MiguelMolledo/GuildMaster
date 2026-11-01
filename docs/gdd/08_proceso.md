## 8. Proceso de desarrollo con agentes

### 8.1 Cuaderno vivo (diario de desarrollo)

Igual que en Wizards Broke It:

- **`docs/novedades.json`**: cada función terminada añade una entrada **al principio** con `fecha`, `titulo`, `que`, `como_probar` y `capturas` (capturas reales del juego sacadas con `--smoke`, en `docs/novedades/`). **Sin entrada con capturas, la función no está entregada.**
- **`docs/decisiones.json`**: `tomadas` (`fecha`, `tema`, `decision`, `por_que`), `pendientes` y `proximos_pasos`. Cualquier cambio de reglas, datos, controles o decisiones lo actualiza.
- **`python3 tools/cuaderno.py`** regenera la página "Guild Renew · cuaderno del juego" en Grimoire con novedades, decisiones, controles, estado de los hitos (`docs/hitos.json`) y lo que falta de arte (`assets/inventario.json`). Dónde se lleva cada cosa: 8.5.
- **`docs/paginas.json`** registra los ids de todas las páginas/artifacts del proyecto (`tools/paginas.py --check`).
- La **crónica** del juego (4.14) es otra cosa: es el diario de la partida, no del desarrollo.

### 8.2 Colas de trabajo: manager y subgrims

- El hilo principal de Grimoire ("Guild Renew · dirección") es el **manager**: planifica el hito, lo parte en encargos y los delega en **subgrims** (`grimoire cmd orchestrate.delegate`), luego `orchestrate.wait` / `orchestrate.result`.
- Cada encargo lleva: objetivo, **su zona de ficheros** (para no pisarse), qué secciones de este documento leer, criterio de "hecho", rituales que debe pasar y su entrada del cuaderno.
- **Como mucho 4 subgrims a la vez** (máquina de 16 GB).
- Los subgrims **no hacen commit ni push**: tocan solo su zona, ponen sus pruebas en `tests/test_<zona>_*.gd` y su entrada en `reports/novedades/<zona>.json`. Los errores de otra zona se apuntan en el informe, no se arreglan.
- El manager revisa (pruebas, capturas, simulaciones), integra, **sella** (commit), hace push y avisa al owner por Telegram.
- **Cola de procesos pesados:** todo lo que abra ventana, exporte o lance Playwright va con `grimoire heavy -- <comando>` (uno a la vez en la máquina; `--timeout 3m` para pasadas con ventana). Nunca `pkill -f` con patrones generales: solo los PID propios.
- **Copia jugable:** un hook post-commit (`tools/git-hooks/post-commit` → `tools/preparar_jugar.sh`) prepara `tmp/jugar/<commit>`; el owner juega con doble clic en `jugar.command`. Su guardado vive en una carpeta propia que ninguna prueba toca.

### 8.3 Protocolos de contenido

`docs/protocolos/` con un paso a paso por tipo de contenido, como en Wizards: `crear-objeto.md`, `crear-receta.md`, `crear-edificio.md` (ficha + huella + interior + sprite + mejoras), `crear-mejora.md`, `crear-profesion.md`, `crear-evento.md`, `crear-cargo.md`, `crear-npc.md`, `crear-mapa.md` (sustituye a `howto-level-design.md`). Cada protocolo termina con los rituales que hay que pasar.

### 8.4 Pipeline de arte y audio con IA

| Uso | Herramienta | Cómo |
|---|---|---|
| Concepto y exploración de estilo | **fal.ai** (Nano Banana para iterar, Nano Banana Pro para lo serio; FLUX descartado) | `tools/art/style_explore.py` → tablero de comparación en Grimoire. No son sprites del juego. |
| Personajes (8 direcciones + animaciones) | **PixelLab** (`create_character`, `animate_character`, `animate_with_skeleton_v3`) | Ver `.claude/commands/generar-asset.md` del proyecto actual: 48 px, `low top-down`, contorno negro, sombreado medio. Animaciones base: idle, walk, work, forge, death (+ talk, carry, sit). **Un sprite base por clase y género**, con los **colores clave** de pelo, piel y ropa (9.6) para la variación por paleta. |
| Variación de personajes y retratos (4.10.9) | Shader de intercambio de paleta en `game/` + `reduce_colors` de PixelLab para fijar los colores clave | 0 generaciones extra. `frame_check.py` comprueba que cada sprite usa exactamente los colores clave reservados. |
| Edificios | **PixelLab** `create_map_object` (1 gen por objeto) o, para variedad, `create_building_kit` (10-25 gen por kit; piezas modulares de muros, tejados, puertas) | Ver sección 9. |
| Interiores | **PixelLab**: kit modular de interior (suelos, paredes, mobiliario genérico) + puestos por oficio + mejoras visuales genéricas reutilizables | Ver 4.6.4 y el presupuesto de 9.3. |
| Suelos | **PixelLab** `create_tiles_pro` / `create_isometric_tile` / `create_path_tiles` (caminos) | Diamante 64×32. Los mapas de PixelLab no admiten 64×32 plano: se montan en Godot. |
| Props y efectos | `create_map_object`; **gratis**: `pixelart_workbench` y `vfx_workbench` | Luces, humo de la forja, chispas, emoji de estados. |
| Iconos de objetos y UI | fal.ai + pixelado local (como `tools/art/cards_build.py` de Wizards) o PixelLab `create_ui_asset` | 32×32 (iconos), marcos 9-patch. |
| Retratos | PixelLab `create_portrait_character` | Para HUD, árbol genealógico, contratación. |
| Voces de NPC | **ElevenLabs** (TTS; perfiles por clase social: noble, artesano, pícaro, cura, mercader) | `scripts/tools/generate_voice.py` actual → `tools/audio/`. Ladridos cortos ("¡Buen acero!", saludos), no diálogo completo. |
| Música | **ElevenLabs Music** (decisión de Wizards del 2026-10-21); si el owner hace pistas en Suno con los prompts de `data/music.json`, las sustituyen | Temas: ciudad de día, mercado, noche, taberna, tensión, tribunal. Bucles con `tools/audio/make_loop.py`. |
| Efectos de sonido | fal.ai Stable Audio (`generate_audio.py` actual) o ElevenLabs SFX | Martillo, fuelle, monedas, puertas, pasos, campanas. Niveles con `tools/audio/sfx_batch.py check`. |
| Comprobación de arte | `assets/art/_tools/frame_check.py`, `stabilize.py`, `preview.py` (copiar de Wizards) | Nada se integra con veredicto `error`. Hoja de contacto en `assets/art/_preview.png`. |

**Reglas de créditos** (copiadas de Wizards):
- `.env` fuera de git con `FAL_KEY` y `ELEVENLABS_API_KEY`. Nunca imprimir ni subir claves.
- Cada encargo que gaste mide el saldo **antes y después** (`mcp__pixellab__get_balance`) y lo apunta en `assets/art/MANIFEST.md` (tabla de gasto) y `assets/audio/MANIFEST.md`; el coste de cada asset va además en su registro de `assets/inventario.json` (8.5).
- Ojo (comprobado el 2026-10-31): con las generaciones del plan a 0, PixelLab cobra **del crédito en $ antes que del regalo diario**. No lanzar trabajos de pago si no se quiere gastar dinero. Gratis: `pixelart_workbench`, `vfx_workbench`, `search_help`, `get_*`, `list_*`.
- Plan actual: Tier 1, 2.000 generaciones/mes, se renueva el **2026-11-15**.
- El contrato de assets vive en `docs/ASSETS.md` (tiras `<id>_<anim>_<dir>.png`, punto de apoyo de los pies, direcciones `s se e ne n nw w sw`) y el estado de cada asset en `assets/inventario.json` (8.5).

**Activos reutilizables del primer intento:** ~1.260 fotogramas de las 4 clases en ambos géneros (`assets/sprites/characters/`), ~440 de NPC, 77 de edificios (forja, mercado, residencias, overlays), 95 tiles, 106 de UI, 35 iconos, props (barril, banco, carro, saco, pozo), conceptos y paletas (`assets/concept/`). Se copian al repo nuevo, se renombran al contrato de `ASSETS.md` y se registran en `assets/inventario.json` antes de generar nada nuevo.

### 8.5 Registro del proyecto

Dónde se lleva cada cosa. Cada fichero tiene un único dueño de verdad: no se repite el estado en otro sitio (L10).

| Qué | Dónde | Contenido |
|---|---|---|
| Estado de los hitos | `docs/hitos.json` | Cada hito (sección 10) y cada criterio de aceptación con su estado (**pendiente / en curso / hecho**), fecha y prueba (test, informe de bots, captura). |
| Diario de desarrollo | `docs/novedades.json` | Ver 8.1. |
| Decisiones | `docs/decisiones.json` | Ver 8.1. Recoge las de la sección 12 y las que vengan. |
| Perfil estético | `docs/style/biblia.md` | Paleta, tamaños, perspectiva, contorno, referencias, prompts base, colores clave de personaje (4.10.9). |
| Contrato de assets | `docs/ASSETS.md` | Nombres, tamaños, direcciones y animaciones que pide cada tipo de asset. |
| Inventario de assets | `assets/inventario.json` | Un registro por asset: estado, qué hito o entidad lo necesita, animaciones pedidas y hechas, origen (id de PixelLab, prompt de fal) y coste. |

**Escala de estado de un asset** en `assets/inventario.json`:

- Arte: `falta → greybox → concepto → sprite → animado → final`.
- Audio: `falta → provisional → generado → final`.

`tools/arte.py` valida el inventario contra `docs/ASSETS.md` (nombres, tamaños, animaciones pedidas) y saca la lista de lo que falta por hito; el cuaderno (8.1) la enseña.

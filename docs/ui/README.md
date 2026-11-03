# Diseño de interfaz · índice

Cómo se ve y se usa cada pantalla de GuildMaster, en pixel art a 960×540 lógicos (×2 entero a 1080p). Es diseño:
aquí no se implementa nada. Cada documento sigue la [plantilla de 10 puntos](_plantilla.md) y sus maquetas se hacen
con el kit real (`tools/ui/maqueta.py`, ver [tools/ui/README.md](../../tools/ui/README.md)).

> [!NOTE]
> Orden de autoridad: 00 (lenguaje visual) y 01 (HUD) mandan sobre las convenciones de `mecanicas/_comun.md` y
> `mecanicas/_social.md`; esas mandan sobre cada documento de mecánica. Solo el worker «kit» edita este índice.

## Documentos

| # | Documento | Qué cubre | Dueño | Estado |
|---|---|---|---|---|
| — | [_plantilla.md](_plantilla.md) | Los 10 puntos de cada documento | kit | hecho |
| 00 | [00_lenguaje_visual.md](00_lenguaje_visual.md) | Rejilla, tokens de color, marcos, estados, tipografía, iconos, animación, cursor, sonidos de UI | kit | borrador |
| 01 | [01_hud.md](01_hud.md) | Interfaz general en mapa e interior: zonas, prioridades y solapes, avisos, tooltips, modales, objetivos y F1, familiares, reloj, teclas | kit | borrador |
| 02 | [02_menu_inicial.md](02_menu_inicial.md) | Título, partida nueva, cargar/guardar, opciones, créditos, salir, fin de partida | kit | borrador |
| 03 | [03_produccion_sin_creditos.md](03_produccion_sin_creditos.md) | Cómo se hace la UI sin créditos, lista de la compra de PixelLab (15-nov), cómo editar piezas en Godot | kit | borrador |

### Mecánicas · economía (worker «mecánicas-economía»)

Convenciones comunes: [mecanicas/_comun.md](mecanicas/_comun.md).

| Documento | Qué cubre | Estado |
|---|---|---|
| [forja_interior.md](mecanicas/forja_interior.md) | Interior, menú de puesto, órdenes, rutina | en curso |
| [produccion.md](mecanicas/produccion.md) | Cola de producción y recetas | en curso |
| [almacen_y_personaje.md](mecanicas/almacen_y_personaje.md) | Almacén del edificio, inventario y equipo del personaje | en curso |
| [mercado_y_libro.md](mecanicas/mercado_y_libro.md) | Mercado, mostrador, libro de cuentas y deuda | en curso |
| [empleados.md](mecanicas/empleados.md) | Contratar, plantilla, rangos, lealtad | en curso |
| [mejoras.md](mecanicas/mejoras.md) | Árbol de mejoras y obras | en curso |
| [parcelas_y_construccion.md](mecanicas/parcelas_y_construccion.md) | Modo construcción, parcelas, obra | en curso |

### Mecánicas · social (worker «mecánicas-social»)

Convenciones comunes: [mecanicas/_social.md](mecanicas/_social.md).

| Documento | Qué cubre | Estado |
|---|---|---|
| [ciudad_viva.md](mecanicas/ciudad_viva.md) | Ficha de vecino, tablón, microeventos, burbujas | en curso |
| [familia.md](mecanicas/familia.md) | Árbol, retratos, herencia | en curso |
| [cortejo_y_boda.md](mecanicas/cortejo_y_boda.md) | Cortejo y boda | en curso |
| [titulos_y_reputacion.md](mecanicas/titulos_y_reputacion.md) | Títulos, reputación, ceremonia | en curso |
| [cargos_y_elecciones.md](mecanicas/cargos_y_elecciones.md) | Organigrama, campaña, votación, poderes | en curso |
| [tribunal.md](mecanicas/tribunal.md) | Juicios | en curso |
| [rivales.md](mecanicas/rivales.md) | Familias rivales, ataques, avisos | en curso |

## Maquetas

- PNG en [maquetas/](maquetas/): `<id>.png` (960×540) y `<id>_x2.png` (1920×1080).
- La fuente de cada maqueta (`.json` o `.py`) va en `maquetas/src/`, para que se pueda regenerar cuando cambie una
  pieza: `python3 tools/ui/maqueta.py docs/ui/maquetas/src/<doc>.py`.
- Para montar una pantalla sobre el HUD propuesto: `docs/ui/maquetas/src/hud.py` (`ficha()`, `barra_estado()`, `reloj()`,
  `objetivo()`, `lateral()`, `seleccion()`, `avisos()`; zonas en `hud.ZONAS`).
- Fondos del juego sin HUD: `maquetas/fondos/` (se regeneran con `tools/ui/captura_fondos.tscn`).
- Las capturas del juego de hoy que ilustran un documento se llaman `<documento>_hoy_<qué>.png`.
- Ejemplo con todos los tipos de elemento: `maquetas/_ejemplo.png` (fuente: `tools/ui/ejemplos/ejemplo.json`).

## Herramientas y piezas

| Qué | Dónde |
|---|---|
| Maquetas | `tools/ui/maqueta.py` · `tools/ui/tokens.json` (colores, fuentes, medidas) |
| Piezas del kit (9-patch) | `tools/art/dibujar_ui.py` → `assets/art/ui/theme/` (márgenes en `PIECES`) |
| Fuentes | `assets/art/ui/fonts/` (cada una con su licencia al lado) · `tools/ui/glifos_extra.py` |
| Theme del juego | `game/ui/greybox_theme.tres` (uno solo, en la raíz del HUD y en todos los paneles) |
| Iconos | `assets/art/icons/` (juego) · `~/Code/guild/assets/sprites/ui/` (Guild Renew, solo lectura) |

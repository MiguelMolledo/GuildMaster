# tools/ui · maquetas con el kit real

`maqueta.py` compone maquetas de 960×540 (y `_x2` a 1080p) con las piezas del juego: 9-patch de `assets/art/ui/theme/`
(márgenes en `PIECES` de `tools/art/dibujar_ui.py`), fuentes de `assets/art/ui/fonts/` y colores y medidas de
`tokens.json`. Si una pieza cambia, la maqueta cambia al regenerarla.

- Uso: `python3 tools/ui/maqueta.py docs/ui/maquetas/src/hud.py [otra.json…] [--out DIR] [--rejilla]` → `docs/ui/maquetas/<id>.png`. `--piezas` lista piezas, fuentes, colores y tipos.
- Entrada: `.json` (una maqueta o lista) o `.py` con `MAQUETA`/`MAQUETAS` (`{"id", "fondo", "elementos", "tam"?}`). Ejemplo con todo: `ejemplos/ejemplo.json`.
- Fondo: `{"color": "hueco"}` o `{"captura": "docs/ui/maquetas/fondos/mapa_dia.png", "oscurecer": 0.4, "desaturar": 0.3}`.
- Elementos (`rect` `[x, y, w, h]`, 0 = automático): `panel` (madera|pergamino|oscuro|fila, titulo, cerrar) · `boton` (estado normal|encima|pulsado|desactivado, icono, tecla) · `pestana(s)` · `barra` · `campo` · `tooltip` · `retrato` (marco, familia, tecla, corona, cola) · `icono` · `imagen` (recorte, escala) · `texto` (fuente cuerpo|negrita|pequena|titulo o `fichero.ttf:tam`) · `separador` · `fila`/`lista` · `aviso` · `velo` · `caja` · `pieza` · `zona` · `llamada`.
- Imágenes: `guild:icons/icon_oro.png` (Guild Renew, solo lectura), `icono:sword`, `ui:marks/seal`, `pieza:check_on` o ruta del repo. Colores: token de `tokens.json` o `#rrggbb`.
- HUD propuesto como funciones (`ficha()`, `reloj()`, `lateral()`…): `docs/ui/maquetas/src/hud.py`.
- Fondos sin HUD: `captura_fondos.tscn` (por `grimoire heavy`; `--at=HH:MM --solo=<toma>` para el atardecer).
- `logo.py` dibuja el logotipo; `glifos_extra.py` añade `→ ← ↑ ↓ −` a Pixel Operator (necesita `pip install fonttools`).

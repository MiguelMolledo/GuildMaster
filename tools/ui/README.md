# tools/ui · maquetas con el kit real

`maqueta.py` compone maquetas PNG de 960×540 (y `_x2` a 1920×1080) con las piezas del juego: los 9-patch de
`assets/art/ui/theme/` (márgenes en `PIECES` de `tools/art/dibujar_ui.py`), las fuentes de `assets/art/ui/fonts/` y los
colores y medidas de `tokens.json`. No es un dibujo libre: si una pieza cambia, la maqueta cambia al regenerarla.

- `python3 tools/ui/maqueta.py tools/ui/ejemplos/ejemplo.json` → `docs/ui/maquetas/_ejemplo.png` + `_ejemplo_x2.png`
- Varias a la vez, otra carpeta, rejilla de 4/16 px: `maqueta.py a.json b.py --out /tmp/m --rejilla`
- Qué hay: `maqueta.py --piezas` (piezas, fuentes, colores y tipos de elemento).
- Entrada: `.json` (una maqueta o lista) o `.py` con `MAQUETA`/`MAQUETAS`; o `import maqueta; maqueta.render(dict)`.
- Fondo: `{"color": "hueco"}` o `{"captura": "docs/novedades/x.png", "oscurecer": 0.4, "desaturar": 0.3}`.
- Elementos (`rect` = `[x, y, w, h]`; `w`/`h` = 0 → automático): `panel` (estilo madera|pergamino|oscuro|fila, titulo,
  cerrar) · `boton` (texto, estado normal|encima|pulsado|desactivado, icono, tecla) · `pestana`/`pestanas` · `barra`
  (valor, color, marca, texto) · `campo` (texto, vacio, cursor) · `tooltip` (titulo, texto) · `retrato` (imagen, marco
  normal|activo|apagado|muerto, familia, tecla, corona, cola) · `icono` · `imagen` · `texto` (fuente cuerpo|negrita|
  pequena|titulo, color, alinear, contorno) · `separador` · `fila`/`lista` (icono, valor, color_valor, seleccionada,
  apagada) · `aviso` (gravedad info|aviso|urgente|bien) · `velo` · `caja` · `pieza` · `zona` · `llamada` (n).
- Imágenes: `guild:icons/icon_oro.png` (Guild Renew, solo lectura), `icono:sword` (`assets/art/icons/`), `ui:marks/seal`
  (`assets/art/ui/`), `pieza:check_on` (`assets/art/ui/theme/`) o ruta del repo. Láminas de otro tamaño: `"tam": [w, h]`.
- Fuentes de maquetas: `tools/ui/kit/` (00-03 y el HUD: `hud.py` tiene funciones `ficha()`, `reloj()`, `lateral()`…
  para montar cualquier pantalla sobre el HUD propuesto), `tools/ui/mecanicas/`. Fondos sin HUD: `captura_fondos.tscn`.
- Colores: un token de `tokens.json` (`oro`, `negativo`…) o `#rrggbb`. Texto sin suavizado, como en el juego.
- `glifos_extra.py` añade a Pixel Operator `→ ← ↑ ↓ −` (necesita `pip install fonttools`; solo si cambian las fuentes).

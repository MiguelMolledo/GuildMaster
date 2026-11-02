# Arte · gasto de créditos

Cada encargo que gaste apunta aquí el saldo **antes y después** (PixelLab: `get_balance`; fal: coste estimado).
Gratis: `pixelart_workbench`, `vfx_workbench`, `search_help`, `get_*`, `list_*`.
Ojo: con las generaciones del plan a 0, PixelLab cobra del crédito en $ antes que del regalo diario.
Plan: Tier 1, 2.000 generaciones/mes, se renueva el 15 de cada mes.

| Fecha | Encargo | Herramienta | Assets | Saldo antes | Saldo después | Gasto |
|---|---|---|---|---|---|---|
| 2026-11-01 | Láminas de concepto de ciudad (6) | fal Nano Banana Pro | `assets/concept/ciudades/` (en el repo guild) | — | — | 6 imágenes |
| 2026-11-01 | Instalación de PixelLab Pip: comprobación de saldo (sin generar) | `get_balance` | — | 0 gen. del plan · $0.00 · 4 de regalo hoy | igual | 0 |
| 2026-11-02 | Reuso de sprites de Guild Renew (rama arte-guild): edificios, puestos, suelo, puestos de la forja, props, iconos, bocadillos | Copia del repo `guild` (sin generar) | 53 assets, origen `guild-renew` (lista en `docs/arte/reuso_guild.md`) | — | — | 0 (reuso sin coste) |
| 2026-11-02 | Reuso de Guild Renew, 2ª tanda: casas de relleno, patios, tablón compuesto, props a escala, adoquín y tierra recoloreados, iconos de 16 px | Copia del repo `guild` + Pillow (`tools/art/derivar_guild.py`) | 2 casas, tablón, surcos, suelo de patio, 25 iconos pequeños; recoloreo de street/plaza/dirt; props a mitad | — | — | 0 (reuso sin coste) |

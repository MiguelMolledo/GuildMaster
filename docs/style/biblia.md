# Biblia de estilo

El perfil estético de GuildMaster. Todo asset nuevo (PixelLab, fal, a mano) se pide y se revisa contra esta página.
Referencias visuales: `assets/concept/ciudades/` (láminas de fal, 2026-11-01) y docs/gdd/09_ciudades.md.

## Dirección

- **Pixel art 16-bit SNES**, tono cálido y vivido (Graveyard Keeper, Stardew Valley), con la profundidad sistémica de The Guild II.
- **Isométrico 2:1**, diamante de 64×32. Cámara fija, sin rotación.
- Contorno **negro de un color**, sombreado medio, detalle medio. Luz que viene de arriba a la izquierda.
- Siglo XIV centroeuropeo: entramado de madera, piedra, tejas de barro y pizarra, toldos de tela.

## Tamaños (D2: viewport 960×540 escalado ×2 entero)

| Qué | Tamaño en el sprite |
|---|---|
| Casilla | 64×32 |
| Personaje | 48 px de alto |
| Edificio pequeño / mediano / grande | ~128 / ~192 / ~256 px de ancho |
| Icono | 32×32 |
| Retrato | 64×64 |

> Las escalas de edificio del primer intento (192 px × 1,6) eran para 1920×1080. Con D2 se revisan en H1 con una captura de
> prueba: personaje y edificio juntos en su escala real antes de generar nada nuevo.

## Paletas

**Base (tierras cálidas):** marrones, tostados, terracota, verde bosque, gris piedra, dorado, rojo oscuro, azul cielo.
**Secundaria (otoñal):** gris oscuro, púrpura profundo, oro apagado, verde bosque — noche, intrigas, zona del Pícaro, tribunal.

**UI medieval** (marco de madera con remaches sobre pergamino):

| Uso | Color |
|---|---|
| Madera | `#5c3a1e` |
| Remaches | `#8a8a7a` |
| Pergamino | `#d4b896` |
| Sección oscura | `#2a1f14` |
| Filete dorado | `#c8a84e` |
| Hueco vacío | `#1a1209` |
| Positivo | `#7ec87e` |
| Negativo | `#c85050` |

**Día y noche** (tinte global): amanecer `#FFD4A0`, día `#FFFFFF`, atardecer `#FF9060`, noche `#1A1A40`.

## Ciudad (D10, provisional hasta la prueba de PixelLab)

Rebanada vertical en estilo **E (pueblo-calle)**; mapa del EA en **A (villa de mercado orgánica) con C (río y puerto)**.
Jerarquía clara (plaza, iglesia, ayuntamiento), calles orgánicas, casas adosadas de 1-3 plantas con tejados que cambian por
barrio, y detalle de calle (toldos, barriles, carros, pozos, ropa tendida).

## Personajes

- Sprites monolíticos por profesión/NPC (sin capas) en el MVP.
- **Identidad de familia por paleta:** pelo, piel y ropa con el color de la familia. Los rasgos visuales se heredan.
- Lectura a 48 px: silueta y color de la ropa dicen la profesión antes que el detalle.

## Prompts base

- PixelLab personaje: `view: low top-down`, `outline: single color black outline`, `shading: medium shading`,
  `detail: medium detail`, 8 direcciones, 48 px.
- fal (concepto): «16-bit SNES pixel art, isometric 2:1, warm earthy palette (browns, tans, terracotta, forest green, stone
  grey, gold, deep red, sky blue), single black outline, medieval central European town, 14th century» + lo que se pide.

## No

- Nada de degradados suaves, antialiasing ni filtrado lineal.
- Nada de perspectiva distinta de 2:1 en sprites del juego (las láminas de fal son concepto, no se recortan).
- Nada de texto dentro de los sprites (los textos salen de i18n).

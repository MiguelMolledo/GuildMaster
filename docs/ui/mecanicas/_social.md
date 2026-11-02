# Mecánicas sociales y políticas: convenciones comunes

Lo que comparten los siete documentos sociales de `docs/ui/mecanicas/` (ciudad_viva, familia, cortejo_y_boda,
titulos_y_reputacion, cargos_y_elecciones, tribunal, rivales). Parte de [`_comun.md`](_comun.md) (rejilla, filas, colores
con significado, motivos de rechazo, cifras, iconos de Guild Renew) y solo añade lo propio de lo social.

> [!NOTE]
> Si la guía visual del kit (`docs/ui/README.md` y 00-03) fija otra cosa, manda la guía.

## Dónde va cada cosa (960×540)

```
 0                                                                          960
 ┌─ HUD superior (kit) ───────────────────────────────────────────────────────┐ 0
 ├────────────────────────────────────────────────────────────────────────────┤ 48
 │ grupo 1-2-3                                                                │
 │ ┌ TARJETAS ──────┐                     ┌── PANEL LATERAL (_comun) ───────┐ │ 96
 │ │ x 4..304       │                     │ x 600..952 · y 96..516           │ │
 │ │ microevento,   │                     │ ficha de vecino, cortejo,        │ │
 │ │ vida, presagio │       mapa          │ tablón, ayuntamiento, cargos,    │ │
 │ │ (apiladas,     │                     │ familias rivales                 │ │
 │ │  máx. 2 + «+N»)│                     │                                  │ │
 │ └────────────────┘                     └──────────────────────────────────┘ │
 ├────────────────────────────────────────────────────────────────────────────┤ 524
 └────────────────────────────────────────────────────────────────────────────┘ 540

 PANEL GRANDE (árbol, juicio):  x 4..956 · y 52..520, sobre velo; el HUD superior sigue visible.
 CARTA (ceremonia, boda, sucesión, recuento, veredicto): centrada, 360-420 × 180-260, sobre velo 50 %.
 CONFIRMACIÓN: la de _comun (280×120 centrada).
```

- **Panel lateral**: los paneles sociales usan la misma caja que los de economía. Abrir uno cierra el que hubiera. La
  ficha de vecino deja de salir abajo a la izquierda: así no tapa el grupo ni las tarjetas.
- **Tarjetas** (columna izquierda): avisos que piden mirar o decidir sin parar el juego. Como mucho 2 visibles; el resto
  en una lengüeta «+N más». Orden: las que caducan antes, arriba.
- **Cartas**: momentos (título, boda, sucesión, resultado de una elección, veredicto). Una a la vez; si llegan dos, la
  segunda espera a que se cierre la primera. Se cierran con clic o con su tiempo; las que piden una decisión no se cierran
  solas.

## Piezas sociales que se repiten

| Pieza | Uso | Estado en el kit |
|---|---|---|
| Retrato con color de familia | Toda persona que aparece en una ficha, lista o carta | Existe (`retrato` con `familia`) |
| Estandarte / cinta de familia | Cabecera del árbol, cartas, fichas de familia rival | **Pendiente**: 9-patch vertical teñido con `colors.primary` y `secondary` |
| Barra bipolar −100..+100 | Relación | **Pendiente** (la `barra` del kit es de 0 a 1; hace falta la marca del cero centrada) |
| Barra con umbral | Afinidad (80), votos, juicio (defensa contra acusación) | Existe (`barra` con `marca`) |
| Insignias 8×8 | Heredero, controlable, cargo, difunto, regente, candidato | **Pendiente** (base: `icon_crown`, `icon_deceased`, `icon_ring`, `icon_controllable` de Guild Renew) |
| Banda de palabra | Relación (Enemigo…Amigo), rivalidad (Cordial…Enemiga), probabilidad (Fácil/Dudoso/Difícil) | Texto + color: no necesita pieza |
| Sello de lacre | Cartas oficiales (título, cargo, veredicto) | **Pendiente**: sello 24×24 en `lacre` con relieve |

## Reglas

1. **El motivo se lee**: igual que en `_comun`, el motivo de un botón apagado va escrito; en lo social además dice
   **cuándo** se arregla si es cuestión de tiempo («Ya hablasteis hoy · mañana», «Inscripción hasta el día 13»).
2. **Lo irreversible confirma**: insultar, amenazar, sobornar, difamar, proponer matrimonio, designar heredero, acusar.
   Lo barato y repetible (conversar, halagar, regalar poco) no.
3. **Las tiradas se anuncian por bandas**, no con el número: Fácil (umbral ≥ 65) · Dudoso · Difícil (≤ 35), con
   umbral = 50 + (stat del actor − stat del rival) × 5 (GDD 4.2.4). El tooltip enseña los dos atributos enfrentados.
4. **Colores de familia en todo lo que tenga dueño**: el color de una familia (`families[fam].colors.primary`) solo
   se usa para identificarla (borde de retrato, cinta, borde de burbuja de emoción, barra de votos). Nunca como
   positivo o negativo.
5. **Lo público y lo privado**: la UI enseña de otras familias solo lo que vería un jugador (GDD 4.21, 04c 4.21.4):
   título, reputación, cargos, edificios por fuera, candidaturas, ventas públicas. Nunca su oro ni sus inventarios.
6. **Nada de rol en los textos de sistema**; el tono medieval va en los títulos de las cartas y los botones de cierre
   («¡Viva la familia!»), como hoy.

## Sonido

Las cartas y ceremonias necesitan sonidos que hoy no están en `data/audio.json`. Cada documento lista los suyos; en
resumen, faltan: `sfx_wedding_bells`, `sfx_birth`, `sfx_death_bell`, `music_succession`, `sfx_title_fanfare`,
`sfx_vote_count`, `sfx_gavel`, `sfx_verdict_guilty`, `sfx_verdict_innocent`, `sfx_rumor` (presagio). Mientras no haya
créditos, cada uno apunta en su documento qué sonido ya pagado lo sustituye.

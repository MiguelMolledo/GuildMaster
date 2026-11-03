# Mecánicas sociales y políticas: convenciones comunes

Lo que comparten los siete documentos sociales de `docs/ui/mecanicas/` (ciudad_viva, familia, cortejo_y_boda,
titulos_y_reputacion, cargos_y_elecciones, tribunal, rivales). Parte de [`_comun.md`](_comun.md) (rejilla, filas, colores
con significado, motivos de rechazo, cifras, iconos de Guild Renew) y solo añade lo propio de lo social.

> [!NOTE]
> Si la guía visual del kit (`docs/ui/README.md` y 00-03) fija otra cosa, manda la guía.

## Dónde va cada cosa (zonas del HUD propuesto, `01_hud.md`)

Mandan las zonas de [`01_hud.md`](../01_hud.md) (`hud.ZONAS` en `docs/ui/maquetas/src/hud.py`). Lo social las usa así:

| Zona del HUD | Rect | Qué lleva de lo social |
|---|---|---|
| 4 · Columna izquierda | `[4, 58, 236, 186]`, y bajo ella hasta la zona de avisos | **Tarjetas**: microevento, nacimiento/escuela, «te acusan», presagio. Debajo del objetivo, que se pliega a su título cuando hay tarjeta. Como mucho 2 visibles; el resto en «+N más». 236 de ancho. |
| 5 · Panel de gestión | `[600, 58, 356, 430]` | Ficha de vecino, tablón, cortejo, ayuntamiento, reputación (libro), familias rivales y ficha de familia. Uno a la vez. |
| 6 · Selección | `[244, 492, 472, 44]` | La persona o el vecino elegido, con sus 1-3 acciones. |
| Modal grande | `[24, 58, 912, 440]` sobre velo desde y 58 (el HUD de arriba se ve) | **Pantallas que no caben en la zona 5**: árbol de la familia, organigrama de cargos (con sus pestañas Campaña y Poderes) y el juicio (preparación y vista oral). |
| Carta | centrada, 380-420 × 200-260, sobre velo | Ceremonia de título, boda, sucesión, recuento, veredicto. |
| Confirmación | 280 × ~150 centrada (01_hud §5) | Cancelar a la izquierda, la acción a la derecha. |

- **Un solo panel de gestión** (01_hud): abrir la ficha de vecino cierra el tablón, etc.
- **Tarjetas**: avisos que piden mirar o decidir sin parar el juego. Orden: las que caducan antes, arriba.
- **Cartas**: una a la vez; si llegan dos, la segunda espera. Se cierran con clic o con su tiempo; las que piden una
  decisión no se cierran solas.

## Piezas sociales que se repiten

| Pieza | Uso | Estado en el kit |
|---|---|---|
| Retrato con color de familia | Toda persona que aparece en una ficha, lista o carta | Existe (`retrato` con `familia`) |
| Estandarte / cinta de familia | Cabecera del árbol, cartas, fichas de familia rival, letreros | **Pendiente**: 9-patch vertical teñido con `colors.primary` y `secondary` (en las maquetas, con cajas) |
| Barra bipolar −100..+100 | Relación | **Pendiente** (la `barra` del kit es de 0 a 1; hace falta la marca del cero centrada) |
| Barra con umbral | Afinidad (80), votos, juicio (defensa contra acusación) | Existe (`barra` con `marca`) |
| Insignias de título y cargo | Título de una familia, cargo de una persona | **Existen**: `ui:marks/badge_title_<id>` y `ui:marks/badge_office_<id>` (12×12) |
| Galones de rango | Aprendiz / oficial / maestro de un vecino | **Existen**: `ui:marks/rank_1..3` (8×8) |
| Insignias 8×8 de estado | Tecla 1-2-3, escuela pendiente, regente, elección abierta («urna»), de tu familia | **Pendiente** (en las maquetas, letra sobre caja) |
| Banda de palabra | Relación (Enemigo…Amigo), rivalidad (Cordial…Enemiga), probabilidad (Fácil/Dudoso/Difícil) | Texto + color: no necesita pieza |
| Sello de lacre | Cartas oficiales (título, cargo) | **Existe**: `ui:marks/seal` (16×16). Para el veredicto hace falta su variante con texto encima (CULPABLE / INOCENTE). |
| Pergamino | Notas del tablón | **Existe**: pieza `parchment` |

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

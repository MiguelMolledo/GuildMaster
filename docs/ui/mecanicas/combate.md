# Combate · la pantalla del duelo

> Dueño: duelo · Estado: en la partida (rama duelo2) · Fecha: 2026-11-04
> Guía de estilo: [00_lenguaje_visual.md](../00_lenguaje_visual.md) · Zonas y reglas del HUD: [01_hud.md](../01_hud.md) ·
> Reglas: [04e_combate.md](../../gdd/04e_combate.md) · Convenciones: [_comun.md](_comun.md), [_social.md](_social.md)

La ventana que 04d (4.22.6.13) marcaba como «falta». Sirve para el duelo de honor y, con las variantes de 4e.7, para
los combates del Pícaro. En la partida se abre sola a la hora del duelo; el prototipo sigue en `--duel-test` (§9).
Contrato: [docs/contratos/duelo.md](../../contratos/duelo.md).

---

## 1. Para qué sirve

- «¿Qué va a hacer?» → el **gesto** del rival y **cuánto fiarse** de él.
- «¿Qué puedo hacer y qué me cuesta?» → las tres acciones con su coste de aliento; las que no puedo pagar, apagadas.
- «¿Voy ganando?» → los toques de cada uno y el lance en que vamos.
- «¿Qué ha pasado?» → la animación del lance y una línea de registro por lance.

## 2. Cómo se abre y se cierra

- **Antes:** «Retar a duelo…» en la ficha de una persona de otra familia (apagado con su motivo: sin motivo, enfriamiento,
  ya tiene un duelo…) abre la **carta de reto** (`DuelCard`, PageCard): tipo, hora y sitio, tus opciones en banda con el %,
  testigos de ahora, lo que ganas o pierdes, qué le cuesta rechazar, «si no estás a la hora, pierdes»; un botón por causa
  («Por la ofensa», «Por el oficio», «Por Clara»), «Pelear sin reto» si estás al alcance, Cerrar. Lejos, el personaje va
  andando y reta al llegar. La **respuesta** llega en otra carta («Bernat acepta el duelo: el día 2 a las 06:00»), y a las
  05:30 un aviso urgente («Duelo con Bernat a las 06:00: a la plaza»).
- **Abrir:** a las 06:00, si los dos están en la plaza, la pantalla se abre sola. Si no estás, carta de incomparecencia.
  Prototipo: `--duel-test` (sobre la partida de prueba en pausa).
- **Pausa automática** mientras está abierta, como la vista oral del tribunal (H11): el duelo no corre contra el reloj.
- Cerrar: al acabar, con la carta de resultado («Cerrar»): la partida vuelve a la pausa en que estaba. **Esc** a medio
  duelo: en la partida, «Resolver sin jugar» (no se abandona un duelo); en el prototipo, cierra.
- Cada lance es una orden que se aplica al momento aunque la partida esté en pausa (`Game.step_now`: un minuto de juego).
- Teclas: **1** Golpe, **2** Parada, **3** Finta, **R** Rendirse (solo hasta la rendición), **A** Resolver sin jugar.
  Las teclas salen en la esquina de cada botón (`MenuKit.add_hint`).

## 3. Jerarquía de información

1. **El gesto** (pergamino bajo la escena): quién lleva la iniciativa, la frase del gesto («Adelanta el hombro: viene
   un golpe.») y la fiabilidad en grande («Fiable: 5 de cada 10»). Si llevas tú la iniciativa: «Bernat te lee: 5 de cada
   10». Lance 1: «Lance a ciegas».
2. **Las tres acciones** con su coste (`Golpe −2`, `Parada +1`, `Finta −1`), apagadas sin aliento (motivo en el tooltip:
   «Te falta aliento»); a la derecha Rendirse y Resolver sin jugar.
3. **Los dos duelistas**: retrato grande con marco (PortraitFrame, el tuyo dorado), nombre y casa, arma (y armadura),
   **toques** (cuadros dorados, el rival se llena desde la derecha) y **aliento** («Aliento 2/4» y cuadros azules).
4. **La escena** en el centro: los dos sprites frente a frente (×2) y la animación del lance.
5. Cabecera: «Duelo a primera sangre» y «Lance 3 de 9 · gana quien dé 3 toques».
6. Registro: los 3 últimos lances («Lance 6 · Parada contra Golpe → toque (Hugo)»).
7. A demanda (tooltip): qué gana cada acción y cuánto aliento gasta.

## 4. Acciones y sus estados

| Acción | Orden que emitirá | Normal | Deshabilitada | ¿Confirmación? |
|---|---|---|---|---|
| Golpe (1) | `{"type": "duel_move", "actor", "duel", "action": "strike"}` | Botón primario | Sin 2 de aliento: «Te falta aliento»; durante la animación | No |
| Parada (2) | `duel_move` `parry` | Botón primario | Solo durante la animación (siempre se puede parar) | No |
| Finta (3) | `duel_move` `feint` | Botón primario | Sin 1 de aliento | No |
| Rendirse (R) | `duel_move` `yield` | Solo en «hasta la rendición» | Oculto en «a primera sangre» | No (hoy); en la partida, sí: es irreversible y cuesta honor |
| Resolver sin jugar (A) | `{"type": "duel_auto", "actor", "duel"}` | Siempre | Durante la animación | No |
| Otro duelo / Cerrar (carta) | — (prototipo) | — | — | — |

En la partida la pantalla solo da esas órdenes y lee `state.duels.open[id].duel`; el prototipo llama a `Duel.choose()` /
`Duel.auto_finish()` sobre un duelo propio. La carta de resultado de la partida enseña **lo que el sim aplicó**
(reputación, relación, afinidad); la del prototipo, lo propuesto.

## 5. Estados especiales

- **Lance a ciegas** (el 1): sin pista; el pergamino lo dice.
- **Sin aliento**: Golpe y Finta apagados; el rival lo ve igual que tú (su barra está a la vista).
- **Durante la animación** (~0,6 s): botones apagados, la cabecera, el gesto y las barras siguen siendo los del lance
  que se anima; al acabar pasan al siguiente.
- **Resolver sin jugar**: los lances que faltan se animan seguidos a doble velocidad y sale la carta.
- **Fin**: «El duelo ha terminado» en el pergamino y la carta de resultado encima.
- **Tipo bloqueado** (a muerte): la pantalla no se abre; el reto lo rechaza el sim (`kind_locked`).

## 6. Maqueta

```
┌──────────────────────────── Duelo a primera sangre ─────────────────────────────┐
│                     Lance 3 de 9 · gana quien dé 3 toques                       │
│ ┌──────┐                                                              ┌──────┐  │
│ │retrato│                 ¡Toque!                                     │retrato│ │
│ └──────┘          ☺ ──────▶        ◀── ☺                              └──────┘  │
│ Hugo Herrero      (sprite ×2)          (sprite ×2)              Bernat Ferrer  │
│ A puño                                                                A puño   │
│ Toques ■□□        ─────────────────────────────────             Toques □□■     │
│ Aliento 2/4 ■■□□  Arte provisional: faltan poses y efectos   Aliento 4/4 ■■■■ │
│ ┌────────────────────────────────────────────────────────────────────────────┐ │
│ │ Bernat lleva la iniciativa: lee su gesto                                   │ │
│ │ Carga el pie de atrás: espera para parar.                                  │ │
│ │ Fiable: 5 de cada 10                                                       │ │
│ └────────────────────────────────────────────────────────────────────────────┘ │
│ [Golpe −2  1] [Parada +1  2] [Finta −1  3]        [Rendirse R] [Resolver sin jugar A] │
│ Lance 1 · Golpe contra Golpe → choque (Bernat)                                  │
│ Lance 2 · Finta contra Finta → nada (nadie)                                     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

Capturas reales del prototipo: `docs/novedades/duelo_gesto.png` (leer), `duelo_iniciativa.png` (llevar la
iniciativa), `duelo_lance.png` (a mitad de animación), `duelo_resultado.png` (la carta).

## 7. Datos

- Lee (hoy): un `Duel` (`sim/combat/duel.gd`): `view(lado)` (lance, quién lidera, papel, pista, lectura, acciones
  permitidas, si se puede rendir), `lances_log()`, `result()`, `touches()`, `breath()`; las cifras de `Catalog.combat`
  (`data/combat.json`); el personaje y su familia del `WorldState` (retrato, sprite, nombre, armas por el equipo).
- Leerá (conectado): `state.duels[id]` (el mismo diccionario, `Duel.d`).
- Emitirá: `duel_move`, `duel_auto` (04e §4e.4.3). Las cartas de reto y respuesta (`duel_challenge`, `duel_answer`)
  serán una carta no bloqueante del kit de página (como «Te acusan» del tribunal), fuera de esta pantalla.

## 8. Sonido, animación y arte

- **Animación por lance** (`DuelArena`, pasos de píxel entero de `UiAnim`): Golpe = embestida de 18 px y vuelta
  (`UiAnim.lunge`, 0,24 s); Finta = media embestida que se retira; Parada = paso atrás de 6 px con chispa; el tocado
  retrocede 10 px parpadeando (`UiAnim.recoil`, 0,18 s) con un círculo rojo; una palabra sube en el centro («¡Toque!»,
  «choque», «detenido», «nada»). La entrada de la ventana, `UiAnim.panel_in`.
- **Arte provisional** (marcado en la escena con «Arte provisional: faltan las poses y efectos del duelo»): las poses
  usan las animaciones que ya hay (`forge` para el golpe, `work` para la finta, `idle` para la parada) y los efectos se
  dibujan por código. Lo que falta, en `assets/inventario.json` (`para: duelo`):

| Id | Qué | Herramienta | Coste |
|---|---|---|---|
| `chr_duel_poses` | Guardia, golpe, parada, finta, tocado y rendido, de perfil (e y w), para los 6 ids de personaje | PixelLab `animate_character` (ciclo del 15-nov) | ~40 generaciones (lista de abajo) |
| `vfx_duel_strike`, `vfx_duel_parry`, `vfx_duel_feint`, `vfx_duel_hit` | Tajo, chispa, estela, toque | `vfx_workbench` | **Hecho** (gratis): `assets/art/vfx/<id>/<id>.png` + `.json` |
| `icon_duel_actions` | Golpe, Parada, Finta, Rendirse, Resolver sin jugar, aliento, toque y reto (32 y 16) | fal | **Hecho**: `assets/art/ui/icons/duel/icon_<acción>.png` y `small/` |
| `ill_duel_result` | Ilustración de la carta (victoria, derrota, tablas) y de la carta de reto | fal | **Hecho**: `assets/art/ui/illustrations/duel/<victory\|defeat\|draw\|challenge>.png` (240×135) y `_192` |

**Efectos.** Cada tira es de izquierda a derecha y va acompañada de su `.json`, con estos campos:
- `frames`, `frame_w`, `frame_h`, `fps` y `loop`;
- `offset`: la esquina de arriba a la izquierda del fotograma respecto a los pies del personaje, mirando al **este**.
  Mirando al oeste, se refleja y se usa `x = -(offset.x + frame_w)`.

Dónde va cada uno: el golpe, la parada y la finta se ponen en quien los hace; el toque, en quien lo recibe. Los
cuatro se editan en «My effects» de pixellab.ai (`tools/art/vfx_duelo.py` lleva sus ids) y se rehacen con
`python3 tools/art/vfx_duelo.py`.

**Poses: lista para el ciclo de PixelLab del 15-nov** (`chr_duel_poses`). Los 6 ids salen de 4 personajes de
PixelLab, porque los empleados comparten sprite con los artesanos (`tools/art/personajes_guild.py`). Todo se pide
mirando al **este**; el oeste es el mismo reflejado. Las tiras se pasan por `personajes_guild.py` para codificar la
identidad, igual que las demás animaciones.

| Personaje (PixelLab) | Lo usan |
|---|---|
| Artesano Base `1cf5846c-8d08-4c45-9e4c-cd04a8da312c` | `artisan_m`, `worker_m` |
| Artesana Base `695c5c8e-c279-426e-848c-a4d8cde4fe30` | `artisan_f`, `worker_f` |
| Aldeano Hombre `fde29d1c-75de-4379-9b9a-e7f682a7ddba` | `townsfolk_m` |
| Aldeana Mujer `e29d63fb-1474-4396-a095-79cd8aefcf36` | `townsfolk_f` |

| Animación (id del juego) | Cómo pedirla | Generaciones por personaje (este) |
|---|---|---|
| `duel_guard` (bucle) | plantilla `fight-stance-idle-8-frames` | 1 |
| `duel_hit` (tocado) | plantilla `taking-punch` | 1 |
| `duel_strike` | a medida (skeleton-v3, pose `slash`): «steps forward and slashes a short sword from high to low, then returns to guard», 6-8 fotogramas | ~2 |
| `duel_parry` | a medida (pose `block`): «raises the blade across the body to block a blow and leans back a little», 4-6 fotogramas | ~2 |
| `duel_feint` | a medida: «starts a forward slash, stops halfway and pulls back to guard», 6 fotogramas | ~2 |
| `duel_yield` (rendido, sin bucle) | a medida (pose `kneel`): «drops the sword and kneels on one knee, one hand raised», 6 fotogramas | ~2 |

En total, unas 4 × 10 = **~40 generaciones**. El coste a medida, `ceil(ancho × alto × fotogramas / 65536)` por
dirección, sale del lienzo que genere la herramienta: hay que mirar el recibo y apuntar el saldo antes y después en
`MANIFEST`. Se guardan como `assets/art/characters/<id>/duel_<pose>_e.png` (y `_w` reflejado), como las demás tiras.

- Sonido (faltan en `data/audio.json`): `combat_hit`, `combat_miss` (ya propuestos en 04d 4.22.9), `combat_parry`,
  `combat_feint`, `duel_start` (campana corta), `duel_won`.

## 9. Diferencias con lo que hay y tareas

Hecho (prototipo, rama `duelo`): `game/ui/duel_screen.tscn` + `duel_screen.gd`, `duel_arena.gd`, `duel_pips.gd`,
`UiAnim.lunge` / `UiAnim.recoil`, `App.open_duel_test()` (`--duel-test`, `--duel-kind`, `--duel-weapon`,
`--duel-rival`), el bot `game/smoke/smoke_duel.gd` (`--smoke-script=duel [--duel-again]`).

Hecho en duelo2: `game/ui/duel_director.gd`, el modo partida de la pantalla, «Retar a duelo…» en la ficha, las cartas,
el guion `--smoke-script=duelo_partida`.
- [x] La pantalla da `duel_move` / `duel_auto` (por `Game.step_now`).
- [x] Carta de reto y de respuesta, con el coste de rechazar a la vista.
- [x] Esc = Resolver sin jugar.
- [x] Consecuencias reales en la carta.
- [ ] Responder retos (Aceptar / Rechazar / Proponer otro tipo): cuando los NPC reten (O-C7, O-C17).
- [ ] Confirmación de Rendirse: con «hasta la rendición» (O-C4).
- [ ] Testigos en la escena (siluetas detrás) y el padrino de cada lado.
- [ ] Arte y sonido de §8 (los efectos, iconos e ilustración se ven solos cuando lleguen: `VisualPaths.duel_*`).

## 10. Criterios de aceptación

- [x] Con `--duel-test`, se ve la pantalla con los dos retratos, los dos sprites frente a frente, toques, aliento, el
  gesto con su fiabilidad y los tres botones con su coste (captura `docs/novedades/duelo_gesto.png`).
- [x] Sin aliento, Golpe y Finta salen apagados (captura `duelo_gesto.png`: «Golpe −2» apagado con aliento 1).
- [x] Cada lance se anima y deja su línea en el registro (captura `duelo_lance.png`).
- [x] Al acabar sale la carta de resultado con los toques, los lances y las consecuencias propuestas
  (`duelo_resultado.png`).
- [x] «Resolver sin jugar» acaba el duelo y saca la carta (`--duel-again`, `duel_auto_result`).
- [x] Con un duelo de la partida, la pantalla se abre sola a la hora con pausa automática (`docs/novedades/duelp_pantalla.png`).
- [x] Desde la ficha del rival, «Retar a duelo…» abre la carta con las causas (`duelp_ficha.png`, `duelp_carta.png`).
- [x] La respuesta del rival y el aviso de las 05:30 (`duelp_respuesta.png`, `duelp_alba.png`).

# Combate · la pantalla del duelo

> Dueño: duelo · Estado: borrador (prototipo jugable aparte, sin conectar a la partida) · Fecha: 2026-11-04
> Guía de estilo: [00_lenguaje_visual.md](../00_lenguaje_visual.md) · Zonas y reglas del HUD: [01_hud.md](../01_hud.md) ·
> Reglas: [04e_combate.md](../../gdd/04e_combate.md) · Convenciones: [_comun.md](_comun.md), [_social.md](_social.md)

La ventana que 04d (4.22.6.13) marcaba como «falta». Sirve para el duelo de honor y, con las variantes de 4e.7, para
los combates del Pícaro. Hoy se abre solo con `--duel-test` o `--smoke-script=duel` (§9).

---

## 1. Para qué sirve

- «¿Qué va a hacer?» → el **gesto** del rival y **cuánto fiarse** de él.
- «¿Qué puedo hacer y qué me cuesta?» → las tres acciones con su coste de aliento; las que no puedo pagar, apagadas.
- «¿Voy ganando?» → los toques de cada uno y el lance en que vamos.
- «¿Qué ha pasado?» → la animación del lance y una línea de registro por lance.

## 2. Cómo se abre y se cierra

- Abrir (cuando se conecte): al empezar un duelo en el que juega alguien de tu familia, a la hora y en el sitio
  (04e §4e.3.3). Hoy: `--duel-test` (sobre la partida de prueba en pausa).
- **Pausa automática** mientras está abierta, como la vista oral del tribunal (H11): el duelo no corre contra el reloj.
- Cerrar: al acabar, con la carta de resultado («Cerrar»). **Esc** a medio duelo: hoy cierra el prototipo; en la partida
  será «Resolver sin jugar» (no se puede abandonar un duelo sin perderlo).
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

Hoy el prototipo llama a `Duel.choose()` / `Duel.auto_finish()` directamente (no hay partida que guardar); al conectarlo,
la pantalla solo dará esas órdenes y leerá `state.duels[id]`.

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
| `chr_duel_poses` | Guardia, golpe, parada, finta, tocado y rendido, de perfil (e y w), para los 6 ids de personaje | PixelLab `animate_character` (ciclo del 15-nov) | ~6 × 6 animaciones, estimar con `get_balance` |
| `vfx_duel_strike`, `vfx_duel_parry`, `vfx_duel_feint`, `vfx_duel_hit` | Tajo, chispa, estela, toque | `vfx_workbench` | Gratis |
| `icon_duel_actions` | Golpe, Parada, Finta, Rendirse, aliento, toque (32 y 16) | `create_1_direction_object` o Pillow | 1 hoja |
| `ill_duel_result` | Ilustración de la carta (victoria, derrota, tablas) | fal con el kit de página | ~0,15 USD por lámina |

- Sonido (faltan en `data/audio.json`): `combat_hit`, `combat_miss` (ya propuestos en 04d 4.22.9), `combat_parry`,
  `combat_feint`, `duel_start` (campana corta), `duel_won`.

## 9. Diferencias con lo que hay y tareas

Hecho (prototipo, rama `duelo`): `game/ui/duel_screen.tscn` + `duel_screen.gd`, `duel_arena.gd`, `duel_pips.gd`,
`UiAnim.lunge` / `UiAnim.recoil`, `App.open_duel_test()` (`--duel-test`, `--duel-kind`, `--duel-weapon`,
`--duel-rival`), el bot `game/smoke/smoke_duel.gd` (`--smoke-script=duel [--duel-again]`).

Pendiente al conectarlo (tras el Gate O-C):
- [ ] La pantalla da `duel_move` / `duel_auto` por `Game.give` en vez de llamar a `Duel`.
- [ ] Carta de reto y respuesta (Aceptar / Rechazar / Proponer otro tipo) con el coste de rechazar a la vista.
- [ ] Confirmación de Rendirse; Esc = Resolver sin jugar.
- [ ] Testigos en la escena (siluetas detrás) y el padrino de cada lado.
- [ ] Consecuencias reales en la carta (hoy: «propuesta, sin aplicar»).
- [ ] Arte y sonido de §8.

## 10. Criterios de aceptación

- [x] Con `--duel-test`, se ve la pantalla con los dos retratos, los dos sprites frente a frente, toques, aliento, el
  gesto con su fiabilidad y los tres botones con su coste (captura `docs/novedades/duelo_gesto.png`).
- [x] Sin aliento, Golpe y Finta salen apagados (captura `duelo_gesto.png`: «Golpe −2» apagado con aliento 1).
- [x] Cada lance se anima y deja su línea en el registro (captura `duelo_lance.png`).
- [x] Al acabar sale la carta de resultado con los toques, los lances y las consecuencias propuestas
  (`duelo_resultado.png`).
- [x] «Resolver sin jugar» acaba el duelo y saca la carta (`--duel-again`, `duel_auto_result`).
- [ ] Con un duelo de la partida (cuando se conecte), la pantalla se abre sola a la hora con pausa automática.

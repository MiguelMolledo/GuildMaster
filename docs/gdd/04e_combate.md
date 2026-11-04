## 4e. Combate: el duelo «a tres tiempos» (Gate O-C)

**Estado: borrador para aprobar por el owner** (2026-11-04). Nada de esto está conectado a la partida: las reglas puras
viven en `sim/combat/` y el prototipo jugable se abre aparte (`--duel-test`, §8). Cuando el owner lo apruebe, se apunta en
`docs/decisiones.json` y se decide en qué hito entra (O-C1).

Las cifras **[balance]** son valores iniciales medidos con `tools/duel_bench.gd` (§2.8). Lo que solo puede decidir el
owner está en §9.

Dependencias: 4.22.6.1 «Combate como orden» (04d, pendiente de Gate 4.22), SkillCheck (ap. A), reputación y títulos
(4.12, H9), cortejo (4.10.1, H8), tribunal y delitos leves (4.12.5, H11), IA rival (04c, pendiente de Gate) y la regla de
que el sim es determinista (5.2). **No cambia 04c ni 04d**: donde las toca, se propone aquí y se pregunta.

---

### 4e.1 Qué es y qué no es

El juego no va de combatir. El combate aparece en momentos señalados: un duelo con otro noble por el amor de una dama
(o de un caballero), porque alguien te ha ofendido ante testigos, o en las submecánicas del Pícaro. Por eso es un
**minijuego corto, legible y de decisiones, no de reflejos**:

1. **Corto.** Un duelo dura de 4 a 9 lances, unos 40-60 s reales. Nunca hay tiempo límite para decidir.
2. **Legible.** Tres acciones, un triángulo, una pista con su fiabilidad en porcentaje. Todo lo que cuenta está en pantalla.
3. **De decisiones.** Lo que saca al duelo del azar es **leer el gesto** del rival y **administrar el aliento**; la IA
   castiga al que repite siempre lo mismo.
4. **Una sola resolución.** El duelo, el «Resolver sin jugar», los combates entre vecinos y el Pícaro usan el mismo lance
   (§4). Jugar bien da lo mismo que la resolución automática; jugar a ciegas, menos.

---

### 4e.2 Reglas del lance

#### 4e.2.1 Las tres acciones

Cada lance, los dos duelistas eligen una acción:

| Acción | Gana a | Aliento [balance] | Lectura |
|---|---|---|---|
| **Golpe** (`strike`) | Finta | −2 | Ataque franco |
| **Parada** (`parry`) | Golpe (y contraataca) | **+1** (recupera) | Esperar y responder |
| **Finta** (`feint`) | Parada | −1 | Amagar para abrir la guardia |

- **Distintas:** quien gana el intercambio **intenta un toque** (§4e.2.3). Puede fallarlo («lo detiene»).
- **Golpe contra golpe:** **choque**. Uno de los dos toca seguro; quién, lo decide una tirada (§4e.2.3).
- **Parada contra parada** o **finta contra finta:** nada, salvo que el arma de uno tenga ese filo (§4e.2.5).

#### 4e.2.2 Iniciativa y gesto (la lectura)

El lance 1 es **a ciegas**: los dos eligen sin ver nada. Desde el lance 2 la **iniciativa se alterna** (el retador lleva
la del lance 2, el retado la del 3, y así):

- Quien **lleva la iniciativa** elige primero; su cuerpo le delata (el hombro, la mirada, el pie).
- Quien **lee** ve ese **gesto**, que dice la verdad con probabilidad

```
lectura = clamp(0,50 + (empatía_lector − arte_marcial_del_que_lleva) × 0,05 ; 0,34 ; 0,90)    [balance]
herido: −0,10
```

  y, si miente, enseña una de las otras dos acciones (a partes iguales). La pantalla dice la fiabilidad («Fiable: 6 de
  cada 10»). Con 0,34 la pista no sirve de nada; con 0,90 casi siempre acierta, pero nunca es segura.

- Cuando el jugador lleva la iniciativa, el rival le lee a él con la misma fórmula (la pantalla lo avisa: «Ferrer te
  lee: 5 de cada 10»).

Por qué así y no los dos a la vez con pista para el jugador: si solo el jugador leyera, la vía automática y la jugada no
podrían dar las mismas probabilidades, y un duelo entre dos vecinos no tendría lector. Con la iniciativa alterna la regla
es simétrica: lo que da la Empatía al jugador se lo da al rival, y la resolución automática es el mismo lance jugado por
la IA en los dos lados (§4e.4).

| Lector (Empatía) contra quien lleva (Arte Marcial) | Lectura |
|---|---|
| 3 contra 3 (el herrero contra el herrero rival) | 0,50 |
| 3 contra 6 (el herrero contra un noble entrenado) | 0,35 |
| 7 contra 3 | 0,70 |
| 10 contra 1 | 0,90 (tope) |

#### 4e.2.3 El toque y el choque

Las dos son tiradas d100 con los críticos de SkillCheck (≤ 5 acierta siempre, ≥ 96 falla siempre):

```
toque  (gana el intercambio) = 50 + (arte_marcial_A − arte_marcial_B) × 5 + 30 (ventaja)
                               + filo_del_arma (si la acción ganadora es la de su filo) + mods
choque (golpe contra golpe)   = 50 + (arte_marcial_retador − arte_marcial_retado) × 5
                               ± empate_del_arma (de quien tenga filo de golpe) + mods;   pasa: toca el retador, falla: el retado
filo en empate (parada-parada, finta-finta) = 50 + (AM_portador − AM_otro) × 5 + empate_del_arma + mods;   pasa: toca, falla: nada
mods [balance]: armadura del otro −10 · herido −20
```

Ganar el intercambio con Arte Marcial igual toca el 80 % de las veces; contra alguien 4 puntos mejor, el 60 %.

#### 4e.2.4 Aliento

```
aliento_máx = 2 + floor(constitución × 0,5) + aliento_del_arma          [balance]   (Con 5, puños: 5)
```

Golpe gasta 2, Finta 1, Parada recupera 1 (sin pasar del máximo). **Sin aliento para una acción, no se puede elegir**: con
0 solo queda Parada, y el rival lo sabe. La barra de aliento de los dos se ve siempre.

#### 4e.2.5 Armas y armadura

Las armas **inclinan** el triángulo, no hacen más fuerte: lo que gana duelos es el Arte Marcial y la Empatía (§2.8).

| Arma (`weapons`) | Filo | Toque con su filo | Empate en su filo | Aliento | De dónde sale |
|---|---|---|---|---|---|
| Puños (`fists`) | — | — | — | +1 | Sin arma equipada |
| Herramienta (`tool`) | Golpe | +5 | +10 en el choque | — | Martillo, sierra, azada equipados |
| Espada (`sword`) | Golpe | +20 | +20 en el choque | — | Espada equipada |
| Daga (`dagger`) | Finta | +5 | finta-finta: tirada +10 | — | [futuro: Pícaro] |
| Bastón (`staff`) | Parada | +5 | — | +1 | [futuro] |

- **Armadura** (ropa `armor` equipada): −10 a los toques y choques contra quien la lleva.
- Qué objeto equipado cuenta como qué arma: `data/combat.json` → `items` y `armor_items`.
- En un duelo de honor **el retado elige las armas** (O-C5): las dos espadas, las dos herramientas o a puño.

#### 4e.2.6 Tipos de duelo y final

| Tipo (`kinds`) | Gana quien da | Lances máx. | El perdedor | Rendirse | Para qué |
|---|---|---|---|---|---|
| **A primera sangre** (`first_blood`) | 3 toques | 9 | Sin herida | No | Ofensas, cortejo: el duelo normal |
| **Hasta la rendición** (`surrender`) | 4 toques | 11 | **Herido** 24 h (4.22.3.3) | Sí, en cualquier lance | Afrentas graves, ofensas repetidas |
| **A muerte** (`to_death`) | — | — | — | — | **Bloqueado** (O4 de 04d, O-C3) |

- Al llegar al último lance sin el número de toques, gana quien lleve más; con los mismos, **tablas** (los dos salvan
  el honor).
- **Rendirse** (solo hasta la rendición): pierdes sin herida, pero con más pérdida de honor que caer luchando (§4e.5).
  La IA se rinde cuando al otro le falta un toque y va 2 por detrás, la mitad de las veces [balance].

#### 4e.2.7 La IA del duelo

La misma política sirve para el rival, para los duelos entre vecinos y para «Resolver sin jugar» (`CombatRules.ai_choice`):

- **Cuando lee:** responde a la pista con lo que la gana (Golpe contra Finta, etc.). Si no tiene aliento, repite la acción
  de la pista (empate) o para.
- **Cuando lleva la iniciativa o a ciegas:** desde el lance 3, la mitad de las veces **castiga tu costumbre**: elige lo que
  gana a la acción que más has repetido (si hay una sola más repetida). Si no, elige al azar entre lo que puede pagar, con
  un poco más de peso (+0,2) para el filo de su arma.

Así cualquier política fija pierde (§4e.2.8): el jugador que siempre golpea, para o finta acaba leído.

#### 4e.2.8 Medidas (`tools/duel_bench.gd`, 2.000 duelos por fila, a primera sangre)

`godot --headless --path . -s tools/duel_bench.gd [-- --n=2000 --kind=surrender --set=read.step=0.07]`. Retador contra
retado, los dos jugados por la IA (o el retador por la política que dice la fila):

| Duelo (retador vs retado) | Gana | Pierde | Tablas | Lances |
|---|---|---|---|---|
| Iguales (AM 3, Emp 3, Con 5, puños) | 46 % | 46 % | 9 % | 6,4 |
| Arte Marcial 5 vs 3 | 64 % | 28 % | 8 % | 6,4 |
| Arte Marcial 7 vs 3 | 75 % | 18 % | 7 % | 6,3 |
| Empatía 7 vs 3 | 58 % | 34 % | 8 % | 6,3 |
| Constitución 9 vs 5 | 48 % | 45 % | 7 % | 6,3 |
| Espada vs puños | 46 % | 44 % | 10 % | 6,5 |
| Herramienta vs puños | 44 % | 46 % | 10 % | 6,6 |
| Daga vs puños | 54 % | 40 % | 6 % | 6,1 |
| Bastón vs puños | 47 % | 45 % | 8 % | 6,4 |
| Espada vs espada y armadura | 36 % | 54 % | 10 % | 6,6 |
| Herido vs sano | 26 % | 63 % | 12 % | 6,8 |
| Herrero (AM 3, Emp 3, martillo) vs noble (AM 6, Emp 5, espada) | 15 % | 79 % | 6 % | 6,1 |
| Pícaro (AM 7, Emp 5, espada) vs vecino (AM 3, Emp 4, Con 4) | 78 % | 15 % | 7 % | 6,3 |
| Pícaro vs guardia (AM 6, Emp 5, Con 6, espada, armadura) | 45 % | 44 % | 10 % | 6,6 |

| El jugador (iguales) contra la IA | Gana | Pierde | Tablas |
|---|---|---|---|
| **Resolver sin jugar** | 46 % | 46 % | 9 % |
| **Sigue la pista** (la política de la IA) | 46 % | 46 % | 9 % |
| Elige al azar | 36 % | 54 % | 10 % |
| Siempre Golpe | 31 % | 63 % | 6 % |
| Siempre Parada | 6 % | 87 % | 8 % |
| Siempre Finta | 34 % | 50 % | 16 % |

Lectura de la tabla:

- **Las dos vías dan lo mismo** con los mismos atributos: «Resolver sin jugar» es exactamente el duelo de quien sigue la
  pista (las pruebas lo comprueban duelo a duelo y en 3 emparejamientos con 2.000 semillas, ±3 puntos).
- **Leer vale ~10 puntos** frente a jugar al azar; repetir una acción cuesta de 12 a 40.
- El retado gana ~1 punto más que el retador con atributos iguales (lee el lance 3); retar tiene su riesgo.
- La Constitución apenas pesa (aliento). Es deliberado: el duelo es de destreza y lectura, no de aguante. Si el owner
  quiere que pese, se sube el coste del Golpe o se baja `breath.base` [balance].
- Hasta la rendición: 8 lances de media entre iguales, mismas proporciones.
- Con Constitución 3 (el arenero `town_e_start`: aliento 4) los últimos lances tienden a Parada y Finta sin nada
  (los dos sin aliento para golpear): el bot de capturas acabó dos duelos así. Si molesta al jugarlo, que la Parada
  recupere 2 o que el empate en Finta sea un choque [balance, a probar jugando].

---

### 4e.3 Cuándo hay duelo

#### 4e.3.1 Quién reta y por qué

Solo se puede retar con una **causa**: el sim la comprueba (`reason` legible si falta). Causas propuestas:

| Causa (`cause`) | Cuándo vale | Quién puede retar | A quién |
|---|---|---|---|
| **Ofensa** (`offense`) | Te insultaron (`npc_insult`, H7) o amenazaron en los últimos 2 días [balance] | El ofendido o un miembro adulto de su familia | Al ofensor |
| **Amor** (`courtship`) | Dos pretendientes de la misma persona soltera, los dos con afinidad ≥ 40 [balance] con ella | Cualquiera de los dos | Al otro pretendiente |
| **Honor de la familia** (`slander`) | Te acusaron en el tribunal (H11) y saliste **inocente** | El acusado | Al acusador |
| **Afrenta de un rival** (`rivalry`) | La IA rival en banda Hostil (04c, 4.21.8) puede **retar** como ataque nuevo | La familia IA | Al jugador o a otra familia |

- Edad mínima: adulto (16 años). Un herido no puede retar ni ser retado. Un retado no puede tener otro duelo pendiente.
- Enfriamiento: la misma pareja no se reta otra vez en 1 estación [balance].
- La **IA rival** retando es un ataque nuevo de 04c (lista cerrada): solo si el owner lo añade a 04c (O-C7). Mientras
  tanto, la IA solo **responde** retos.

#### 4e.3.2 Responder

El retado tiene **hasta el amanecer siguiente** para responder (`duel_answer`). Una carta no bloqueante («Ferrer te reta
a primera sangre por la señorita Clara»), con los tres botones: **Aceptar**, **Rechazar**, **Proponer otro tipo**
(primera sangre ↔ hasta la rendición; el retador acepta o retira). Sin respuesta = rechazo.

| Respuesta | Efecto [balance] |
|---|---|
| Aceptar | Duelo al amanecer siguiente (§4e.3.3) |
| Rechazar | **−10 de reputación** con testigos del reto (0 si nadie lo vio); el retador +2. Si el retado tiene un título **dos o más escalones por encima**, rechazar no cuesta nada («no se rebaja») |
| No presentarse a la hora | Como rechazar, y además −10 de relación con el retador |
| Retirar el reto (el retador) | −5 de reputación del retador |

La IA (familias IA y vecinos) acepta si su probabilidad de ganar (la de la vía automática, §4e.2.8) es ≥ 40 % o si
rechazar le costaría más reputación de la que arriesga perdiendo [balance]; si no, rechaza.

#### 4e.3.3 Dónde, cuándo y con quién mirando

- **Cuándo:** al amanecer siguiente a aceptar, a las 06:00 [balance]. Los dos reciben una orden `move_to` al sitio a las 05:30
  (la da el sim como hoy la rutina; el jugador puede cambiarla y entonces no se presenta).
- **Dónde:** el marcador `duel_ground` del mapa (un claro o la plaza; `data/maps/<mapa>.json` → `markers`); si el mapa no
  tiene, la plaza. Es un dato del mapa, no del código.
- **Testigos:** los personajes despiertos a ≤ 8 casillas [balance] cuando empieza, más un **padrino** por lado (el
  primer miembro adulto de cada familia que esté libre; si no hay, nadie). Con 3 o más testigos el duelo es **público**:
  sus consecuencias de honor cuentan doble (§4e.5).
- **Pausa:** si uno de los duelistas es de la familia del jugador, al empezar se abre la pantalla del duelo con **pausa
  automática**, como la vista oral del tribunal (H11). Si no lo es, se resuelve en el sim sin pantalla (vía automática)
  y llega un aviso con el resultado.

#### 4e.3.4 Duelo entre otros

Dos familias IA, o un vecino y una familia IA, pueden batirse (cuando 04c lo permita): se resuelve con `Duel.auto` en el
minuto en que empieza, deja su hecho en la crónica y sus consecuencias igual que si fuera del jugador.

---

### 4e.4 Encaje con el sim determinista

#### 4e.4.1 Una sola resolución

`sim/combat/combat_rules.gd` (`CombatRules`, puro y estático) resuelve **un lance** a partir de las dos acciones, los dos
luchadores, la semilla y el id del duelo. `sim/combat/duel.gd` (`Duel`) lleva un duelo lance a lance; su estado es un
`Dictionary` JSON (`Duel.d`) listo para vivir en `WorldState` cuando se apruebe. **Todo combate del juego pasa por ahí**:

| Quién | Cómo |
|---|---|
| El jugador juega el duelo | `Duel` con `player` = su lado; cada elección es una orden (§4e.4.3) |
| «Resolver sin jugar» | `Duel.auto_finish()`: la IA juega el lado del jugador desde ese lance |
| Duelo entre dos NPC | `Duel.auto()` al empezar |
| Pícaro: asalto, robo, detención | El mismo lance con las variantes de §4e.7 |

#### 4e.4.2 Las tiradas no mueven nada

Cada tirada sale de una semilla con clave, como `Kin.roll`:

```
tirada = RandomNumberGenerator(seed = hash("<semilla del mundo>|combat|<id del duelo>|<lance>|<qué>")).randf()
qué: cue, cue_lie, touch, clash, edge, habit|<lado>, style|<lado>, yield|<lado>
```

- **No usa `state.rng`**: un duelo no cambia ninguna otra tirada de la partida (mercado, eventos, vecinos).
- **No depende del orden**: da igual que el jugador tarde, que el lance se resuelva en este paso o en el siguiente, o
  que se mire la pantalla o no.
- Misma semilla, mismo duelo, mismas elecciones = mismo resultado (prueba `test_same_seed_same_duel`). La elección del
  rival depende solo de la semilla, el lance y el historial de acciones del duelo.

#### 4e.4.3 Órdenes (propuesta; ninguna existe hoy)

| Orden | Campos | Tipo | Regla principal (motivo si falla) |
|---|---|---|---|
| `duel_challenge` | actor, target, cause, kind | en persona (a ≤ 3 casillas, como el cortejo) | Causa válida, adultos, sanos, sin duelo pendiente, sin enfriamiento, tipo no bloqueado (`no_cause`, `too_young`, `wounded`, `busy`, `cooldown`, `kind_locked`, `too_far`) |
| `duel_answer` | actor, duel, answer: `accept` \| `refuse` \| `counter`, kind | gestión | Solo el retado, antes del plazo (`not_challenged`, `too_late`) |
| `duel_withdraw` | actor, duel | gestión | Solo el retador, antes de empezar |
| `duel_move` | actor, duel, action: `strike` \| `parry` \| `feint` \| `yield` | gestión (pantalla) | Su lado, lance abierto, aliento suficiente, rendirse solo si el tipo lo deja (`not_your_side`, `already_chosen`, `no_breath`, `cannot_yield`, `duel_over`) |
| `duel_auto` | actor, duel | gestión | «Resolver sin jugar» desde el lance abierto |

- `duel_move` se aplica en el paso en que llega, en pausa activa (como las órdenes del tribunal). La IA no «ve» la
  elección del jugador: cuando el jugador lleva la iniciativa, el sim genera la pista de su acción con la lectura del
  rival y la IA responde a esa pista, nunca a la acción.
- Los bots dan las mismas órdenes (un `bot_duelist` para las dianas de §4e.6).

#### 4e.4.4 Estado y guardado

`state.duels: {id → Duel.d}` (pendientes y en curso; los cerrados pasan a la crónica y se borran) y en cada personaje
`last_duel: {with, day}` para el enfriamiento. **Entra con la versión de guardado de 4.22 (v15) o la siguiente libre**;
en esta fase no se guarda nada (el prototipo vive fuera de la partida).

#### 4e.4.5 Encaje con 4.22.6.1 (combate como orden del Pícaro)

4.22.6.1 propone asaltos de 5 min con vida (5 + Constitución), daño y SkillCheck de Arte Marcial. Este documento propone
**sustituirlo por el lance** (O-C2), para que haya una sola resolución:

| 4.22.6.1 | Con el lance |
|---|---|
| Asalto de 5 min | Un lance = 1 min de juego en el sim (un duelo de 9 lances, < 10 min) [balance] |
| Vida 5 + Constitución, daño 3 + arma − armadura | Toques para ganar (`kinds`); la Constitución da aliento |
| Acierta = SkillCheck(AM, AM) + mods | Toque y choque (§4e.2.3), mismos mods: arma, armadura −10, herido −20 |
| Emboscada +20 el primer asalto | Emboscada: el primer lance el emboscado no elige (§4e.7) |
| Aliados +10 cada uno (máx. +20) | Banda: cada aliado da un toque gratis al empezar, máx. 2 (§4e.7) |
| Posturas `to_the_end` / `flee` / `yield` | La IA usa su postura al ir perdiendo: `yield` = rendirse; `flee` = la acción Huir (§4e.7) |
| Veneno +15 y +1 de daño | Truco sucio de un uso: un toque (§4e.7) |
| Cuenta: Pícaro (AM 7, espada) vs vecino (3) gana ≥ 90 % | Con el lance, **78 %** a primera sangre; con emboscada o banda, por encima del 90 % (a medir en H12.3) |
| Contra un guardia gana < 35 % | Con el lance, 45 % a primera sangre; el guardia lucha hasta la rendición (4 toques) y suele ir acompañado: a medir |

Las cuentas de referencia de 4.22.6.1 se mueven: el lance tiene más varianza que el modelo de vida. Se mide con el bot
`thief` cuando llegue H12.3, no ahora.

---

### 4e.5 Consecuencias

El juego no tiene un atributo «honor»: **el honor es la reputación** (4.12.1, `Reputation.change`) y, entre nobles, la
relación. Propuesta [balance], multiplicada por 2 si el duelo es público (≥ 3 testigos) y por el **peso del rival**
(1 + 0,5 por cada escalón de título que esté por encima del tuyo, máx. 2):

| Hecho | Reputación | Relación entre los dos | Otros |
|---|---|---|---|
| Ganar | +5 | −10 | Hecho de crónica `duel_won` (puntos en `score.json`) |
| Perder luchando (a toques o en el último lance) | −2 | −5 | Hasta la rendición: herido 24 h (4.22.3.3) |
| Tablas | +1 los dos | +5 | «Se batieron con nobleza» |
| Rendirse | −8 | −5 | Sin herida |
| Rechazar un reto con testigos | −10 | −10 | 0 si el retado está 2+ títulos por encima |
| Ganar con trampa (Pícaro, §4e.7) con testigos | — | — | Delito `brawl`; con veneno, `poison` (4.22.6.9) |

- **Cortejo** (causa `courtship`): la persona cortejada suma **+15 de afinidad al ganador** y **+5 al perdedor que luchó
  sin rendirse** («se batió por mí»); el que se rinde o rechaza, **−15**. La regla de 4.10.1 no cambia: la boda sigue
  pidiendo `propose_min` y la propuesta. Si los dos pretendientes quedan en tablas, +5 a los dos.
- **Ofensa** (causa `offense`): ganar borra el estado «ofendido/humillado» de tu lado y te da +5 de relación con quien
  presenció la ofensa; perder le da al ofensor el estado «Humillado» de 4.11.5 (POST-MVP hoy, se activaría aquí).
- **Calumnia** (causa `slander`): ganar al acusador le pone −10 de reputación adicional («acusó en falso y perdió»).
- **Delitos:** un duelo con causa, aceptado, en el sitio y a la hora es **legal** (costumbre). Pegarse sin reto aceptado es
  `brawl` (leve, multa 10-50, H11), como dice 4.22.6.1. Las heridas no llevan a juicio. No hay muertes (O4, O-C3).
- **Herido** (solo «hasta la rendición»): el estado de 4.22.3.3 (no trabaja, −20 en combate, 24 h). Si 4.22 no se aprueba
  antes, el duelo hasta la rendición queda bloqueado como el «a muerte» (O-C4).

---

### 4e.6 Bots y dianas (cuando se conecte)

| Bot | Qué hace | Diana [balance] |
|---|---|---|
| `duel_bench` (herramienta, ya existe) | Emparejamientos con 2.000 semillas | Iguales en [42 %, 50 %]; AM 7 vs 3 ≥ 70 %; «Resolver sin jugar» a ±3 puntos de «Sigue la pista»; ninguna política fija ≥ 40 % |
| `duelist` | Partida nueva: corteja, provoca un reto por amor y lo juega siguiendo la pista | En 30 días, ≥ 1 duelo en el 50 % de las semillas; ninguna muerte; las dianas de H3 y H5 del Artesano siguen en verde |
| `idle` + duelos de NPC | Sin jugador; familias IA que se retan (si O-C7) | ≤ 1 duelo por estación en la ciudad; ningún bloqueo |

---

### 4e.7 Variantes del Pícaro (solo diseño; Gate 4.22)

Las mismas piezas, con cuatro variantes. Ninguna se implementa hasta que el owner apruebe 4.22.

| Variante | Regla [balance] | Legalidad |
|---|---|---|
| **Emboscada** | Si el objetivo no te vio venir (SkillCheck sigilo vs empatía, como 4.22.6.1), el lance 1 el emboscado no elige: tu Golpe o tu Finta tocan si pasa el toque; tu Parada no hace nada. Después, duelo normal. | La del ataque (4.22.6.1) |
| **Huida** | Una cuarta acción, **Huir**, cuando se va perdiendo o en vez de responder a una detención: SkillCheck(destreza, destreza del otro). Pasa: el combate acaba sin ganador. Falla: el otro toca gratis. Cuesta 1 de aliento. | Huir de la guardia y fallar: `resisting` |
| **Banda** | Cada aliado presente da **un toque gratis** al empezar (máx. 2). | La del ataque |
| **Trucos sucios** (un uso por combate, del inventario) | **Arena a los ojos:** el lance siguiente el rival no ve pista y no puede leerte. **Veneno** (equipado): el siguiente toque que des cuenta doble. | Con testigos (`Watch.observe`), `brawl`; el veneno, además `poison` |

La pantalla es la misma (§8), con el botón de la acción extra y el inventario de trucos a la derecha.

---

### 4e.8 Prototipo y arte

- **Prototipo:** `godot --path . -- --duel-test [--duel-kind=surrender] [--duel-weapon=sword] [--seed=<n>]` abre la pantalla
  del duelo sobre la partida de prueba (Hugo contra el herrero rival, sus retratos y sus sprites), sin tocar la partida
  ni guardar. Guion de capturas: `--smoke-script=duel`. Pantalla: [docs/ui/mecanicas/combate.md](../ui/mecanicas/combate.md).
- **Arte que falta** (marcado en pantalla y en `assets/inventario.json`): poses de duelo de los personajes (guardia,
  golpe, parada, finta, tocado, rendido), destello de golpe, chispa de parada, estela de finta, iconos de las tres
  acciones y del aliento. Hoy: las animaciones existentes (`idle`, `forge`, `walk`, `death`) y dibujo por código para
  los efectos. Lista de la compra para el ciclo de PixelLab del 15-nov en §4e.8 de `combate.md`.

---

### 4e.9 Decisiones que necesitan al owner

| # | Decisión | Opciones | Recomendación |
|---|---|---|---|
| **O-C1** | Cuándo entra el duelo en la partida | (a) Ya, como mecánica social del Artesano (ofensa y cortejo), antes de 4.22. (b) Con H12.3, junto al Pícaro. (c) Solo el minijuego; los retos con el mapa EA (H13). | **(a)**, solo a primera sangre (sin heridas, sin v15): usa sistemas que ya existen (insultos de H7, cortejo de H8, tribunal de H11) y da algo que hacer con un rival. Hasta la rendición, con 4.22. |
| **O-C2** | Una sola resolución de combate | (a) El lance sustituye a los asaltos de 4.22.6.1 (vida y daño desaparecen). (b) Dos sistemas: el lance para duelos y 4.22.6.1 para el Pícaro, calibrados para dar lo mismo. | **(a)**: una regla, una prueba, una pantalla; las variantes del Pícaro (§4e.7) cubren emboscada, huida, banda y veneno. Obliga a rehacer las cuentas de 4.22.6.1 en H12.3. |
| **O-C3** | Duelo a muerte | (a) Bloqueado siempre (O4). (b) Opción futura solo entre nobles, con delito máximo. (c) En duelos con consentimiento. | **(a)** en el MVP; la fila queda en `data/combat.json` con `locked: true` para no cerrarle la puerta. |
| **O-C4** | Herida del duelo hasta la rendición | (a) Esperar a la salud de 4.22.3.3. (b) Una herida propia del duelo antes de 4.22 (−20 en combate y sin trabajar 1 día). | **(a)**: no inventar una salud paralela; mientras, solo primera sangre. |
| **O-C5** | Quién elige las armas | (a) El retado (tradición). (b) Cada uno las suyas equipadas. (c) Siempre espada en duelos de honor. | **(a)**, entre las que tengan los dos (si uno no tiene espada, herramienta o puños): el retador ya elige el momento. |
| **O-C6** | Lectura: qué atributo lee | (a) Empatía contra Arte Marcial. (b) El mayor de Empatía y Sigilo (la «astucia» del Pícaro). (c) Retórica. | **(a)** para el duelo; (b) solo para las variantes del Pícaro si hace falta. |
| **O-C7** | La IA rival reta | (a) Añadir «Reto» a la lista cerrada de ataques de 04c (con presagio: «Ferrer habla mal de ti en la taberna»). (b) La IA solo responde retos. | **(a)** cuando se revise 04c: es el ataque más legible y barato; mientras tanto, (b). |
| **O-C8** | Rechazar un reto | (a) Cuesta reputación siempre (−10 con testigos). (b) Gratis si el retado está 2+ títulos por encima. (c) Gratis siempre. | **(b)**: un barón no se rebaja ante un aprendiz, pero entre iguales rechazar es cobardía. |
| **O-C9** | Iniciativa del primer lance | (a) A ciegas el 1, luego alterna empezando el retador. (b) Alterna desde el 1, empieza el retado. (c) La lleva quien ganó el lance anterior. | **(a)**: simétrica, el retado lee un lance más (+1 punto) y nadie empieza en desventaja. (c) alarga los duelos (el que gana es leído). |
| **O-C10** | «Resolver sin jugar» | (a) Igual que jugar siguiendo la pista. (b) Un poco peor (−5 %) para premiar jugar. (c) Un poco mejor para no castigar a quien no quiere el minijuego. | **(a)**: el minijuego es para quien lo disfrute; jugar bien empata, jugar mal pierde. |
| **O-C11** | Tipos de duelo | (a) Primera sangre (3 toques) y hasta la rendición (4). (b) Solo primera sangre. (c) También «a tres asaltos» sin heridas, por puntos (torneo). | **(a)**; el torneo, con las fiestas de H13 si se quieren. |
| **O-C12** | Dama o caballero | (a) Cualquier pretendiente de la persona cortejada puede retar al otro, sea cual sea su sexo. (b) Solo entre pretendientes del mismo sexo. | **(a)**: la regla mira el cortejo, no el sexo. |

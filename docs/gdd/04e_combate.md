## 4e. Combate: el duelo «a tres tiempos» (Gate O-C)

**Estado: aprobado por el owner** (2026-11-04: O-C1..O-C12 según las recomendaciones de §4e.9; `docs/decisiones.json`)
**y en la partida** (rama `duelo2`): retos, respuesta de los NPC, el duelo al alba en la plaza, consecuencias, cartas,
pantalla, tutorial y bot. Solo a primera sangre (O-C1, O-C11); hasta la rendición espera a la salud de 4.22 (O-C4).
Contrato: [docs/contratos/duelo.md](../contratos/duelo.md). Guardado **v15**.

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
| **Golpe** (`strike`) | Finta | −1 | Ataque franco |
| **Parada** (`parry`) | Golpe (y contraataca) | **+2** (recupera) | Esperar y responder |
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
toque  (gana el intercambio) = 50 + (arte_marcial_A − arte_marcial_B) × 5 + 15 (ventaja)
                               + filo_del_arma (si la acción ganadora es la de su filo) + mods
choque (golpe contra golpe)   = 50 + (arte_marcial_retador − arte_marcial_retado) × 5
                               ± empate_del_arma (de quien tenga filo de golpe) + mods;   pasa: toca el retador, falla: el retado
filo en empate (parada-parada, finta-finta) = 50 + (AM_portador − AM_otro) × 5 + empate_del_arma + mods;   pasa: toca, falla: nada
mods [balance]: armadura del otro −10 · herido −20
```

Ganar el intercambio con Arte Marcial igual toca el 65 % de las veces; contra alguien 4 puntos mejor, el 45 %. (Hasta el
ajuste de duelo2 la ventaja era 30: con el toque al 80 % el filo de un arma casi no se notaba.)

#### 4e.2.4 Aliento

```
aliento_máx = 2 + floor(constitución × 0,5) + aliento_del_arma          [balance]   (Con 5, puños: 5)
```

Golpe gasta 1, Finta 1, Parada recupera 2 (sin pasar del máximo). **Sin aliento para una acción, no se puede elegir**: con
0 solo queda Parada, y el rival lo sabe. La barra de aliento de los dos se ve siempre.

#### 4e.2.5 Armas y armadura

Las armas **inclinan** el triángulo, no hacen más fuerte: lo que gana duelos es el Arte Marcial y la Empatía (§2.8).

| Arma (`weapons`) | Filo | Toque con su filo | Empate en su filo | Aliento | De dónde sale |
|---|---|---|---|---|---|
| Puños (`fists`) | — | — | — | +1 | Sin arma equipada |
| Herramienta (`tool`) | Golpe | +10 | +10 en el choque | — | Martillo, sierra, azada equipados |
| Espada (`sword`) | Golpe | +25 | +20 en el choque | — | Espada equipada |
| Daga (`dagger`) | Finta | +5 | finta-finta: tirada +10 | — | [futuro: Pícaro] |
| Bastón (`staff`) | Parada | +5 | — | +1 | [futuro] |

- **Armadura** (ropa `armor` equipada): −10 a los toques y choques contra quien la lleva.
- Qué objeto equipado cuenta como qué arma: `data/combat.json` → `items` y `armor_items`.
- En un duelo de honor **el retado elige las armas** (O-C5): las dos espadas, las dos herramientas o a puño.

#### 4e.2.6 Tipos de duelo y final

| Tipo (`kinds`) | Gana quien da | Lances máx. | El perdedor | Rendirse | Para qué |
|---|---|---|---|---|---|
| **A primera sangre** (`first_blood`) | 3 toques | 9 | Sin herida | No | Ofensas, cortejo: el duelo normal |
| **Hasta la rendición** (`surrender`) | 4 toques | 11 | **Herido** 24 h (4.22.3.3) | Sí, en cualquier lance | Afrentas graves, ofensas repetidas. **Bloqueado** hasta la salud de 4.22 (O-C4, O-C11) |
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
retado, los dos jugados por la IA (o el retador por la política que dice la fila). «Sin nada»: lances en que no pasa
nada (parada contra parada, finta contra finta sin filo). Cifras del **ajuste de duelo2** (2026-11-04):

| Duelo (retador vs retado) | Gana | Pierde | Tablas | Lances | Sin nada |
|---|---|---|---|---|---|
| Iguales (AM 3, Emp 3, Con 5, puños) | 43 % | 45 % | 11 % | 6,8 | 18 % |
| Iguales con Constitución 3 (el arenero) | 42 % | 47 % | 11 % | 6,9 | 19 % |
| Arte Marcial 5 vs 3 | 65 % | 26 % | 9 % | 6,7 | 19 % |
| Arte Marcial 7 vs 3 | 80 % | 13 % | 7 % | 6,5 | 20 % |
| Empatía 7 vs 3 | 56 % | 34 % | 9 % | 6,7 | 15 % |
| Constitución 9 vs 5 | 43 % | 46 % | 11 % | 6,8 | 18 % |
| Espada vs puños | 54 % | 38 % | 9 % | 6,6 | 18 % |
| Herramienta vs puños | 47 % | 42 % | 10 % | 6,8 | 18 % |
| Daga vs puños | 53 % | 39 % | 8 % | 6,4 | 14 % |
| Bastón vs puños | 45 % | 45 % | 11 % | 6,8 | 18 % |
| Espada vs espada y armadura | 36 % | 55 % | 9 % | 6,7 | 18 % |
| Herido vs sano | 20 % | 68 % | 12 % | 7,1 | 19 % |
| Herrero (AM 3, Emp 3, martillo) vs noble (AM 6, Emp 5, espada) | 12 % | 83 % | 5 % | 6,0 | 18 % |
| Pícaro (AM 7, Emp 5, espada) vs vecino (AM 3, Emp 4, Con 4) | 90 % | 7 % | 3 % | 6,0 | 18 % |
| Pícaro vs guardia (AM 6, Emp 5, Con 6, espada, armadura) | 46 % | 45 % | 9 % | 6,7 | 19 % |

| El jugador (iguales) contra la IA | Gana | Pierde | Tablas |
|---|---|---|---|
| **Resolver sin jugar** | 43 % | 45 % | 11 % |
| **Sigue la pista** (la política de la IA) | 43 % | 45 % | 11 % |
| Elige al azar | 35 % | 54 % | 11 % |
| Siempre Golpe | 23 % | 72 % | 5 % |
| Siempre Parada | 14 % | 76 % | 10 % |
| Siempre Finta | 19 % | 70 % | 11 % |

**El ajuste de duelo2** (lo que se midió en el prototipo y se arregló):

| Problema medido | Antes | Cambio [balance] | Después |
|---|---|---|---|
| Con Constitución 3 los últimos lances eran paradas y fintas sin nada | 30 % de lances sin nada | Parada recupera **2** (era 1) y Golpe gasta **1** (era 2) | 19 % |
| Las armas casi no daban ventaja | espada vs puños 46/44 | Ventaja del toque **15** (era 30): el filo pesa; espada **+25** (era 20), herramienta **+10** (era 5) | 54/38; herramienta 47/42 |
| Siempre Finta ganaba a la IA sin aliento para golpear | 34 % (y 45 % en una prueba) | El Golpe barato deja a la IA castigarla | 19 % |
| Pícaro (AM 7, espada) contra un vecino (4.22.6.1 pide ≥ 90 %) | 78 % | (el mismo cambio) | 90 % |

Lectura de la tabla:

- **Las dos vías dan lo mismo** con los mismos atributos: «Resolver sin jugar» es exactamente el duelo de quien sigue la
  pista (las pruebas lo comprueban duelo a duelo y en 3 emparejamientos con 2.000 semillas, ±3 puntos).
- **Leer vale ~8 puntos** frente a jugar al azar; repetir una acción cuesta de 24 a 29.
- El retado gana ~2 puntos más que el retador con atributos iguales (lee el lance 3): retar tiene su riesgo.
- La Constitución apenas pesa en el resultado (aliento). Es deliberado: el duelo es de destreza y lectura, no de aguante.
- Pruebas que lo fijan: `test_combat_duel.gd` (`test_balance_the_sword_tilts_and_weak_breath_does_not_stall`: espada
  ≥ 8 puntos sobre puños; Constitución 3 ≤ 24 % de lances sin nada).

---

### 4e.3 Cuándo hay duelo (en la partida desde duelo2)

#### 4e.3.1 Quién reta y por qué

Solo se puede retar con una **causa**: el sim la comprueba (`Duels.causes`, `reason` legible si falta). Hoy, con los
sistemas que ya existen:

| Causa (`cause`) | Cuándo vale | Quién reta | A quién |
|---|---|---|---|
| **Ofensa** (`offense`) | Un adulto de tu familia está `offended` o `angry` (4.11.5) **hacia la familia del otro**: un insulto (`npc_insult`) o una amenaza (`npc_threaten`) de H7, mientras dura la emoción (1-2 días) | Cualquier adulto de la familia ofendida | A cualquier adulto de la familia ofensora |
| **Amor** (`courtship`) | Los dos tienen afinidad ≥ 40 [balance] con la misma persona soltera y adulta (`about`: la de afinidad más alta de las dos) | Cualquiera de los dos | Al otro pretendiente |
| **Rivalidad del oficio** (`rivalry`) | Las dos familias tienen un edificio del mismo tipo (la forja del jugador y la del herrero rival, 4.5.5) | Cualquier adulto | A cualquier adulto de la otra |

- **No retan los NPC** (O-C7 b): ni las familias IA ni los vecinos dan `duel_challenge`. Solo **responden**. Por eso
  ningún bot de antes ve un duelo y sus dianas no se mueven.
- **Calumnia** (`slander`, acusación en falso) queda para después: hoy el tribunal no guarda quién acusó en falso a quién de
  forma utilizable (O-C14).
- Rechazos del sim (`Duels.challenge_status`, en este orden): `unknown_actor`/`unknown_target`, `dead`, `same_family`,
  `too_young` (< 16 años), `wounded` (con la salud de 4.22; hoy nadie), `busy` (alguno ya tiene un duelo abierto),
  `cooldown` (la misma pareja cerró un duelo hace menos de 1 estación = 2 días [balance]), `kind_locked` (hasta la rendición
  y a muerte), `no_cause`, `too_far` (en persona, al alcance de las acciones de H7: 3 casillas o la puerta del edificio
  donde está; la carta de reto acerca al personaje antes, como la ficha).

#### 4e.3.2 Responder

El retado responde con `duel_answer` (aceptar o rechazar) **antes del alba siguiente** (06:00); sin respuesta, rechaza.
Como los NPC no retan, en la práctica solo responden NPC, y lo hacen **en el minuto siguiente** al reto (`Duels.ai_answer`):

1. Si su título está **2 o más escalones por encima** del retador, rechaza y no le cuesta nada («no se rebaja», O-C8).
2. Si no, estima su probabilidad de ganar con 40 duelos automáticos con clave (no mueven ninguna tirada) y acepta si es
   ≥ 0,40 + (aversión al riesgo de su perfil − 0,5) × 0,4 [balance] (el herrero rival: 0,40), o si le falta menos de 0,10
   y rechazar le costaría honor (alguien vio el reto).

| Respuesta | Efecto [balance] |
|---|---|
| Aceptar | Duelo al alba siguiente (§4e.3.3); carta «Bernat acepta el duelo» con el día y la hora |
| Rechazar | El retado −10 de reputación **si alguien vio el reto** (testigos a ≤ 8 casillas del retador al retar), −10 de relación; el retador +2. Carta «Bernat rechaza el reto» |
| Retirar el reto (`duel_withdraw`, el retador, antes de empezar) | −5 de reputación del retador |

#### 4e.3.3 Dónde, cuándo y con quién mirando

- **Cuándo:** a las 06:00 del día siguiente a aceptar [balance]. A las 05:30 el sim manda a los dos a la plaza
  (`move_to`, saliendo antes del edificio si están dentro) y avisa a la familia del jugador («Duelo con Bernat a las 06:00:
  a la plaza»).
- **Reservados:** desde esa llamada hasta que el duelo se cierra, el sim **no da órdenes de sistema** a los dos duelistas
  (IA rival, IA familiar, rutinas, directivas, vecinos: `Sim.give` y `Sim.step` las retienen). Sin esto la IA rival se
  llevaba al herrero a su forja al alba y nunca llegaba. Las órdenes del jugador sí pasan: irse a otra parte es no
  presentarse.
- **Dónde:** el primer spawn del mapa de `challenge.ground` (`duel_ground` si un mapa lo tiene, si no `market`, la plaza).
  El validador exige que cada mapa tenga uno.
- **Presentes:** en la calle y a ≤ 3 casillas del sitio a la hora. Quien no está **pierde por incomparecencia**: −10 de
  reputación, −10 de relación; el otro +2 y gana el duelo. Si faltan los dos, se anula sin más.
- **Testigos:** los que estén en la calle a ≤ 8 casillas al empezar. Con 3 o más el duelo es **público** y su honor cuenta
  doble (§4e.5). (El padrino de 04e queda para cuando haya testigos dibujados, §4e.8.)
- **Armas** (O-C5, el retado elige): la primera de `weapons_order` (espada, herramienta, puños) que tengan **los dos**
  equipada. Hugo con martillo contra Bernat sin nada: a puño.
- **Pausa:** si uno de los duelistas es de la familia del jugador, al empezar el sim deja el duelo abierto (`fighting`)
  y la partida se pausa sola con la pantalla del duelo (como la vista oral de H11). Cada lance es una orden `duel_move`
  que se aplica al momento aunque la partida esté en pausa (`Game.step_now`: un lance = un minuto de juego, en el
  replay). «Resolver sin jugar» (`duel_auto`) juega el resto con la IA. Si nadie juega (un bot que no da órdenes), a los
  120 minutos la IA lo termina.

#### 4e.3.4 Duelo entre otros

Un duelo sin nadie de la familia del jugador (hoy solo si un vecino reta a otro en una prueba: los NPC no retan) se
juega con `Duel.auto` a la hora y deja sus consecuencias y su crónica igual que uno del jugador.

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

#### 4e.4.3 Órdenes (en `Orders.apply`, contrato en `docs/contratos/duelo.md`)

| Orden | Campos | Tipo | Regla principal (motivo si falla) |
|---|---|---|---|
| `duel_challenge` | actor, target, cause, kind | en persona (va por la cola) | §4e.3.1 (`no_cause`, `too_young`, `wounded`, `busy`, `cooldown`, `kind_locked`, `too_far`, `same_family`, `dead`) |
| `duel_answer` | actor, duel, answer: `accept` \| `refuse` | gestión | Solo el retado, el reto pendiente (`unknown_duel`, `not_challenged`, `already_answered`, `bad_answer`) |
| `duel_withdraw` | actor, duel | gestión | Solo el retador, antes de empezar (`not_challenger`, `already_fighting`) |
| `duel_move` | actor, duel, action: `strike` \| `parry` \| `feint` | gestión | Su lado, lance abierto, aliento (`not_fighting`, `not_your_side`, `no_breath`, `bad_action`, `already_chosen`) |
| `duel_auto` | actor, duel | gestión | «Resolver sin jugar» desde el lance abierto |
| `duel_brawl` | actor, target | en persona | Pelea al momento sin reto aceptado (§4e.5): `too_far`, `busy`, `same_family`, `too_young` |

- La IA no «ve» la elección del jugador: cuando el jugador lleva la iniciativa, el sim genera la pista de su acción con la
  lectura del rival y la IA responde a esa pista, nunca a la acción.
- Eventos: `duel_challenged`, `duel_answered`, `duel_called`, `duel_started`, `duel_lance`, `duel_finished`,
  `duel_brawl` (con `family` = la del retador y `target_family`).

#### 4e.4.4 Estado y guardado (v15)

`state.duels = {open: {id → duelo}, closed: [duelo]}` (los 20 últimos cerrados: el enfriamiento y el libro; sin sus
lances, que se descartan al cerrar). Cada duelo: `{id, challenger, challenged, challenger_family, challenged_family,
cause, about, kind, status (pending | accepted | fighting), created, answer_by, at, place, weapon, challenge_witnesses,
witnesses, called, started, duel (Duel.d), player_side}` y al cerrar `{outcome, winner, closed_at, touches, lances}`.
Migración v14 → v15: `SaveFile._to_v15` (una función propia; los viajes, v16, se encadenan detrás). Prueba de ida y
vuelta y de migración en `tests/test_combat_duels_game.gd`.

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
| Cuenta: Pícaro (AM 7, espada) vs vecino (3) gana ≥ 90 % | Con el lance, **90 %** a primera sangre tras el ajuste de duelo2 (era 78 %); con emboscada o banda, más |
| Contra un guardia gana < 35 % | Con el lance, 46 % a primera sangre; el guardia lucha hasta la rendición (4 toques) y suele ir acompañado: a medir |

Las cuentas de referencia de 4.22.6.1 se mueven: el lance tiene más varianza que el modelo de vida. Se mide con el bot
`thief` cuando llegue H12.3, no ahora.

---

### 4e.5 Consecuencias (en el sim: `Duels._close`)

El juego no tiene un atributo «honor»: **el honor es la reputación** (`Reputation.change`, motivos `duel_*` que el libro
de reputación enseña) y, entre los dos, la relación. Un duelo **público** (≥ 3 testigos) dobla la reputación; una
**ganancia** se multiplica por el peso del rival: 1 + 0,5 por cada escalón de título que esté por encima del tuyo, máx. 2.
La relación es una sola cifra entre los dos: cambia una vez por duelo. [balance] (`data/combat.json` → `consequences`):

| Hecho | Reputación | Relación entre los dos | Otros |
|---|---|---|---|
| Ganar | +5 | −10 | Crónica `duel` (resultado `won`) y aviso |
| Perder luchando | −2 | (la del ganador) | Crónica `duel` (`lost`) |
| Tablas | +1 los dos | +5 | «Se batieron con nobleza» |
| No presentarse | −10 | −10 | El otro +2 y gana |
| Rechazar con testigos del reto | −10 (0 si 2+ títulos por encima o sin testigos) | −10 | El retador +2 |
| Retirar el reto | −5 | — | |
| Pelear sin reto (`duel_brawl`) | −5 | −15 | Si alguien lo vio: un **hecho público** con el cargo `brawl` (leve, multa 10-50, H11) contra la familia de quien pegó; sin honor para nadie |

- **Cortejo** (causa `courtship`): la persona cortejada da **+15 de afinidad al ganador**, **+5 al que perdió luchando**,
  **−15** al que no se presentó o rechazó, **+5** a los dos con tablas. La boda sigue pidiendo `propose_min` (4.10.1).
- **Ofensa** (causa `offense`): si gana el ofendido, su familia deja de estar ofendida o enfadada con la del ofensor (el
  estado «Humillado» de 4.11.5 sigue siendo POST-MVP).
- **Crónica:** un hecho `duel` por familia (`character`, `rival`, `cause`, `outcome`, `result`, `touches`, `public`); la
  pantalla final lo cuenta («Duelo con Bernat (ganado), día 2»).
- **Rendirse y heridas:** solo en «hasta la rendición», bloqueado hasta 4.22 (O-C4). Sin muertes (O-C3).

---

### 4e.6 Bots y dianas

| Bot | Desde | Qué hace | Diana (`data/targets.json` → `duelist`) |
|---|---|---|---|
| `duel_bench` (herramienta) | — | Emparejamientos con 2.000 semillas | §4e.2.8 (fijado en pruebas) |
| `duelist` (`sim/bots/bot_duelist.gd`) | escenario `duel_ready` | Reta al rival del oficio cada vez que puede (camina hasta él como la UI), deja que el sim lo lleve a la plaza y juega siguiendo la pista | 8 días: 0 órdenes rechazadas, 0 incomparecencias, 0 peleas sin reto, ≥ 2 duelos de media, entre 0,5 y 2,5 ganados de media. Medido: 3 duelos por semilla, 1,2 ganados |
| Los de antes | — | No retan | Sus dianas salen iguales: ningún NPC reta (O-C7 b) |

Ritual: `godot --headless --path . -s tools/sim_runner.gd -- --scenario=duel_ready --bots=duelist --days=8 --seeds=5`
(en `run_all`, paso `duel`, 3 semillas). Escenario: `tools/scenarios/make_duel_scenarios.gd`.

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

### 4e.8 En la partida, prototipo y arte

- **En la partida:** la ficha de cualquier persona de otra familia lleva «Retar a duelo…» (apagado con su motivo). La carta
  de reto (PageCard) dice el tipo, la hora y el sitio, tus opciones (bandas buenas / parejas / malas con el %), los testigos
  de ahora, lo que te juegas y un botón por causa; «Pelear sin reto» si estás al alcance. La respuesta del rival llega en
  otra carta; el aviso de las 05:30 y el resultado, en los avisos. A las 06:00, si los dos están, la pantalla del duelo se
  abre sola con la partida en pausa. Contrato: [docs/contratos/duelo.md](../contratos/duelo.md). Pantalla:
  [docs/ui/mecanicas/combate.md](../ui/mecanicas/combate.md).
- **Probarlo:** `godot --path . -- --scenario=duel_ready` (el rival te acaba de insultar, a tu lado en la plaza). Capturas:
  `--smoke-script=duelo_partida` (todo el flujo) y `--smoke-script=duel` (el prototipo de `--duel-test`, que sigue).
- **Arte** (`assets/inventario.json`, `para: duelo`; llegó con `arte-fal-2` el 2026-11-04), por `VisualPaths`, que traduce
  los ids del duelo a los nombres del arte sin renombrarlo (`DUEL_ICON_ALIAS`, `DUEL_ILLUSTRATION_ALIAS`):
  - efectos `assets/art/vfx/duel_<strike|parry|feint|hit>/duel_<id>.png` con su `duel_<id>.json` (fotogramas, tamaño, fps,
    desplazamiento de la esquina respecto a los pies, `facing` e): cada duelista dibuja el de su acción a sus pies (×2, como
    la figura; el del oeste reflejado) y el toque sale a los pies de quien lo recibe;
  - iconos `assets/art/ui/icons/duel/icon_<strike|parry|feint|surrender|auto|breath|touch|challenge>.png` y `small/`: los
    botones (Rendirse = `surrender`, Resolver sin jugar = `auto`), las barras de toques y aliento, «Retar a duelo…» (`challenge`);
  - láminas `assets/art/ui/illustrations/duel/<victory|defeat|draw|challenge>.png` (240×135, cartas: resultado y reto) y
    `_192` (192×108, avisos: respuesta e incomparecencia).
  Sin el arte, la caída de siempre (dibujo por código, sin icono, sin lámina). Las poses (`chr_duel_poses`) esperan a
  PixelLab (15-nov): hoy `forge`, `work` e `idle`, y la escena lo dice («Arte provisional: faltan las poses del duelo»).

---

### 4e.9 Decisiones

**Tomadas el 2026-11-04** (el owner: «me parece bien lo que comentas»): O-C1 (a) solo a primera sangre, O-C2 (a), O-C3 (a),
O-C4 (a), O-C5 (a), O-C6 (a), O-C7 (b) hasta revisar 04c, O-C8 (b), O-C9 (a), O-C10 (a), O-C11 (a) con solo primera sangre
de momento, O-C12 (a). Lo que sigue es el registro de lo que se propuso.

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

**Nuevas (duelo2, para el owner):**

| # | Decisión | Opciones | Recomendación |
|---|---|---|---|
| **O-C13** | El duelo en la puntuación de dinastía (`data/score.json`) | (a) Sin puntos: el honor ya es reputación. (b) Pocos puntos por duelo ganado en público. | **(a)**: la reputación ya suma; un punto aparte premiaría retar sin motivo. |
| **O-C14** | La calumnia como causa (te acusaron y saliste inocente) | (a) Añadirla cuando el tribunal guarde «acusó en falso» por familia. (b) No. | **(a)**: es la causa más clara de honor; hoy el juicio no lo guarda de forma utilizable. |
| **O-C15** | Ir a la plaza al alba | (a) El sim lleva al duelista a las 05:30 y lo reserva (hoy). (b) Solo un aviso: el jugador lo lleva. | **(a)**: no perder un duelo por un descuido de reloj; el jugador puede llevárselo y entonces no se presenta. |
| **O-C16** | «Pelear sin reto» en la carta | (a) Dejarlo (delito leve con testigos, −5 de reputación). (b) Quitarlo hasta el Pícaro. | **(a)**: es la salida cuando el rival rechaza, y tiene coste. |
| **O-C17** | Retos de los NPC (O-C7) | (a) Mantener que no retan hasta revisar 04c. (b) Dejar que reten los vecinos ofendidos por el jugador (con un tope por estación). | **(a)** ahora; **(b)** es la siguiente vuelta: hoy un insulto del jugador no tiene más vuelta que la relación. |


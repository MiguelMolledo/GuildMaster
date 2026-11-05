## 4.24–4.28 La ciudad viva II: vida, seguridad, fiestas, juegos y la Posada

> Petición del owner (2026-11-04): «que los NPC tengan muchas cosas que hacer, no solo una; que tengan puntos de
> reunión para hablar; que haya guardias en las entradas; que de vez en cuando haya algún altercado, algún ataque de
> los bandidos por la noche o algún secuestro; eventos en la ciudad como en la medieval: muchas fiestas, con animales,
> la matanza para que todos comiesen, corridas de toros, la visita de algún marqués, la Navidad… con sus imágenes y
> sus efectos visuales, decoraciones, NPC de otras ciudades, visitas y rutas de comercio temporales; más población;
> un negocio nuevo de hospedaje tipo taberna, con clientes a los que atender (mirando Wartales); bodas, la fiesta del
> monasterio, banquetes, y encargos por oficio: el vestido de la novia para el sastre, una espada decorativa de
> regalo para el herrero; torneos de justas, torneos de peleas, apuestas, dados de la época, cartas y carreras de
> caballos». El owner pide que este documento lo desarrolle el manager y lo mantenga al día.

Este documento amplía 4.11 (ciudad viva), 4.13 (eventos), 4.5.6 (encargos) y adelanta piezas de 4.22: los
forasteros (4.22.3.6), los guardias (4.22.6.2), la demanda de servicios (4.22.3.2) y la Taberna-Posada (4.22.4.5).
Esas piezas se construyen **ya**, para todas las clases, aunque el resto de 4.22 siga esperando su Gate. Cuando
4.22 se apruebe, las reutiliza sin rehacerlas.

**Principios** (los de siempre, más dos):

1. **Datos, no código.** Fiestas, actividades, sucesos, juegos, platos y encargos de fiesta son tablas en `data/`,
   con su validación en `tools/validate_content.py`. Añadir una fiesta no pide código.
2. **El sim manda y la vista pinta.** Las decoraciones, la música y los NPC disfrazados son vista. Lo que cambia la
   demanda, las rutinas o el oro está en el sim, es determinista y queda en el replay.
3. **Flujos de azar propios.** Cada sistema nuevo tira con su clave (`semilla | sistema | día | id`) y no mueve las
   tiradas de hoy (como hicieron H13, la población y el duelo).
4. **Las dianas no se mueven sin decirlo.** Los escenarios de las dianas de hoy siguen dando lo mismo, con
   `_no_events` donde ya lo llevan o con el sistema nuevo apagado. Si algo, como la población, tiene que moverlas
   por diseño, se mide antes y después, se propone la banda nueva y se avisa al owner.
5. **Lo bonito es fácil de leer.** Cada fiesta y cada suceso se anuncia con su carta (kit de página, PageCard) y su
   ilustración, sale en la crónica y tiene un aviso que lleva al sitio.
6. **Minijuegos opcionales.** Todo minijuego tiene «Resolver sin jugar», con probabilidades iguales a jugar bien
   (como el duelo, O-C10).

**Calendario (recordatorio, 4.1):** 1 día = 5 min reales; **1 estación = 2 días; 1 año = 8 días**. Cada día del
año cubre, por tanto, mes y medio del calendario real. Por eso el calendario festivo es **un día con fiesta grande
y otro sin ella en cada estación**, más los sucesos y las visitas que caen al azar.

---

### 4.24 Vida en la ciudad: muchas cosas que hacer

#### 4.24.1 La agenda del NPC

Hoy un NPC va de casa al trabajo, socializa al atardecer y vuelve a casa (4.11.2). A partir de ahora cada NPC tiene
**necesidades** y una **agenda de actividades** entre las que elige por utilidad, como las familias jugadoras de H14.

**Necesidades del NPC** (0-100; el mismo modelo que `data/family.json` → `needs`, más `faith`) [balance]:

| Necesidad | Baja por hora | La sube | Si está baja |
|---|---|---|---|
| `hunger` (hambre) | −2 | comer en casa, en la taberna o en el banquete | busca comida antes que el ocio |
| `rest` (descanso) | −1,5 despierto | dormir en casa (o en la posada) | se retira antes |
| `social` | −1 | charlar, bailar, la taberna o la misa | busca un corrillo |
| `fun` (diversión) | −1 | dados, taberna, fiestas y espectáculos | elige ocio antes que pasear |
| `faith` (fe) | −0,5 | la misa, la procesión o la romería | va a la iglesia los días de fiesta |

**Actividades** (`data/life/activities.json`). Cada una lleva dónde se hace, a qué hora, quién la hace, cuánto
dura, qué necesidad sube y qué burbuja enseña:

| Actividad | Dónde | Cuándo | Quién | Sube |
|---|---|---|---|---|
| Trabajar | su taller o puesto | DÍA | adultos con oficio | — (es la obligación) |
| Ir a la compra | puestos del mercado | DÍA, sobre todo por la mañana | adultos; más las amas de casa | `hunger` (compra real, 4.5) |
| Por agua | el pozo o la fuente | AMANECER y DÍA | jóvenes y adultos | — (tarea) |
| Lavar | el lavadero del río o el pozo | DÍA | adultos | `social` +5 |
| Leña y recados | sale a la puerta del pueblo y vuelve | DÍA | jóvenes | — (tarea) |
| Misa | la iglesia | AMANECER; días de fiesta, DÍA | todos; más los piadosos | `faith` +40, `social` +10 |
| Charlar en corrillo | punto de reunión (4.24.2) | DÍA en los descansos, ATARDECER | adultos y ancianos | `social` +30 |
| Sentarse | banco o poyo | DÍA, ATARDECER | ancianos sobre todo | `rest` +10 |
| Taberna | la taberna (4.27) | ATARDECER y NOCHE hasta las 02:00 | adultos; más los Carisma ≥ 7 | `fun`, `social`, `hunger` (paga) |
| Dados | punto de dados o mesa de la taberna | ATARDECER | adultos con Destreza ≥ 6 | `fun` +30 (apuesta, 4.26) |
| Visitar a la familia | la puerta de otra casa | ATARDECER | adultos con parientes | `social` +25 |
| Jugar | la plaza o el prado | DÍA | niños | `fun` +40 |
| Pasear | la calle mayor o la ribera | ATARDECER | parejas y jóvenes | `social`, `fun` |
| Cortejar | un banco o la ribera | ATARDECER | solteros en cortejo (H8) | afinidad (como hoy) |
| Mirar un espectáculo | donde esté (juglares, toros, justa) | según el evento | todos | `fun` +40 |
| Dormir | casa (o posada si es forastero) | NOCHE | todos | `rest` |

**Elección por utilidad** (cada vez que acaba una actividad y cada hora):

```
utilidad(a) = Σ urgencia(necesidad) × sube(a, necesidad)
            × gusto(personalidad, a) × hora(a) × evento(a)  − distancia(a) × 0,02
urgencia(n) = ((100 − n) / 100) ^ 2
gusto       = 1,4 si el rasgo cuadra (Carisma → charla y taberna; Empatía → banco y visitas; Destreza → dados;
              Fe alta → misa); 1 si no. El 12 % de las veces se elige al azar entre las tres mejores (4.11.3).
evento(a)   = lo que pida la fiesta del día (la procesión ×5, el baile ×3, el trabajo ×0,5 en día de guardar…)
```

- **Trabajar es obligatorio en DÍA**, salvo en los descansos (los de 4.11.2) y en los días de guardar.
- **Coste:** una decisión por NPC y por hora más una al acabar cada actividad. Con 40 NPC son unas 60 decisiones
  por hora de juego. Va al bench: la media tiene que seguir por debajo de 2 ms.
- **Ninguna regla de economía cambia**, salvo «Ir a la compra», que ya existe como demanda del mercado. Las demás
  actividades son vida que se ve y necesidades que se mueven. La taberna (4.27) es lo único que cobra.

> [!NOTE]
> **Construido (rama vida, 2026-11-04; contrato `docs/contratos/vida.md`).** `data/life/activities.json` con 17
> actividades: las de la tabla más **Comer en casa** (12-15 h, sube el hambre: sin ella nadie comía de día) y
> **Recados** (la de leña: va a una puerta y vuelve). «Ir a la compra» recorre 2-3 puestos elegidos por la demanda que
> ya calcula el mercado (`Market.effective_demand`) y sube el hambre; no compra nada (ningún flujo de oro nuevo:
> probado). Las necesidades se guardan en décimas (enteros) y bajan cada hora entera; la noche en casa repone descanso
> y hambre. El descanso del trabajo es la probabilidad por hora de H7 (`data/town.json` routine; ×2 los ancianos); el
> día de guardar sube al 70 %. Los niños salen a jugar de día. «Fe alta» = un 30 % de vecinos «piadosos», sacados por
> persona. Todo cuelga de un interruptor (`data/life/life.json` `enabled`): las dianas de antes corren con la vida
> apagada (`_no_life`, principio 4) y salen idénticas. Coste medido: 1,73 ms por paso en el bench (1,37 sin la vida,
> con la máquina cargada; diana < 2 ms).

#### 4.24.2 Puntos de reunión y rumores

**Puntos de reunión** (`social_points` del mapa, con un `kind` nuevo), donde se forman corrillos de 2 a 5:

| Punto | Dónde lo pone el generador | Ambiente |
|---|---|---|
| La fuente o el pozo de la plaza | centro de la plaza | se habla de precios y de bodas |
| El atrio de la iglesia | delante de la iglesia | después de misa; se habla de la fe y de los muertos |
| La puerta de la taberna | fachada de la taberna | al atardecer; se habla de juego, peleas y forasteros |
| El lavadero | orilla del río o del pozo | de día; cotilleo |
| El puente | el puente mayor | jóvenes y paseo |
| La puerta de la villa | junto a los guardias | se habla de los caminos, los bandidos y otras ciudades |
| El banco de la calle mayor | lo pone el decor por reglas | ancianos |

**Rumores** (lo que se habla en los corrillos). Cada corrillo saca, de una tabla, un rumor sobre algo que **ha
pasado de verdad** en la crónica o va a pasar en el calendario: «Dicen que Ferrer debe 200 al banco», «Viene el
marqués para San Juan», «En Portvell pagan bien las espadas», «Anoche asaltaron un carro en el Coll de la Venta».

- El jugador lo ve en una burbuja si pasa a ≤ 4 casillas, y queda en el **libro de rumores** (pestaña del libro).
- Algunos rumores **dan información útil**: precios de otra ciudad, el próximo evento, una deuda o un secreto de
  una familia rival (esto último pasa como pista al espionaje de 4.22 cuando exista), o un encargo que se va a
  publicar.
- La taberna es el mejor sitio para oírlos (4.27.6).
- Los rumores son vista y libro: el sim solo guarda cuáles has oído (para no repetir).

> [!NOTE]
> **Construido.** Kinds nuevos de `social_points`: `well`, `atrium`, `tavern`, `washhouse`, `bridge`, `gate` y `square`
> (la plaza abierta, para niños, juglares y buhoneros), con huecos de 2 a 5. Los pone `tools/city/citylib.add_life` en
> el generador, en las ciudades orgánicas (`region_*`) y en `make_town_e.py`, después del decor y nunca encima (town_e
> conserva sus seis puntos de H7 y H7 solo pasea por los suyos: sus dianas no se mueven); para un mapa ya hecho,
> `ciudad.py reunion`. **Cambio:** el corrillo cuenta su rumor **en cuanto se forma** (cada 10 min; uno por punto
> mientras dura la burbuja, 50 min) y no una vez por hora (con la hora en punto se deshacían antes de hablar). Lo oye
> cualquiera de la familia del jugador a ≤ 4 casillas (no solo el seleccionado), una vez por rumor. El libro es la
> pestaña **«Rumores» del libro de cuentas**, con el día, el sitio y la marca «Útil». Fuentes (`data/life/rumors.json`):
> la crónica de los últimos 4 días (bodas, nacimientos, muertes, títulos, cargos, condenas, peleas, duelos, asaltos y
> secuestros), las deudas de otras familias, los precios de otra población, las elecciones abiertas, los eventos en
> vigor, el tablón, el último forastero, lo que cuenta un mercader de su ciudad y los bandidos vistos la víspera de un
> asalto. Una noticia ya oída se cuenta menos (×0,25).

#### 4.24.3 Más población y forasteros

- **Población fija** (`data/town.json` → `population`): `max_total` pasa de 20 a **una cifra por mapa, 5 por casa**
  (O-R9 b), con un tope por rendimiento. Para `town_e` se propone 32 (hoy 20) [balance]. **Mueve las dianas**,
  porque hay más clientes y más bodas: se mide y se propone la banda nueva (principio 4).
- **Forasteros** (4.22.3.6, adelantado): de 2 a 4 al día [balance], más en las fiestas (×3) y en la feria (×5).
  Llegan por las puertas desde **una ciudad de la región** (Portvell, Bellcaire…), que se ve en su ficha y en su
  ropa. Duermen en la posada si hay sitio (4.27). Si no, se van al atardecer. Tipos [balance]:

| Tipo | Peso | Qué hace | Bolsa |
|---|---|---|---|
| Mercader | 30 % | compra y vende en la plaza y deja precios de su ciudad (rumor) | 40-120 |
| Peregrino | 20 % | va a la iglesia o a Montsacre; duerme en la posada | 10-30 |
| Buhonero | 15 % | monta un puesto un día | 20-50 |
| Juglar o cómico | 10 % | actúa en la plaza o en la taberna (espectáculo) | 5-20 |
| Soldado de paso | 10 % | taberna, pelea fácil | 15-40 |
| Noble de viaje | 5 % | posada buena y comida cara; puede ser rehén (4.24.5) | 80-200 |
| Mendigo | 10 % | pide limosna en el atrio (dar sube la reputación +1) | 0 |

- Son personajes temporales de `fam_visitors`, como dice 4.22.3.6. `state.town.visitors` guarda los vivos (tope
  12, o 30 en la feria).

> [!NOTE]
> **Construido.** Tope de vecinos por mapa: `data/life/life.json` → `population` (5 por casa hasta 32; un mapa puede
> fijar `population_max`), solo con la vida encendida. **Medido (O-V2):** town_e pasa de 16 a 21 vecinos en 10 años,
> 29 en 20 y 30-32 desde el año 30, con 6 solteras fértiles al final; en las partidas de 10-24 días de las dianas de
> economía el tope casi no se alcanza. La diana de H7 (`town_population` [14, 22]) no cambia (se mide con la vida
> apagada); la nueva `town_population_life` propone [14, 32], **pendiente del owner**. Forasteros: 2-4 al día
> (medido 3,25), de una población de la región con su ropa (`city_dress`, el shader de identidad), entran por una
> puerta, siguen el plan de su tipo (`visitors.kinds`) y **se van al atardecer** por la misma puerta (dormirán en la
> posada cuando exista: 4.27); al irse salen del estado. El juglar monta un espectáculo en la plaza y los vecinos van a
> mirarlo. Limosna: orden `give_alms` (1 de oro, +1 de reputación una vez al día por familia).

#### 4.24.4 La guardia

Adelanta 4.22.6.2 lo justo para la vida de la ciudad. Lo demás (detención por delitos del jugador o el Alguacil
eligiendo patrullas) llega con 4.22.

- **Quiénes:** familia `fam_watch` («Guardia de la villa»), creada con la partida: **2 en las puertas de día**
  (uno en cada puerta principal), **2 de patrulla de noche** y 1 en la plaza en los días de fiesta y de feria
  [balance]. Arte Marcial 6, Constitución 6, espada y armadura (4.22.6.2). Su ropa es la librea de la villa, con
  el color del concejo.
- **Puertas:** el guardia de la puerta saluda a los forasteros, «cobra el portazgo» (cosmético; el peaje de verdad
  es el de las rutas, 09b) y no deja entrar a nadie de noche.
- **Patrulla:** rutas de patrulla del mapa (`patrols`) que el generador de ciudades pone por las calles mayores y
  la plaza. Llevan farol de noche.
- **Respuesta:** un altercado, un asalto o un grito a ≤ 12 casillas hace que vayan (4.22.6.2). Si llegan, separan
  la pelea (4.24.5) o se enfrentan a los bandidos.
- **El concejo paga** la guardia (no sale en ningún libro, O7 de 4.22). Un cargo de Alguacil (H10) tiene, como
  poder pasivo, +1 guardia de noche [propuesta].

> [!NOTE]
> **Construido.** `fam_watch` (como `fam_visitors` y `fam_bandits`: familias de servicio, `controlled_by: town`; no se
> contratan, no se casan ni cuentan como vecinos) con cinco guardias: dos de puerta (puesto a 3 casillas dentro de la
> puerta, en la calle; saludan al forastero que entra), dos de ronda por las `patrols` del mapa (`patrol_main` de
> puerta a puerta por la plaza y `patrol_plaza`, que pone `citylib.add_life`), con farol de mano, y uno en la plaza en
> fiesta. El Alguacil es el cargo `constable` (+1 de noche si está ocupado). Fuera de turno no están en el mapa (el
> cuerpo de guardia es la puerta del ayuntamiento). Un grito a ≤ 12 casillas los manda; «dar la alarma» los llama a
> todos. Librea: `watch.livery` (rojo oscuro y oro), teñida con el shader hasta el arte del 15-nov.

#### 4.24.5 Sucesos: altercados, bandidos y secuestros

Son eventos **locales** de `data/events.json` con un flujo de azar propio (`events_city`), **apagados en los
escenarios de las dianas** (`_no_events`), con su carta, su aviso y su entrada en la crónica.

| Suceso | Cuándo | Qué pasa | Qué puede hacer el jugador | Frecuencia [balance] |
|---|---|---|---|---|
| **Altercado** | ATARDECER y NOCHE, cerca de la taberna o en la plaza en fiesta | Dos NPC con relación ≤ −20, o uno borracho y otro ofendido, se pelean (combate del duelo, a toques, sin heridas). Corrillo de mirones. | Separarlos (Carisma o Arte Marcial contra la rabia: +reputación y relación con los dos), apostar (4.26.6) o mirar. Si llega la guardia, multa 10-20 al que empezó (hecho «pelea» del tribunal, H11). | ~1 cada 2 días; ×2 en fiesta |
| **Asalto de bandidos** | NOCHE, desde fuera del mapa | Una banda de 2-4 bandidos (Arte Marcial 4-6) entra por una puerta o por el campo y va a un almacén, un carro o una casa del borde. Rompe la cerradura y se lleva mercancía u oro. | Defender (combate del duelo, uno contra uno, con aliados), dar la alarma (los guardias llegan en 10-20 min) o esconderse. La Seguridad del edificio (4.8: cerradura y guardia contratado) baja la probabilidad de que elijan tu casa. | 1 cada 2-3 estaciones [balance]; más en guerra y en invierno; nunca el primer año |
| **Secuestro** | NOCHE o en el camino (viajes, 09b) | Los bandidos se llevan a un rico: un forastero noble, el hijo de un patricio o, rara vez, un familiar del jugador (nunca el cabeza de familia ni un niño de menos de 8). Llega una nota de rescate: oro en 2 días al Nido del camino (ruta de la región). | **Pagar** (sale libre). **Negociar** (Retórica contra el jefe: −30 % o +50 %). **Rescatar**: contratar a la guardia o a mercenarios (15-30 oro cada uno) e ir al Nido; se resuelve con combates del duelo en cadena y se puede «Resolver sin jugar». **No hacer nada**: si es de tu familia, vuelve a los 4 días con «asustado» y −10 de reputación («no pagó por los suyos»). Si es de otra familia y lo rescatas tú, +15 de reputación y +30 de relación con esa familia. | 1 por año como mucho; nunca antes del año 2 [balance] |
| **Ladrón nocturno** | ya existe (H7, 4.20) | — | Ahora la guardia de noche puede verlo (4.22.6.2): solo puede bajar los robos. | igual que hoy |
| **Incendio** [propuesta, O-V6] | DÍA o NOCHE, en verano o en fiesta de hogueras | Arde un edificio de madera o un pajar; los vecinos hacen cadena con cubos desde el pozo. | Ayudar a apagarlo (+reputación); el dueño pierde parte del almacén si no se apaga en 1 h. | 1 cada 2 años |

- **Sin muertes** (O4). Hasta que exista la salud de 4.22.3.3, perder un combate deja **«asustado»** y la bolsa,
  no una herida. Cuando llegue la salud, «herido 24 h».
- **Riesgo justo:** el suceso avisa antes (los perros ladran, un rumor de «bandidos por el Coll» la víspera, una
  nota en el tablón) y la carta deja elegir. Nunca te quita más del 10 % del oro ni más de 3 objetos de un
  almacén.
- **Los bandidos vienen de algún sitio.** Salen del Nido de la ruta con más riesgo (09b) y la IA del Bandido de
  4.22 los reutilizará. Si la guardia los vence, el Nido queda «escarmentado» y no vuelven en 1 año.

> [!NOTE]
> **Construido.** **Cambio de sitio:** van en `data/life/incidents.json`, no en `data/events.json` (WorldEvents tira
> por cada definición de events.json y un suceso nuevo movería sus tiradas y su `max_active`); los eventos los
> multiplican con `{kind: incident, id, mult}`. **Altercado:** entre 18 y 22 h (no hasta las 02:00: de noche están
> todos en casa y salían 0,12 al día; ahora ~0,46), dos vecinos o un soldado de paso cerca de la taberna o de un punto
> de la plaza; pelea con `Duel.auto` a primera sangre y a puño; mirones; la guardia que llega la para y multa 10-20 al
> que empezó (hecho «brawl» si es de una familia jugadora). **Asalto:** se tira al alba del día anterior para que ese
> día haya aviso y rumor (riesgo justo); va a un edificio del borde (el tercio más alejado de la plaza, O-V4 a) con
> peso 1 − su Seguridad; 2-4 bandidos entran por la puerta más cercana; la carta (Defender, Alarma, Esconderse) sale al
> llegar a la puerta; topes del 10 % del oro y 3 piezas (comprobados por el bot `guard_watch`). **Secuestro:** se tira
> al alba del mismo día, entre las 17 y las 02 h (para que haya nobles forasteros antes de irse); víctimas con peso
> sobre todos los tipos (un tipo sin nadie = no hay secuestro: los familiares del jugador, ~8 % de las tiradas);
> la víctima queda fuera del mapa (`captive`, como de viaje). **Pendiente:** jugar la cadena del rescate en la
> pantalla del duelo (hoy se resuelve sin jugar, con las mismas probabilidades) y apostar sobre un altercado (4.26.6,
> bloque Juegos).

---

### 4.25 El calendario de fiestas

#### 4.25.1 Las fiestas fijas del año

Ocho días por año, ocho momentos del calendario medieval (hispano, catalán y castellano). Cada uno cae en su día y
dura lo que pone la tabla. Las grandes paran el trabajo (día de guardar) y las pequeñas solo llenan el atardecer.

| Día del año | Fiesta | Grande / pequeña | Qué es | Qué cambia |
|---|---|---|---|---|
| Primavera 1 | **Semana Santa** | grande | Cuaresma y Pascua: procesión de penitentes, misa mayor; de Pascua, el cordero | Procesión por la calle mayor. Antes (DÍA): carne ×0,6 en demanda (Cuaresma). Después (ATARDECER): la Pascua, cordero y pan ×1,5. Talleres cerrados por la mañana. |
| Primavera 2 | **Los Mayos y el Corpus** | grande | Se planta el mayo (árbol) en la plaza y se cantan coplas. El Corpus es la procesión con la custodia, entremeses y, en Castilla, **toros** | Procesión y toros (4.26.5) por la tarde. Carpintero: tablados, carros y el cerco para los toros (encargos). Sastre: pendones. |
| Verano 1 | **San Juan** | pequeña | La noche más corta: hogueras, verbena, saltar el fuego, agua de San Juan | Hogueras en la plaza y las calles (luz), baile toda la noche, la taberna ×2. Riesgo de incendio ×3 (si O-V6). |
| Verano 2 | **La siega y la feria** | grande | Se acaba la siega; **feria anual** con privilegio real: mercaderes de toda la región, ganado y titiriteros | La **feria** (4.25.3): puestos de forasteros, arancel 0 (feria franca), rutas temporales, ganado, juglares y carrera de caballos (4.26.4). Forasteros ×5. |
| Otoño 1 | **San Miguel y la vendimia** | pequeña | Se cierran contratos y rentas (San Miguel) y se pisa la uva | Encargos de toneles y prensas (carpintero) y de herrajes (herrero). Las deudas y rentas «vencen» (cosmético en la crónica). |
| Otoño 2 | **Todos los Santos y San Martín: la matanza** | grande | Difuntos y castañas; por San Martín, la **matanza del cerdo**: el pueblo mata, hace embutido y come junto | **Banquete común** en la plaza (4.25.4). Carne ×0,5 de precio (abundancia). Encargos de cuchillos y ganchos (herrero), mesas largas (carpintero) y saladeros. Visita al cementerio. |
| Invierno 1 | **Navidad** | grande | Misa del gallo, belén, aguinaldos y banquete | Misa a medianoche, banquete en casa, aguinaldos (los empleados esperan +1 día de sueldo: lealtad +5 si se lo das), regalos entre familias (+relación). Lujo ×1,3. |
| Invierno 2 | **Carnaval** | pequeña | Antes de Cuaresma: máscaras, excesos, el «gallo», bromas a las autoridades | Disfraces (vista), taberna ×2, altercados ×3, el Alcalde sufre una burla (−2 de reputación al Alcalde, +social a todos). |

- **La fiesta patronal** de cada ciudad es su **día grande propio**, que cae sobre uno de los días «pequeños»: en
  Vilarrasa, **Sant Martí** (se une a la matanza); en Bellcaire, Sant Jordi (Primavera 2, con justas); en Portvell,
  la Virgen del Carmen (Verano 1, procesión de barcas); en Peñarroja, Santa Bárbara (Invierno 1, patrona de los
  mineros); en Vilablat, San Isidro (Primavera 2, bendición de los campos); en Montsacre, la fiesta del santo
  fundador (Otoño 1, romería). Todo esto sale de `data/world/region.json` → `patron_feast` [propuesta, O-V1].
- **Cada fiesta se anuncia la víspera** con el **pregón** (el pregonero en la plaza; carta, aviso y rumor) y abre
  sus encargos (4.25.4) **un día antes**, para que dé tiempo a fabricar.

#### 4.25.2 Eventos que no son de calendario

Caen al azar (flujo `events_city`) o los declara el Alcalde (poder `declare_event`, H13).

| Evento | Duración | Cuándo | Qué trae |
|---|---|---|---|
| **Visita del marqués** (o del obispo, o del infante) | 1 día, anunciada 2 días antes | 1 cada 2 años; nunca en la feria | Recibimiento con arco triunfal (albañil y carpintero), banquete (comida), vestidos nuevos (sastre) y un regalo de la villa (una pieza excelente: la elige el concejo entre las ofrecidas). **Audiencia:** las familias con título de Ciudadano o más piden audiencia; con un buen regalo y Retórica, privilegios (−1 año al próximo título, exención de un arancel o un cargo menor sin elección) [balance]. Su séquito llena la posada. |
| **Boda de una familia noble o rica** | 1 día | cuando dos personajes de rango alto se casan (H8) | Banquete, encargos de oficio (4.25.4), invitados de fuera, baile, quizá una justa. La boda del jugador también la abre, si paga el banquete. |
| **Boda de vecinos** | ATARDECER | cuando dos vecinos se casan (renovación, 4.11.1) | Encargos pequeños (vestido, arcón de dote), baile en la plaza y cencerrada si son viudos. |
| **Torneo** | 1 día | en la fiesta patronal de Bellcaire o con la visita del marqués; o lo convoca el Alcalde | Justas y torneo de lucha (4.26). |
| **Compañía de cómicos** | 1-2 días | 1 por año | Representación en la plaza (espectáculo), la taberna ×1,5, el carpintero monta el tablado. |
| **Predicador** | 1 día | 1 por año | Sermón en la plaza: `faith` +40 a todos y, durante 1 día, el juego está mal visto (dados ×0,3) y se quema algo de lujo. |
| **Romería a Montsacre** | 1 día | en la fiesta de la abadía | La villa camina a la abadía (viaje abstracto, 09b): peregrinos en la posada, comida de romería, encargos de la abadía (velas, pan y vino), un banquete del monasterio. |
| **Rogativa** | ATARDECER | con sequía o hambruna (H13) | Procesión pidiendo lluvia; `faith` +; ninguna regla más. |
| **Ferias de ganado** (mercado franco) | 1 día | 1 por estación en las ciudades con feria | Ganado, carros y caballos a la venta, y una carrera de caballos. |

#### 4.25.3 Qué cambia en la ciudad durante una fiesta

**En el sim** (declarativo, en `data/festivals.json`; los efectos que ya existen y unos pocos nuevos):

| Efecto | Ejemplo | Existe |
|---|---|---|
| `demand {group, mult}` | carne ×0,6 en Cuaresma, lujo ×1,3 en Navidad | sí (H13) |
| `price {group, mult}` | carne ×0,5 por la matanza | sí |
| `counter_clients {mult}` | ×1,5 en feria | sí |
| `service {id, mult}` | taberna ×2 en San Juan | gancho de 4.22.3.2 |
| `visitors {mult, kinds}` | ×5 en la feria, nobles con el marqués | nuevo (4.24.3) |
| `routine {activity, mult}` / `holy_day` | la procesión ×5; día de guardar, trabajo ×0,3 | nuevo (4.24.1) |
| `stalls {kind, count}` | 6 puestos de forasteros en la feria | nuevo |
| `tariff {city, mult}` | feria franca: arancel 0 | 09b |
| `route_bonus {route, days}` | ruta temporal: la feria de Bellcaire invita y el portazgo a Bellcaire es 0 durante 2 días | 09b |
| `contracts {table}` | abre los encargos de fiesta (4.25.4) | 4.5.6 |
| `emotion {id, share}` | «inspirado» al 50 % tras la fiesta | 4.11.5 |
| `spectacle {id}` | toros, justa, cómicos, carrera | nuevo (4.26) |
| `incident {id, mult}` | altercados ×3 en Carnaval | 4.24.5 |
| `reputation {who, amount}` | el que patrocina +; el Alcalde −2 en Carnaval | sí |

**En la vista** (`data/festivals.json` → `view`; lo pinta `world_view` con capas por evento; nada lo lee el sim):

- **Decoración:** guirnaldas y banderolas entre casas de la calle mayor, pendones en el ayuntamiento, el mayo en la
  plaza, hogueras (San Juan), farolillos, el arco triunfal (visita), el tablado (cómicos), el cerco de carros para
  los toros, la liza de la justa, las mesas largas del banquete, el belén en el atrio (Navidad), los puestos de
  feria con toldos de colores y los corrales de ganado.
- **Gente:** máscaras en Carnaval, capirotes y cirios en la procesión, ropa de fiesta (el shader de identidad cambia
  la paleta de ropa a una «de domingo»), el séquito del marqués con su librea, los forasteros con la ropa de su
  ciudad y los animales (cerdos en la matanza, ganado en la feria, caballos en la carrera, el toro).
- **Ambiente:** música por fiesta (gaita y tamboril, campanas, coros), luz cálida de hogueras y campanas al empezar.
- **La carta de la fiesta** (kit de página): ilustración, qué es, qué cambia hoy (efectos en lenguaje claro), qué
  encargos hay y a qué hora es cada cosa (procesión 10:00, toros 17:00, baile 21:00).

#### 4.25.4 Encargos de fiesta y de boda

Lo que pidió el owner: que cada oficio tenga su gran encargo. Salen en el tablón **la víspera**, pagan mucho más que
los normales, piden **calidad** y dan **prestigio** (reputación y relación con quien encarga). Van en una tabla
`data/contracts/festivals.json`, por evento y por oficio [balance]:

| Evento | Herrero | Carpintero | Albañil | Sastre | Comida (taberna, posada o el que venda comida) |
|---|---|---|---|---|---|
| Boda rica | **espada decorativa de regalo al novio** (pieza nueva, excelente; ×3 del precio de una espada) | **arcón de dote** y **cama nupcial** | — | **el vestido de la novia** (pieza nueva; ×4 del precio de ropa fina; excelente da +10 de reputación con la familia) y el jubón del novio | **banquete** (X comidas + Y cervezas o vino) |
| Boda de vecinos | herraduras para el carro, un cuchillo | arcón sencillo | — | vestido sencillo | merienda |
| Visita del marqués | regalo de la villa (si te eligen) y rejas | arco triunfal (con el albañil) y tribuna | arreglo de la fachada del ayuntamiento | vestidos del concejo y pendones | banquete de honor |
| Matanza (San Martín) | cuchillos de matarife y ganchos | mesas largas, bancos y artesas | el saladero | delantales | el banquete común (lo paga el concejo) |
| Corpus y toros | rejas y barrotes del toril | **tablados y el cerco de carros** | — | pendones y la ropa de la procesión | — |
| Feria | herraduras y clavos (hay caballos y carros) | puestos de feria | — | toldos | comida para los forasteros |
| Navidad | adornos de hierro y candelabros | el belén y juguetes | — | ropa de fiesta | banquete de Navidad |
| Fiesta del monasterio | campana nueva [propuesta] | sillería del coro | arreglo del claustro | hábitos y paños de altar | pan y vino de la romería |
| Torneo | **armas de torneo y armaduras** | lanzas de torneo y la liza | — | sobrevestas y gualdrapas | comida para el público |

- **Piezas nuevas** (recetas con su dibujo en la lista de arte): `decorative_sword`, `wedding_dress`, `doublet`,
  `dowry_chest`, `marriage_bed`, `tourney_lance`, `banner`, `stage` (tablado: un encargo «de obra» que se monta
  in situ, como las mejoras de 4.8), `triumphal_arch` (obra) y `feast` (lote de comida). Las de obra se construyen
  en el sitio con los materiales del taller.
- **Competencia:** el rival del mismo oficio también puede coger el encargo. El que antes lo entregue con la calidad
  pedida se lo lleva (como los encargos de hoy, pero con un solo ganador).
- **Prestigio:** cumplir un encargo de boda rica o de la visita da reputación +5 a +10, relación +20 con quien
  encarga, y una entrada en la crónica («Los Molledo forjaron la espada que el marqués regaló al novio»).

#### 4.25.5 Patrocinar y organizar

- **Patrocinar** una fiesta (cualquier familia, la víspera): pagar parte del banquete, la música o los toros.
  Da reputación según lo que pongas, sale en el pregón («gracias a la casa Molledo») y sube la relación con todos
  los vecinos que vayan. Si no patrocina nadie, la fiesta es más pobre (menos efectos y menos visitantes).
- **El Alcalde organiza:** decide si hay toros o justa en la fiesta patronal (cuesta dinero del concejo, poder
  activo nuevo `organize_festival`), declara la fiesta y la festividad (ya existe), y en la visita del marqués elige
  el regalo de la villa entre las piezas que le ofrezcan.
- **Las familias rivales** (04c) patrocinan si les sobra el oro y quieren reputación. Es un uso nuevo del módulo de
  reputación de la IA: va en la revisión de 04c [propuesta].

#### 4.25.6 Las fiestas de las otras ciudades

- Cada ciudad de la región tiene su patronal y su feria (4.25.1). **Se anuncian en el mapa regional** y por rumor.
- **Rutas temporales:** durante la feria de una ciudad, su portazgo baja a 0 y su demanda de ciertas cosas sube
  (Bellcaire en Sant Jordi: armas y ropa fina). Es la ocasión de viajar o mandar una caravana (09b).
- **Visitas:** en tu fiesta llegan forasteros de las otras ciudades (4.24.3). En la suya puedes ir tú (viaje,
  09b): en la página de la ciudad sale su fiesta con sus juegos (justa, carrera, dados) y sus encargos de fuera.

#### 4.25.7 Cómo quedó construido (rama fiestas, 2026-11-04)

Lo que cambió al construirlo, y por qué (también en `docs/decisiones.json`):

- **El día 0 no hay fiesta** (`rules.first_day` 1). La partida empieza la mañana de la Semana Santa; si cayera, el
  primer día del tutorial sería día de guardar. La primera Semana Santa es la del año 2 (día 8). El primer pregón es
  el del día 0 a las 12:00: los Mayos.
- **Pregón a las 12:00 de la víspera** (`eve_hour`) y **encargos que vencen a las 17:00 del día de la fiesta**
  (`contracts.due_hour`): unas 29 horas para fabricar. La visita del marqués se anuncia dos días antes.
- **No hay carne en el juego**: la Cuaresma, la Pascua y la matanza mueven el grupo `food` (demanda ×0,8 hasta las
  17:00 y ×1,5 después; precio ×0,6 en la matanza).
- **Día de guardar solo por la mañana y solo en tres fiestas** (Semana Santa 07-12 ×0,3, Todos los Santos 07-10 ×0,5,
  Navidad 07-10 ×0,5). Parar el trabajo en las cinco grandes quitaba la mitad del año. En el sim es la velocidad de
  producción de todos los ciclos que empiezan en esa ventana; para los NPC, el gancho `Festivals.holy_day`.
- **Las obras se hacen en el taller** (`stage`, `triumphal_arch`): son piezas que se fabrican y se montan al
  entregarlas; la vista pinta el arco y la tribuna cuando el encargo se ha cumplido (`needs_contract`). Montarlas a
  pie de obra llegará cuando el mapa tenga obras.
- **Tres piezas pequeñas más para el herrero** (`horseshoe`, `butcher_knife`, `candlestick`): la tabla de 4.25.4 le
  pide herraduras, cuchillos de matarife y candelabros, y no existían.
- **Recetas por encargo** (`kind: commission`): salen en el taller del jugador, pero los bots y la IA rival no las
  eligen para vender en el mercado (no tienen puesto). Así las dianas de siempre salen iguales.
- **Un solo ganador, con órdenes de verdad**: el encargo de fiesta sigue en el tablón mientras dura la carrera; cada
  familia que lo acepta tiene su copia; la primera que lo entrega con la calidad pedida cobra, gana su reputación y
  relación (también con la familia de la boda) y, si la fila lo dice, sale en la crónica; las demás lo pierden sin
  castigo. El rival del oficio compite con su IA de siempre (04c acepta lo que puede fabricar a tiempo). Una fila
  solo se publica si en la villa hay una familia (del jugador o IA) con el taller de ese oficio.
- **La comida** de los banquetes se pide como `prepared_meal` o `bread` (cualquiera la lleva). La pieza `feast`
  existe sin receta: la cocina de la Taberna-Posada (4.27) le pondrá la suya.
- **No hay tesorería del concejo**: `organize_festival` (toros o justa, cada 2 días de enfriamiento) no cobra a
  nadie; el coste queda en los datos para cuando la haya. La justa abre un torneo ese mismo día.
- **La boda del jugador** abre una carta con «Pagar el banquete (80)» durante un día; los encargos de una boda no los
  puede coger la familia que se casa (es su propia boda).
- **Patrocinios**: banquete, música y, si la fiesta los tiene, los toros. Sin patrocinio, los forasteros ×0,7. El
  patrocinio de la IA rival: de momento no (manager, a la espera del owner; iría en la revisión de 04c).
- **El regalo de la villa** en la visita del marqués es un encargo de carrera (la espada excelente); que el Alcalde
  elija entre varias piezas ofrecidas y la audiencia con privilegios: de momento no (manager, a la espera del owner).
- **Fiestas de las otras ciudades**: la patronal y la feria caen el mismo día (Bellcaire en Primavera 2, Portvell en
  Verano 1, Montsacre en Otoño 1, Peñarroja en Invierno 1, Vilablat en Primavera 2); la de Vilarrasa es la de la siega
  (Verano 2). Durante la feria: arancel 0 en esa ciudad, sin portazgo en sus caminos desde el día antes y su demanda
  sube. Son puro calendario (no se guardan).
- **Enganchado con vida** (2026-11-04, tras juntar su rama): `Life.event_mult` multiplica por la fiesta (`routine`
  e `incident` a su hora; `visitors` con las fiestas de todo el día, porque vida planea los forasteros al empezarlo),
  `Life.holy_day` cuenta la mañana de guardar y `Life.festival` cualquier fiesta del calendario (el guardia de la
  plaza). Con una fiesta del calendario no se suma además el ×3 genérico de vida: la feria da ×5 (×3,5 sin
  patrocinio, y entonces el tope de la feria, `fair_max`), y los tipos que trae la fiesta pesan el doble. Los
  espectáculos de la fiesta entran en la plaza como espectáculos de vida (los vecinos van a mirar, `watch_show`) y el
  predicador sube la fe de los vecinos al empezar. Los ids de actividad y de suceso son los de `data/life/`:
  procesión y romería → `mass`, baile → `stroll`, hogueras y banquete → `chat`, cementerio → `visit`, altercados →
  `altercation` (el incendio espera a O-V6). Quedan para sus ramas `spectacle` jugado (juegos) y `service` (posada).
- **Las dianas**: `sim_runner` apaga las fiestas para todos los bots salvo los de `data/targets.json` `_festivals`
  (hoy, `festive`). En el juego están encendidas.

---

### 4.26 Juegos y competiciones (minijuegos)

Todos siguen la regla del duelo (04e): **decisiones legibles, no reflejos**, cortos (menos de 1 minuto), con
«Resolver sin jugar», reglas puras y deterministas en el sim, cifras en `data/games.json` y una pantalla propia.
Se juegan en las fiestas, en la taberna o donde el evento lo pida.

#### 4.26.1 Justa (torneo a caballo)

- **Tres pasadas** contra un rival. En cada una eliges **dónde apuntas la lanza** (yelmo, escudo o pecho) y
  **cómo te cubres** (escudo alto, medio o bajo). El rival hace lo mismo. Apuntar donde él no cubre es acierto.
  Apuntar al yelmo es difícil (Destreza), pero si aciertas lo desmontas. El escudo da medio punto seguro.
- **Lectura**, como el duelo: el caballo del rival y su postura dan una pista, con su fiabilidad (Empatía contra
  Arte Marcial).
- **Puntos:** lanza rota en el escudo 1, en el pecho 2, desmontar gana la justa.
- **Quién entra:** hace falta un título de Ciudadano o más (o ser noble), un caballo (alquilado en la feria o
  propio, D8) y una lanza de torneo (encargo del carpintero). Premio: una bolsa, reputación +10 y el favor de una
  dama o un caballero (cortejo +15).

#### 4.26.2 Torneo de lucha

- **Eliminatoria de 8** con el duelo de 04e, en la modalidad **«a tres asaltos, por puntos»**, sin heridas
  (O-C11 c, que el owner dejó para las fiestas). Con espada de torneo, bastón o a puño, según el torneo.
- Entran tus personajes y los NPC con Arte Marcial ≥ 4. Las rondas se juegan seguidas: el aliento no se recupera del
  todo entre ellas (+2).
- Apuestas sobre cada combate (4.26.6). Premio: bolsa y reputación.

#### 4.26.3 La sortija

- **Correr la sortija:** a caballo, al galope, hay que ensartar con la lanza una anilla colgada. Tres carreras.
- En cada una eliges el **ritmo** (prudente, firme o a todo galope) y el **momento** de bajar la lanza entre tres
  señales. A más galope, más puntos si aciertas, pero la ventana es más pequeña (Destreza).
- Es la justa de los que no tienen título: cualquiera con caballo.

#### 4.26.4 Carrera de caballos

- **Cuatro tramos** (salida, recta, curva del molino, meta) contra 3-5 jinetes.
- En cada tramo eliges el **ritmo**: reservar, mantener o apretar. Cada ritmo gasta **fuelle** del caballo (como el
  aliento del duelo: apretar −3, mantener −1, reservar +1). En la curva, apretar puede costar un tropiezo
  (Destreza). Gana quien llegue primero; un caballo sin fuelle solo puede reservar.
- **El caballo importa:** velocidad y fuelle por caballo. En la feria se compran y se alquilan (D8: carros y
  caballos con coste).
- Se apuesta (4.26.6). Premio: el palio (un paño de seda: objeto de lujo) y reputación.

#### 4.26.5 Los toros

En la Edad Media no había matadores: se «corría el toro» en la plaza cerrada con carros, y los mozos lo citaban y
lo esquivaban (en algunas villas, el toro ensogado).

- **Mirar:** espectáculo, `fun` +40 a todos.
- **Correr el toro** (minijuego): tres embestidas. En cada una eliges **citar**, **quebrar** (esquivar en el último
  momento) o **ponerte a salvo** tras los carros. El toro avisa con su pista (escarba, baja la cabeza, se arranca)
  y la lectura es Destreza contra la bravura del toro. Quebrar bien da aplausos (reputación +2 por quiebro). Fallar
  da **«asustado»** y burla, nunca una herida mientras no exista la salud de 4.22; con salud, «herido» con un 10 %
  [balance].
- El cerco lo monta el carpintero (encargo) y los toros los paga el concejo o un patrocinador.

#### 4.26.6 Apuestas

- **Sobre cualquier competición:** justa, torneo, carrera, toros (¿quién aguanta?), peleas y altercados.
- Ves las **cuotas** que da el corredor de apuestas (un NPC en la plaza o el tabernero), calculadas a partir de las
  probabilidades del sim con un margen de la casa del 10 % [balance]. Apuestas 5, 10, 25 o 50 de oro.
- **Apostar por ti mismo** está permitido; apostar contra ti mismo y perder adrede es **fraude** (delito «trampa»,
  si te ven).
- El oro de las apuestas viene de y va a fuera (P4) salvo la parte de la casa, que es para el dueño de la taberna si
  la apuesta se hace allí (4.27).

#### 4.26.7 Dados

Inspirados en el **Libro de los juegos** de Alfonso X (1283), que describe los juegos de dados de Castilla.

- **«Azar»** (el juego del que viene la palabra): se tiran **tres dados**. En la primera tirada, sacar mucho (15-18)
  o poco (3-6) es **azar** y gana quien tira. Con un número del medio, ese número es la **suerte** del contrario y
  se sigue tirando hasta que salga una de las dos suertes [simplificación de la regla, documentada]. El jugador
  **apuesta y decide si dobla** tras ver la suerte (la decisión es cuánto arriesgar, no los dados).
- **«Tres dados a la mayor»**, el sencillo: contra 1-3 jugadores; tras la primera tirada se puede **retirar** (pierde
  la mitad) o **seguir** (doble o nada). La personalidad del rival se ve: el atrevido dobla siempre.
- **Dados cargados:** un Pícaro (o quien los compre a un buhonero) puede usarlos. Dan ventaja, y si te pillan
  (Empatía del rival contra tu Destreza) son delito «trampa» y altercado. Así enlaza con 4.22.
- **La tafurería:** en Castilla el juego se hacía en casas con licencia del concejo. Jugar en la calle está mal
  visto en días de predicador. La taberna puede comprar la **licencia de tafurería** (4.27.4) y ganar la parte de la
  casa.

#### 4.26.8 Naipes

Los naipes llegan a la Corona de Aragón a finales del siglo XIV (hay noticias de ellos en Barcelona hacia 1380).
Para el juego proponemos el **«envite»**, en la familia de los juegos de envites y faroles como el truc:

- **Tres cartas por jugador**, de una baraja de 40 de cuatro palos (oros, copas, espadas y bastos).
- **Tres bazas.** Antes de cada una se puede **envidar** (subir la apuesta). El rival **quiere** (acepta), **sube**
  o **no quiere** (pierde lo que había).
- **El farol** es el centro del juego: el rival enseña un **gesto** (como en el duelo) y su fiabilidad depende de tu
  Empatía contra su Retórica. Un buen lector sabe cuándo el otro va de farol.
- Se juega en la taberna contra 1-3 NPC (los parroquianos tienen su carácter: el prudente, el fanfarrón o el
  tramposo).

#### 4.26.9 Pulso

- En la taberna o en la plaza, contra un parroquiano. Son **tres empujes**: en cada uno eliges fuerza, aguantar o
  ceder, con una barra de fuerza (Constitución) y la pista del rival. Gana quien tumba el brazo dos veces. Es el
  más corto: unos 15 segundos.

---

### 4.27 La Taberna-Posada (con ideas de Wartales)

Adelanta 4.22.4.5 y la amplía. Es un **negocio nuevo para cualquier familia**: un segundo edificio que se compra o
se construye (4.9), con su interior, sus puestos y sus empleados. El oficio de Posadero sigue siendo del Patrón
cuando llegue 4.22. Hasta entonces, la familia que compra la taberna la lleva con empleados y con su gente.

#### 4.27.1 Qué tomamos de Wartales (*The Tavern Opens!*, 2024)

| En Wartales | En GuildMaster |
|---|---|
| Cada noche de acampada se juega un **turno** en la taberna | La taberna abre del **atardecer a las 02:00** y cada noche es un **turno** con su resumen (clientes, ventas, propinas, quejas) |
| La **carta**: platos y bebidas a partir de las recetas que conoces, equilibrando satisfacción y beneficio | La **carta** de 4.27.3: eliges qué se sirve y a qué precio, a partir de las recetas que sabe tu cocinero |
| Personal: reclutas civiles o compañeros de tu banda | Personal: empleados contratados (4.7) o miembros de tu familia (grupo 1-2-3) |
| **Clientela** por grupos, y al pasar por un grupo que no viene se ve por qué | **Clientela** de 4.27.2, con el «por qué no vienen» (precio, carta, ambiente, fama o reputación) |
| Mejoras como el **bardo** o la **pizarra de la carta**, que suben las ventas en la zona | Las mejoras de 4.27.5 (juglar, pizarra, chimenea, habitaciones), cada una con su efecto en cifras |
| Mudar la taberna a otra región al mejorarla | Más adelante, **abrir una segunda taberna en otra ciudad** de Valldaura (09b) [propuesta, O-V9] |
| El **equipo** sube la comodidad, la seguridad y la capacidad del local, y cada facción quiere su nivel de cada una | Tres cifras del local en el panel: **ambiente** (0-5, sube con chimenea y tapices, baja un día tras una pelea sin portero), **plazas** (las mesas) y **seguridad** (portero, cerradura, cuarto del portero); cada grupo pide la suya (los nobles, ambiente 3) |
| El **prestigio** del negocio se gana atendiendo bien y abre equipo mejor | La **fama** (0-5): +0,02 por cliente satisfecho, +0,02 por plato excelente, −0,04 por queja, −0,3 por pelea, −0,05 por cama sin hacer, como mucho +0,25 por noche; abre grupos (mercaderes con 1, nobles con 3) |
| Precios y **promociones** según la clientela que quieres | Precio de cada plato de 0,5× a 2× y el **plato de la casa** (×1,15 de atracción para los grupos a los que les gusta) |
| La **seguridad baja** atrae a facciones poco recomendables; los porteros (y los osos) paran peleas | Los soldados (y los jugadores) suben la probabilidad de **pelea**; el **portero** la para; sin él se rompen muebles y los peregrinos no vuelven en 2 noches |
| El **parte del turno** cuenta lo que pasó cada noche y los sucesos notables | La **carta del resumen** a las 02:00 (4.27.4) y la pestaña Turno con el historial de las últimas noches |
| El personal gana experiencia y desbloquea platos y bebidas | Los empleados ascienden con su rango (4.7.2): un oficial rinde el doble que un aprendiz en la cocina y sirve 1,5 veces más rápido |
| Rivalidad, espías y sabotaje entre tabernas | [POST-MVP] cuando haya una taberna rival (un proveedor NPC de 4.22.3.2) y el espionaje de 4.22.6.5 |

Fuentes consultadas (2026-11-04; ideas, no texto): la página de Steam de *Wartales – The Tavern Opens!*
(store.steampowered.com/app/2903960), la guía de Pro Game Guides «Wartales The Tavern Opens tavern guide: management,
shifts & more» (progameguides.com/wartales/wartales-the-tavern-opens-tavern-guide-management-shifts-more/), el análisis
de EIP «Open for business» (eip.gg/reviews/open-for-business-wartales-the-tavern-opens-dlc/) y las notas del parche en
SteamDB (steamdb.info/patchnotes/14097948).

#### 4.27.2 Clientela

Cada noche llegan clientes de **grupos** distintos. Cada grupo tiene sus gustos y sus pegas [balance]:

| Grupo | Viene si… | Pide | Gasta | Pega |
|---|---|---|---|---|
| Artesanos y vecinos | precio bajo o medio | cerveza, pan y empanada | poco | se van si tarda más de 30 min |
| Mercaderes y forasteros | hay camas libres y fama ≥ 1 | comida y vino, cama | medio-alto | quieren rumores de precios (cuentan los que oyen) |
| Peregrinos | hay camas baratas | sopa y cama | poco | no vuelven si hay pelea |
| Soldados y guardias | hay cerveza fuerte | mucha cerveza | medio | buscan pelea (altercados ×2) |
| Nobles y su séquito | fama ≥ 3, ambiente ≥ 3, vino bueno | carne asada, vino y habitación buena | mucho | quieren plato excelente y nada de soldados borrachos |
| Jugadores | hay mesa de dados o naipes y licencia | bebida | medio | traen tramposos |

- La **atracción** de cada grupo es la fórmula de 4.22.3.2 (precio, reputación y bonus de comercio) ×
  `gusto(carta, ambiente, fama)`. El panel **Clientela** enseña cuántos vinieron de cada grupo y, si un grupo no
  viene, **por qué** («Los nobles no vienen: fama 1 de 3; no hay vino bueno»).
- Las fiestas multiplican la clientela (San Juan y Carnaval ×2, la feria ×3) y traen grupos nuevos (el séquito del
  marqués).

#### 4.27.3 La carta

- **Platos y bebidas** (recetas `service` y `craft` de 4.22.4.5, ampliadas): cerveza, vino (comprado a Portvell o
  de la abadía, 09b), sidra, pan, sopa de ajo, empanada, olla, cordero asado (Pascua), embutido (la matanza), dulces
  de Navidad.
- Eliges **qué platos** van en la carta (como mucho 6 al principio; 8 y 10 con mejoras) y **a qué precio** (de 0,5×
  a 2× el de referencia, 4.22.3.2). La **calidad** de lo cocinado sube lo que paga el cliente (buena ×1,15,
  excelente ×1,3).
- **Los platos de temporada** (cordero en Pascua, embutido en San Martín, dulces en Navidad) dan ×1,5 de atracción
  en su fiesta.
- Si un cliente pide algo que no está en la carta o que se ha acabado, se va sin pagar y deja una queja.

#### 4.27.4 El turno de noche: atender

- **Puestos:** barra (servir bebida), cocina (cocinar), mesas (tantas como capacidad: 8 al empezar), recepción
  (camas) y, con mejoras, la mesa de juego y el rincón del juglar.
- **Cada cliente:** entra, se sienta, pide (un bocadillo con el icono del plato), espera con una barra de
  **paciencia**, le sirven, come, paga, deja **propina** según su satisfacción (tiempo de espera, calidad, ambiente)
  y se va. Algunos piden cama.
- **A mano** (el jugador o un familiar en la barra): clic en el cliente que espera, se le lleva lo que pide; es una
  gestión ligera, como en Wartales. **Con empleados:** los roles los llevan solos (tabernero, cocinero, mozo de
  mesas y criada de habitaciones), con la productividad de su rango (4.7.2).
- **Sucesos de la taberna** (de 4.24.5 y propios): pelea (el **portero**, si lo hay, la para; si no, rompe muebles,
  −ambiente 1 día), el que se va sin pagar (el mozo lo persigue: Destreza), el juglar que llena el local, un rumor
  jugoso o un forastero que propone una partida.
- **Resumen del turno** (carta al cerrar, a las 02:00): clientes por grupo, platos vendidos, ingresos, propinas,
  quejas, la fama ganada o perdida y los rumores oídos.
- **Habitaciones:** cada cama ocupada cobra al llegar (4.22.4.5) y **hay que hacerla por la mañana** (tarea de la
  criada, 20 min por cama). Una cama sin hacer no se alquila esa noche.
- **Licencia de tafurería** (el concejo, 60 oro y 1 año): permite la mesa de dados y naipes, se queda con la parte
  de la casa (4.26.6) y trae jugadores. Sin licencia, jugar en tu taberna es delito leve si lo ve el Alguacil.

#### 4.27.5 Mejoras (árbol de la Taberna-Posada, como el de la Forja de 4.8)

| Rama | Nivel 1 | Nivel 2 | Nivel 3 |
|---|---|---|---|
| **Salón** | más mesas (+4 plazas) | chimenea (ambiente +1; en invierno ×1,3 clientes) | tapices y vajilla buena (ambiente +1; vienen nobles) |
| **Cocina** | horno de pan | asador (platos de carne) | despensa fría (la comida no se pierde) |
| **Bodega** | toneles (más cerveza) | vino de reserva (vino bueno) | cueva de crianza (vino excelente) |
| **Habitaciones** | 4 camas más | habitación buena (nobles, ×2 de precio) | establo (caravanas y caballos: más mercaderes) |
| **Ambiente** | pizarra de la carta (+10 % de clientes en la calle) | rincón del juglar (satisfacción +; los cómicos actúan aquí) | mesa de juego (con licencia) |
| **Seguridad** | portero (para peleas) | cerradura de la bodega | cuarto del portero (vigila de noche) |

- **Fama** de la taberna (0-5): sube con clientes satisfechos y platos excelentes, baja con peleas, quejas y camas
  sin hacer. Cada nivel abre grupos de clientes (4.27.2) y mejoras.

#### 4.27.6 Rumores y la taberna

- La taberna es donde más rumores se oyen (4.24.2). Con el tabernero de buena lealtad, el resumen del turno trae
  **un rumor útil por noche** (precio de fuera, la deuda de un rival o el próximo evento).
- Es también donde llegan **los encargos de fuera** de forasteros y peregrinos (09b) y donde se apuntan los
  jugadores del torneo.

---

#### 4.27.7 Cómo quedó construido (rama posada, 2026-11-04)

> [!NOTE]
> Reglas en `sim/inn/` (Inn, InnClientele, InnStaff, InnRumors), cifras en `data/inn/` (inn.json, menu.json,
> clientele.json) y `data/services.json`, el edificio en `data/buildings/tavern_inn.json`, el árbol en
> `data/upgrades/tavern_inn/`, la vista en `game/inn/` (capa de huéspedes del interior, panel, carta del resumen),
> el bot `innkeeper` (`sim/bots/bot_innkeeper.gd`) y los escenarios `innkeeper_start` e `inn_night`
> (`tools/scenarios/make_inn_scenarios.gd`). Guardado v19 (`SaveFile._to_v19`).

Lo que precisa o cambia respecto a lo de arriba (apuntado en `docs/decisiones.json`):

| # | Qué | Por qué |
|---|---|---|
| T1 | **Se compra la del pueblo; construirla llega con H6.** Cada mapa tiene un solar con su Taberna-Posada **en venta** (`for_sale`, 320 de oro, orden `buy_building`); en `town_e`, el prado al sur del callejón de abajo. Solo en partidas nuevas (los guardados y escenarios de antes no la tienen). **Huella 3×4**, la de la carpintería, como su arte (fachada fal de 192×230); 4.22.4.5 proponía 4×4 la Taberna y 4×5 la Posada, que son un solo edificio aquí. | La construcción en parcelas (4.9) no existe todavía; comprar la de la villa da el segundo negocio de O-V7 (a) sin inventar H6. |
| T2 | **El tope de edificios por título (4.9) no se aplica** a la taberna: un Plebeyo puede tenerla. | H6 es quien aplica `max_buildings`; aplicarlo ahora dejaría a la taberna fuera del Artesano que empieza. Pregunta nueva O-V11. |
| T3 | **Turnos por rol:** barra y mesas trabajan de noche (de 30 min antes de abrir a las 02:00); cocina y habitaciones, de día (`work_schedule` del edificio). 3 plazas de empleado (barra, cocina, habitaciones) y la cuarta (mozo de mesas) con «Más mesas». El portero es la mejora, no un empleado. | La cocina tiene que tener la comida hecha al abrir y las camas se hacen por la mañana (4.27.4). |
| T4 | **Los clientes vienen en corrillo** (`party` por grupo: vecinos 1-3, soldados 2-3...) y eligen al azar entre lo que les gusta y hay (peso 3-2-1 por su orden de gusto). Los grupos sin fuente (soldados, nobles, jugadores) tienen `per_night`. Con la vida encendida, los forasteros son los de vida: los de los tipos de cada grupo (`visitor_kinds`: mercader y buhonero → mercaderes, peregrino, soldado, noble) que piden cama y la encuentran se quedan a dormir al acabar su plan o al atardecer (`Inn.lodge`, gancho en `Visitors._step_one`), esperan a la puerta a que abra, entran como clientes con su cama pagada y salen al amanecer hacia su puerta; el generador de prueba (2-4 al día) solo corre con la vida apagada. | Con una visita por persona salían ~10 clientes por noche: ni se llenaba el salón ni pagaba una casa con tres empleados. Con corrillos, ~20 por noche (los bots). |
| T4b | **Dos capas de clientela (04g §4.6.5.7):** los **Vecinos** son los de verdad: los que su agenda de vida manda a la taberna llegan a la puerta y, si está abierta, hay sitio y llevan dinero para algo de la carta, entran con su nombre (`Inn.neighbour_in`, gancho en `Agenda._go`), pagan de la bolsa de su casa, atenderles bien sube su relación con la familia (+2) y al irse vuelven a su agenda (una vez por salida, 2 h de descanso); son pocos (~2 por noche: casi todas las casas tienen 0-5 de oro). El resto es la **Gente de la comarca** (antes «Artesanos y vecinos»: 5-9 visitas por noche a plena atracción, en corrillo), con dinero de fuera (P4), y los grupos de paso (mercaderes, peregrinos, soldados, nobles, jugadores). Cada cliente tiene su **precio máximo** (ref × calidad × (1 + fama × 0,1) × el de su grupo): si nada de la carta lo cumple, se va («muy caro»). Las fiestas suben las dos capas (`Festivals.hook_mult(service, tavern)`: San Juan y Carnaval ×2, feria ×3) y los platos de temporada cuentan el día de su fiesta. No encontrar sitio no resta fama. | Lo decidió el owner en 04g: los vecinos van por su agenda y pagan de su bolsa; la mayoría viene por la fama del negocio, con dinero de fuera. |
| T5 | **Platos sin hierbas:** sopa de ajo = pan + trigo; olla = carne + trigo ×2; cordero = carne ×3; embutido = carne ×2 + trigo. El pan sale a 12. | En `town_e` no hay puesto de boticario: las hierbas no se pueden comprar. Con el pan a 10 se perdía dinero (se compra a 6-8). |
| T6 | **La comida cocinada se estropea** al amanecer (20 %) salvo con la despensa fría; la bebida y el pan, no. | Es lo que da sentido a la despensa fría del árbol (4.27.5). |
| T7 | **Ramas del árbol:** Salón, Cocina, Bodega, Habitaciones, Ambiente (ramas nuevas `inn_*`) y Seguridad (la de la Forja). Toneles = producción ×1,25 + 4 pilas; vino de reserva y cueva = el vino sale +1 / +2 de calidad; pizarra = +10 % de clientes y +2 platos; asador = +2 platos. | El árbol de 4.27.5 en las piezas de efecto que ya existen (H5) más los efectos `inn_*`. |
| T8 | **Durante las obras se sirve**, pero la cocina no cocina (la regla de 4.8). | Cerrar la taberna dos días por cada mejora la hundía. |
| T9 | **Plato de la casa** (de las promociones de Wartales). | Una decisión barata y legible sobre la clientela. |
| T10 | **Ganchos:** la partida que propone un forastero (`inn_game_offer`) espera a los juegos (4.26); hasta entonces la casa se queda su parte con la licencia. Los rumores de la barra son ya los de vida (`Rumors.candidates`, con los temas del punto `tavern` y los útiles ×2) y quedan en el libro de rumores (`town.rumors.heard`, punto `inn:<edificio>`); sin vida, los tres de antes (precio de fuera, evento en curso, deuda de un rival). `Inn.arrive()` es la puerta para los vecinos de verdad de la agenda de vida (4.24.1). | El orden de los bloques (4.28.5). |

**Medido** (bot `innkeeper`, `innkeeper_start`, Normal, 16 días, 10 semillas, con eventos globales): ver la diana
`innkeeper` de `data/targets.json`.

### 4.28 Lo que hace falta para construirlo

#### 4.28.1 Datos nuevos

| Fichero | Qué |
|---|---|
| `data/life/activities.json` | Actividades de 4.24.1 con dónde, cuándo, quién, duración, necesidades y burbuja |
| `data/life/rumors.json` | Plantillas de rumores por tipo de hecho, con sus variables |
| `data/life/life.json` → `needs`, `agenda`, `meeting`, `population`, `visitors`, `watch` (construido: en vez de `data/town.json`) | Necesidades, puntos de reunión, población por mapa, forasteros (4.24.3) y guardia (4.24.4) |
| `data/maps/*.json` → `social_points` (kinds nuevos), `patrols`, `population_max` | Puntos de reunión y rondas (los pone `tools/city/citylib.add_life`) |
| `data/life/incidents.json` (sucesos; construido: no en `data/events.json`) | Altercado, asalto y secuestro, con flujo `events_city` (el incendio no: O-V6 b) |
| `data/festivals.json` | Las fiestas fijas y variables de 4.25 con sus efectos de sim y de vista |
| `data/contracts/festivals.json` | Encargos de fiesta y de boda por evento y oficio (4.25.4) |
| `data/games.json` | Cifras de los minijuegos de 4.26 |
| `data/inn/*.json` | Carta, clientela, mejoras y sucesos de la Taberna-Posada |
| `data/world/region.json` → `patron_feast`, `fair` | Patronal y feria de cada ciudad |

#### 4.28.2 Guardado

| Versión | Qué | Bloque |
|---|---|---|
| **v17** | Vida: necesidades de los NPC, forasteros vivos, guardias, rumores oídos y sucesos en curso (secuestro pendiente) | `town.life`, `town.visitors`, `town.watch`, `town.rumors`, `town.incidents` (construido: todo bajo `town`, sin campos nuevos en la raíz) |
| **v18** | Fiestas: calendario del año, fiesta en curso, patrocinios, encargos de fiesta y competiciones programadas | `festivals` |
| **v19** | Taberna-Posada: carta, precios, fama, camas, licencia, mejoras y turno en curso | por edificio |
| v20 | Diversión y ritmo (03b): desbloqueos vistos, obras maestras con nombre, recetas aprendidas | `unlocks`, `masterworks` |
| v21 | 4.22 (reservada) | — |

Cada paso de migración es una función propia (`SaveFile._to_vNN`) que se encadena detrás de la anterior, con prueba
de ida y vuelta desde la versión de antes.

#### 4.28.3 Arte

- **Ilustraciones** (fal, 240×135 y 192×108; `assets/art/illustrations/events/<id>.png`): una por fiesta (8), por
  evento variable (9) y por suceso (5): unas 22.
- **Decoración** (props isométricos; greybox hasta que haya sprite): guirnaldas, banderolas, pendones, mayo, hoguera,
  farolillos, arco triunfal, tablado, cerco de carros, liza, mesas largas, belén, puesto de feria con toldo y
  corral.
- **Personajes:** guardia con librea, bandido, juglar, mercader forastero, peregrino, noble y séquito, mendigo,
  pregonero y corredor de apuestas. Hasta el día 15 se tiñen con el shader de identidad sobre los sprites que ya
  hay, y después se piden a PixelLab. Animales: cerdo, toro, caballo y oveja.
- **Taberna-Posada:** fachada (delante y detrás, para las puertas), interior (barra, mesas, cocina, chimenea,
  toneles, camas y rincón del juglar) e iconos de platos.
- **Minijuegos:** la pantalla de cada uno (fondos y piezas: liza, caballos de perfil, anilla, dados, naipes de 4
  palos, mesa de taberna), con sus iconos.

#### 4.28.4 Pruebas, bots y dianas

- **Dianas de hoy:** idénticas. Todos los sistemas nuevos van apagados en sus escenarios (`_no_events` y un
  `_no_life` si hace falta), salvo la población, que se mide aparte (4.24.3).
- **Bots nuevos:**
  - `festive` juega un año entero con fiestas y comprueba que cada fiesta sale, sus encargos se publican y se pueden
    cumplir, no hay bloqueos y el bench sigue por debajo de 2 ms con la feria llena;
  - `innkeeper` lleva la taberna 16 días (atiende, ajusta la carta, mejora, compra la licencia), con su diana de oro
    neto, fama y ocupación de camas;
  - `gambler` apuesta y juega a dados y naipes, con su diana: pierde de media lo que marca el margen de la casa, ni
    más ni menos;
  - `guard_watch` corre noches con asaltos y comprueba que la guardia responde y que nunca se pierde más del tope.
    **Construido:** desde `life_bandits` (año 2, asaltos ×5), 16 días; diana propuesta en `data/targets.json`
    `guard_watch` (5 asaltos por semilla, la alarma siempre trae a la guardia, nunca más del 10 % del oro ni de 3
    piezas, 0 órdenes rechazadas y el libro cuadra). Un escenario por suceso: `life_altercation`, `life_bandits`,
    `life_kidnap` (más `life_plaza`, `life_gate` y `life_night` para las capturas).
- **Bancos de los minijuegos** (como `tools/duel_bench.gd`): «Resolver sin jugar» es igual que jugar bien, jugar al
  azar pierde y las políticas fijas pierden.

#### 4.28.5 Reparto en bloques (para los workers)

| Bloque | Secciones | Guardado | Depende de |
|---|---|---|---|
| **Vida** | 4.24 (agenda, reunión y rumores, población y forasteros, guardia, sucesos) | v17 | — |
| **Fiestas** | 4.25 (calendario, eventos, efectos, encargos, patrocinio, región) | v18 | Vida (forasteros, rutinas) y Juegos (espectáculos); empieza por lo que no depende |
| **Juegos** | 4.26 (reglas puras, pantallas, apuestas) | sin guardado: se resuelven en el momento | el duelo (04e) |
| **Posada** | 4.27 | v19 | Vida (clientela y forasteros) y Juegos (mesa de juego); empieza por el edificio, la carta y el turno |
| **Arte** | 4.28.3 | — | las rutas de este documento |

---

### 4.29 Preguntas abiertas para el owner

Cada una lleva la recomendación con la que se construye si no se dice otra cosa.

| # | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| **O-V1** | Patronales de cada ciudad | Las de 4.25.1 u otras | Las de 4.25.1 (Sant Martí, Sant Jordi, el Carmen, Santa Bárbara, San Isidro y el santo fundador) |
| **O-V2** | Población de `town_e` | (a) 32 (5 por casa, con tope). (b) 26. (c) 20, como hoy | **(a)**, midiendo el bench y las dianas; si el bench pasa de 2 ms, (b) |
| **O-V3** | Secuestros de familiares del jugador | (a) Sí, raros, nunca el cabeza de familia ni un niño. (b) Solo de otros (forasteros, otras familias) | **(a)**: el owner los pidió; con aviso, salida digna y nunca antes del año 2 |
| **O-V4** | Asaltos de bandidos a tu casa | (a) Solo al borde del pueblo y con aviso. (b) En cualquier sitio. (c) Solo a forasteros | **(a)**: responde a O14 de 4.22 sin castigar al Artesano que empieza |
| **O-V5** | Toros: ¿puede salir herido el mozo? | (a) No hasta que exista la salud de 4.22. (b) Sí, «asustado» y −reputación | **(a)**, con «asustado» y burla |
| **O-V6** | Incendios | (a) Sí, raros. (b) No | **(b)** de momento: la reconstrucción y el daño de edificios no existen (como la revuelta de H13) |
| **O-V7** | ¿Quién puede tener la Taberna-Posada? | (a) Cualquier familia como segundo negocio. (b) Solo el Patrón (4.22) | **(a)**: el owner la pidió como negocio nuevo; el Posadero del Patrón llega con 4.22 |
| **O-V8** | Juego con dinero de verdad | (a) Sí, con margen de la casa y tope por apuesta. (b) Solo por reputación | **(a)**, con tope de 50 por apuesta y aviso si pierdes más de 100 en un día |
| **O-V9** | Segunda taberna en otra ciudad | (a) Más adelante, cuando se pueda cargar otra ciudad (O-R3). (b) Nunca | **(a)** |
| **O-V10** | Dados cargados y trampas para cualquiera | (a) Solo el Pícaro (4.22). (b) Cualquiera que los compre | **(b)**, con el riesgo de que te pillen; el Pícaro tendrá ventaja |
| **O-V11** | ¿La Taberna-Posada cuenta para el tope de edificios por título (4.9)? | (a) No: es el segundo negocio de cualquiera. (b) Sí, cuando llegue H6: un Plebeyo tendría que ser Ciudadano para comprarla | **(a)** de momento (T2); con H6, decidir si el tope de Plebeyo pasa a 2 |
| **O-V12** | ¿Se puede construir una segunda taberna en un solar? | (a) Con H6 (parcelas de producción). (b) Nunca: una por villa | **(a)**, y entonces la del pueblo entra como proveedor NPC (4.22.3.2), la rival |

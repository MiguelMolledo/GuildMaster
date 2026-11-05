## 3b. Diversión y ritmo: el herrero, de la primera espada a la dinastía

> El owner (2026-11-04): «revisa el loop para ver si es divertido siendo un herrero mismo, lista las cosas divertidas
> que puede hacer y en qué momento de la partida debería ir desbloqueando nuevas mecánicas. Empiezas forjando, pero
> si al final esto es ver solo una progress bar de 0 a 100 y no hacer nada puede ser muy aburrido».

### 3b.1 Diagnóstico honesto del bucle de hoy

Lo que hace hoy un herrero en su primera hora (mirando el inicio de 4.16, los objetivos de inicio y el escenario
`town_e_start`):

| Momento | Qué hace | ¿Decide algo? | Riesgo de aburrimiento |
|---|---|---|---|
| Comprar hierro y carbón | Clic en el puesto, cantidad, comprar | Poco: precio casi fijo al principio | bajo (es corto) |
| Llevarlo a la forja | Andar o pagar el recado | Sí: tiempo frente a dinero | bajo |
| **Forjar** | Clic derecho en el horno, «Trabajar», y la barra va de 0 a 100 durante 1-5 h de juego (12-60 s) | **Una vez al empezar** (rápido, normal o con cuidado) y **un clic** en el toque de maestro si va con cuidado | **alto: es justo lo que teme el owner** |
| Repetir | Auto-repetición o volver a dar la orden | No | **alto** |
| Vender | Ir a la plaza, clic, vender; o mostrador; o encargo | Algo: dónde y cuándo vender (demanda) | medio |
| Esperar al día siguiente | ×4 | No | medio |

**Conclusión:** el esqueleto económico está (comprar, producir, vender, competir, deuda), pero **el corazón del
oficio, forjar, es una barra**, y el toque de maestro es un solo clic sin decisión. Lo divertido llega tarde (familia,
títulos, cargos, tribunal, duelo, viajes) y no se anuncia: todo está disponible desde el principio o tras un título,
sin un ritmo pensado.

Faltan tres cosas:

1. **Que forjar sea un oficio**, no una espera, cuando el jugador quiera hacerlo a mano.
2. **Que siempre haya algo que decidir**: 2-3 metas abiertas, un evento que rompe la rutina y una tensión (precio,
   plazo, rival).
3. **Un ritmo de desbloqueos**: un juguete nuevo cada 20-30 minutos reales al principio, presentado con su carta y
   su capítulo de tutorial.

### 3b.2 Forjar a mano: el oficio como minijuego (propuesta «Forja viva»)

La regla de oro: **los empleados hacen el volumen y tus manos hacen las piezas que importan**. Trabajar a mano
tiene que ser corto, legible, con decisiones, y dar algo que los empleados no dan.

**Una pieza a mano son 3 decisiones** (unos 20-40 s reales, con el reloj del sim avanzando como hoy):

1. **Calentar** — el hierro cambia de color en la fragua: rojo oscuro, **rojo cereza**, naranja, amarillo y blanco
   (quemado). Sacas la pieza cuando quieres. Cada receta tiene su color bueno (la espada, cereza; el clavo,
   naranja), que el jugador **aprende** y la ficha de la receta recuerda. No es un reflejo: el color se queda unos
   segundos en cada tono, y la pista de Artesanía dice «ya casi».
2. **Batir** — en el yunque eliges **cómo das forma**: tres o cuatro golpes, cada uno «fuerte» (forma rápida,
   riesgo de grieta), «medido» o «de acabado». Una pieza bien batida es la que sigue la plantilla de la receta (por
   ejemplo, espada: fuerte, medido, medido, acabado). Con Artesanía alta, la plantilla se ve antes.
3. **Templar** — en el cubo eliges **agua** (dura, frágil), **aceite** (equilibrada) o **al aire** (blanda). Cada
   encargo o cliente prefiere una cosa (el guardia quiere dureza; el noble, una hoja que no se rompa).

**Resultado:** la calidad sale de la tabla de 4.4.2 más los aciertos (+1 escalón con las 3 decisiones bien y −1 con
2 mal) y la pieza puede ganar **rasgos**: «templada al aceite» (+durabilidad), «filo fino», «con marca del maestro».

- **«Resolver sin jugar»** (o el modo normal de hoy) sigue estando: da la calidad media de la Artesanía, como ahora.
  El minijuego solo es **mejor** cuando lo haces bien. Como en el duelo (O-C10), jugar mal pierde: con dos
  decisiones mal la pieza baja un escalón (corregido al construirlo, 2026-11-04: antes decía «jugar mal no es peor
  que no jugar», que contradecía el −1 de arriba y O-C10).
- **Los empleados** siguen con la barra. Es su trabajo, y el jugador decide qué hacen en la cola.
- **La marca del maestro:** con Artesanía ≥ 7 y las tres decisiones bien, una pieza puede salir **obra maestra**
  (un 10 % de las veces [balance]; el nombre, la crónica y la pieza excelente están construidos; la venta a nobles,
  el regalo y la ventaja en justas y duelo son ganchos que esperan a esos sistemas, §3b.8):
  tiene nombre («La espada de San Martín de los Molledo»), queda en la crónica, se vende a nobles por ×3, es el
  regalo perfecto para la visita del marqués o una boda (4.25.4) y se puede usar en las justas y en el duelo (+1
  ventaja).

### 3b.3 Lo divertido que puede hacer un herrero (catálogo por capas)

**Con las manos (minuto a minuto):**

- Forjar a mano piezas que importan (3b.2) y buscar la obra maestra.
- **Encargos con especificaciones**: «una espada ligera y larga para un caballero zurdo», «herraduras para 4 mulas
  antes del alba». Elegir la variante de receta (hoja larga o corta, guarnición sencilla o labrada, temple) es un
  pequeño puzle.
- **Experimentar**: combinar materiales nuevos (acero de Peñarroja, hierro dulce) descubre recetas; la ficha guarda
  lo aprendido.
- Batirse en **duelo** (04e) y competir en **justas, torneos y carreras** (4.26) con sus propias armas.

**Con el negocio (día a día):**

- La guerra de precios con el rival (4.5.5): bajar, aguantar o especializarse.
- Elegir **qué vender dónde**: mercado, mostrador, encargos, otra ciudad (09b) o caravana.
- Contratar, ascender y despedir: el aprendiz que se hace oficial y luego maestro (4.7).
- Mejorar la forja: cada mejora se ve (4.8).
- Abrir un **segundo negocio**: la Taberna-Posada (4.27), la armería o un puesto en otra ciudad.

**Con la ciudad (semana a semana, es decir, de estación en estación):**

- Las **fiestas** y sus grandes encargos: la espada del novio, las rejas del toril, los cuchillos de la matanza
  (4.25).
- Los **sucesos**: separar una pelea, defender el almacén de los bandidos, pagar o rescatar a un secuestrado
  (4.24.5).
- Los **rumores**, que dan información para ganar dinero (4.24.2).
- **Apostar** y jugar a los **dados y naipes** en la taberna (4.26).

**Con la familia y el poder (año a año):**

- Cortejo y boda, hijos, educar al heredero y elegirlo (4.10).
- Títulos, que abren cosas visibles (viajar, justas, tratados) (4.12, 09b).
- Cargos y elecciones, y el tribunal: acusar al rival que te robó (4.12).
- Tratados mercantiles y caravanas por Valldaura (09b).
- La IA rival te ataca y tú te defiendes (04c).

### 3b.4 El ritmo de desbloqueos

**Regla:** cada mecánica llega **cuando el jugador la necesita** y **con su carta** («Nuevo: …»), un capítulo de
tutorial (docs/ui/05_tutorial.md) y una meta que la usa. Al principio llega un juguete nuevo cada **20-30 min
reales** (medio año); después, uno por año. Nada se esconde para siempre: el desbloqueo es por **hito del jugador**
(título, oro, empleados, edad) o por **calendario**, y el jugador experto puede llegar antes.

Recordatorio: 1 año = 8 días = 40 min reales.

| Cuándo (juego · real) | Se desbloquea | Disparador | Meta que lo usa |
|---|---|---|---|
| Día 1 · 0-5 min | Mover, comprar, **forjar a mano** (Forja viva), vender en la plaza | inicio | «Funde dos lingotes y forja una espada» (ya existe) |
| Día 1 · 5-10 min | Encargos del tablón y recado | primera venta | «Cumple tu primer encargo» |
| Día 2 · 10 min | Mostrador y la **primera fiesta** (Semana Santa, que es Primavera 1; la pequeña siguiente si se empieza en otra estación) | calendario | «Vende en tu mostrador durante la fiesta» |
| Día 2-3 · 15 min | **Primer empleado** (aprendiz) y la cola | 150 de oro o 3 encargos | «Contrata a un aprendiz y ponle una cola» |
| Día 3 · 15-20 min | **El rival** te nota (guerra de precios, 4.5.5) | primer día con más ventas que él | «Gana al rival en ventas un día» |
| Día 4 · 20 min | **Mejoras** de la forja | 300 de oro | «Haz tu primera mejora» |
| Verano 2 · 25 min | **La feria**: forasteros, rumores, la carrera de caballos (mirar y apostar) | calendario | «Vende 5 piezas en la feria» |
| Otoño · 30 min | **La taberna** de otro (cliente: dados, naipes y rumores) | la víspera de San Martín | «Oye tres rumores» |
| Fin del año 1 · 40 min | **Devolver la deuda** (la meta grande del año 1) y el **cortejo** | calendario y edad | «Paga la deuda» y «Corteja» |
| Año 2 · 40-80 min | **Título de Ciudadano**: **viajar** (09b), **duelo** (04e), **justa** (si hay caballo) y **segundo negocio** (Taberna-Posada) | título | «Viaja a Vilablat», «Abre tu taberna» |
| Año 2 · desde el día 9 | **Sucesos** de la ciudad: altercados (antes también, pero raros), bandidos y la primera visita del marqués posible | calendario | «Defiende la villa» |
| Año 2-3 · 80-120 min | **Boda e hijos**, **caravanas** (carro), **encargos de boda rica** | boda o carro | «Forja la espada del novio» |
| Año 3 · 2 h | **Cargos** (concejal), **tratados** (con Patricio), **torneo** | título | «Gana una elección», «Firma un tratado» |
| Año 3-5 · 2-3 h | **Tribunal** contra el rival, **secuestros** | un rival hostil | «Lleva a juicio al rival» |
| Cuando salga (desde el día 1 si se juega bien) | **Obra maestra** con nombre | la primera obra maestra (Artesanía ≥ 7 y las tres decisiones bien) | «Forja una obra maestra» |
| Generación 2 · ~17 h | **Heredero**: el hijo forja con su propia Artesanía (aprendida contigo) | muerte o retiro | metas de dinastía (4.17) |

**Cómo se ve el desbloqueo:** una carta del kit de página («Nuevo: la feria»), una marca en el HUD en el botón o
panel nuevo, el capítulo del tutorial (si están activadas las pistas) y una meta en la zona de objetivos.

### 3b.5 Contra la barra: reglas de diseño

1. **Siempre 2 o 3 metas abiertas** en la zona de objetivos: una corta (hoy), una media (esta estación) y una
   larga (este año o de dinastía).
2. **Ningún tramo de más de 60 s reales sin una decisión** en el año 1 (medido con el bot de ritmo, 3b.6). Si el
   jugador no tiene nada que hacer, «Saltar hasta…» (el próximo evento, el amanecer o que acabe la cola) a ×8.
3. **La espera se llena:** mientras la cola de empleados trabaja, tú vas a la plaza, atiendes la taberna, cortejas,
   oyes rumores o preparas el encargo de la fiesta.
4. **Cada estación trae algo**: una fiesta grande o pequeña (4.25.1) y, con suerte, un suceso o una visita.
5. **Tensión, no castigo:** competir por un encargo con el rival, la carrera contra el plazo y elegir entre calidad
   y cantidad, con aviso antes de perder.
6. **Lo manual premia, no obliga:** quien no quiera minijuegos juega con «Resolver sin jugar» y empleados.

### 3b.6 Cómo lo medimos

- **Bot de ritmo** (`pacing`): juega el año 1 como un novato y mide (a) los segundos reales entre decisiones con
  sentido, (b) cuántas metas tiene abiertas a cada hora y (c) cuándo llega cada desbloqueo de 3b.4. Diana: mediana
  < 30 s entre decisiones, máximo < 60 s, siempre ≥ 2 metas y los desbloqueos en su ventana ±1 día.
- **Partida del owner** (la de H11, 2 h): una lista de comprobación en el cuaderno: «¿hubo algún momento en que solo
  mirabas una barra?», «¿qué fue lo más divertido?», «¿qué llegó demasiado pronto o tarde?».

### 3b.7 Preguntas para el owner

| # | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| **O-D1** | Forja viva (3b.2) | (a) Calentar, batir y templar como 3 decisiones. (b) Solo calentar (el color). (c) Dejar la barra y el toque de maestro | **(a)**, con «Resolver sin jugar» |
| **O-D2** | ¿Desbloqueos o todo abierto? | (a) Desbloqueo por hito del jugador y calendario, con carta (3b.4). (b) Todo abierto desde el principio, con el tutorial | **(a)**: es la cura contra «no sé qué hacer» y contra «hay demasiado» |
| **O-D3** | «Saltar hasta…» | (a) Sí, a ×8 hasta el próximo evento, el amanecer o el fin de la cola. (b) No | **(a)** |
| **O-D4** | Obras maestras con nombre | (a) Sí, con Artesanía ≥ 7, con nombre y en la crónica. (b) No | **(a)** |
| **O-D5** | Encargos con especificaciones | (a) Sí, con variantes de receta (largo, guarnición, temple). (b) Solo calidad, como hoy | **(a)** |

### 3b.8 Cómo se ha construido (rama forja, 2026-11-04)

Lo que cambió al construirlo, con su porqué (también en `docs/decisiones.json`):

**Forja viva (§3b.2, O-D1 a, O-D4 a).** Reglas en `sim/forge/live_forge.gd`, cifras en `data/live_forge.json`.

- Es un **modo de trabajo** más, `live`, de `work_at`: solo para quien controla el jugador y solo en las recetas
  que lo tienen (martillo, espada y armadura; el lingote y el acero no se baten). En el yunque de la forja el
  tercer botón del menú del puesto pasa de «Con cuidado» a **«Forja viva»**. El modo `careful` y el toque de
  maestro siguen en el sim, para los bots, las partidas guardadas y los otros oficios, que no tienen Forja viva
  (las dianas de `data/targets.json` no se mueven: los bots siguen con `normal` y `careful`).
- Las tres decisiones son órdenes `live_forge` (paso `heat`, `strike`, `quench` o `skip`), que se aplican al momento
  (van con las de gestión) y quedan en la grabación de la partida, así que se reproducen. El color que se ve
  avanzar en la fragua es de la pantalla (2,4 s reales por tono); lo que sí es del sim es si el color sacado es el
  bueno.
- Cada decisión sale **bien, cerca o mal**: el color bueno está bien, el de al lado está cerca y los demás (y el
  blanco, quemado) están mal; los golpes iguales a la plantilla están bien, con uno distinto cerca y con más, mal; el
  temple bueno está bien y cualquier otro, mal. Una decisión que no se toma cuenta como «cerca». Las tres bien suben
  un escalón y dos o más mal lo bajan.
- **Sin decidir nada, la pieza sale exactamente como en el modo normal**: se tiran los mismos dados en el mismo
  orden. El banco de `tests/test_forja_live.gd` (60 martillos, Artesanía 7) lo mide: normal 1,07, sin jugar 1,07
  (pieza a pieza igual), bien jugado 1,83 y mal jugado 0,33.
- Si el ciclo termina con decisiones pendientes, espera **media hora de juego** [balance] y luego se resuelve con lo
  decidido. Un ciclo de Forja viva solo se repite en Forja viva si se jugó hasta el temple; si no, sigue en normal
  (así quien se va a otra cosa no se queda con la forja esperando).
- Mientras la pantalla está abierta el juego va a ×1, y al cerrarla vuelve la velocidad que había. Esc es «Resolver
  sin jugar» y, en el resultado, «Seguir» (pasa a la pieza siguiente si la forja ya la empezó).
- **Pistas por Artesanía:** con 4 o más, «ya casi» un tono antes del bueno; con 7 o más, la plantilla de golpes se
  ve antes de batir. Lo que se acierta queda en la **ficha** de la familia (`masterworks.learned`): el color, la
  plantilla y el temple de cada receta, y la pantalla lo recuerda.
- **Rasgos:** templada al aceite, templada al agua, enfriada al aire, filo fino y con marca del maestro. Salen en el
  resultado y en la obra maestra; no cambian reglas hasta que exista la durabilidad (gancho).
- **Obra maestra:** Artesanía ≥ 7 (la del personaje) y las tres bien, y entonces una tirada del 10 % [balance]. Sale
  excelente, con nombre («La espada de Santa Inés de los Herrero»: un santo de `patrons` y el apellido de la
  familia), entra en la crónica (`masterwork`), en `masterworks.pieces` y en el registro de avisos, y la pieza va al
  almacén como excelente. El Hugo del inicio ya tiene Artesanía 7, así que la obra maestra puede salir desde el
  primer día (rara); por eso en §3b.4 su desbloqueo es «la primera que salga» y no el año 3-5. Venderla a nobles
  ×3, regalarla en una visita o una boda y la ventaja en justas y duelo quedan como ganchos para cuando lleguen esos
  sistemas: hoy la pieza del almacén es una espada excelente más.

**Encargos con especificaciones (§3b.3, O-D5 a).** En `data/contracts/blacksmith.json` (`specs`, `spec_chance`
0,35, `spec_bonus` 0,3 [balance]) y `data/live_forge.json` (`variants`, `recipe_axes`).

- Algunos encargos del tablón piden una variante: hoja **corta o larga**, guarnición **sencilla o labrada** y un
  **temple**. El cliente lo dice con palabras en el tablón («Un caballero zurdo quiere una espada larga y ligera,
  que no se rompa»): elegir la variante es el puzle.
- **Es una prima, no un castigo:** cada pieza hecha a medida cobra un 30 % más al entregarla; una pieza normal se
  sigue aceptando a la paga normal. Así nadie pierde un encargo por no jugar y los bots no cambian.
- Se hace desde el menú del puesto («Para el encargo de…» y la variante) o en la Forja viva, donde el temple lo
  decide el cubo. La hoja larga tarda ×1,15 y añade un golpe medido; la guarnición labrada tarda ×1,25 y añade uno de
  acabado.
- La pieza que cumple (y llega a la calidad mínima) se **aparta para el encargo** (`contract.made`) y no va al
  almacén; la que no cumple va al almacén como cualquier otra. Al entregar, las apartadas van primero; si el encargo
  vence o se abandona, vuelven al almacén.
- Qué encargo pide variante sale de un azar propio (la semilla de la partida y el id del encargo): `state.rng` no se
  mueve y las dianas de hoy salen iguales.

**Guardado v20** (`SaveFile._to_v20`): las raíces `unlocks` y `masterworks` (`pieces`, `learned`). Una partida de
antes recibe todos los desbloqueos como vistos (ya lo tenía todo abierto) y ninguna obra maestra. No depende de los
campos de v17-v19.

**Desbloqueos (§3b.4, O-D2 a).** Tabla en `data/unlocks.json`, sistema en `sim/pacing/unlocks.gd` (estado en
`unlocks`, v20).

- Cada fila tiene su **disparador** (`start`, `calendar` por día, `gold`, `title`, `employees`, `age`, `event` con
  cuenta, `outsold_rival` y las combinaciones `any`/`all`), su **ventana** de 3b.4 (los días en que se espera, para
  el bot de ritmo), la **marca** (el botón del HUD o del interior que se marca con «●» hasta que se usa), el
  **capítulo** del tutorial, la **meta** (un objetivo de `data/objectives/`) y su horizonte.
- Lo que se desbloquea es **acceso de la UI**: hoy solo se esconden los botones de **Empleados** y **Mejoras** de la
  forja hasta su desbloqueo (150 de oro o 3 encargos; 300 de oro). El resto ya tenía su puerta en el sim (títulos,
  edad, la propia mejora del mostrador) o está en el mundo (el tablón): se anuncia con su carta, su marca y su meta,
  sin esconderlo. El sim no lee los desbloqueos para ninguna regla y no tira dados: las dianas de hoy salen iguales.
- **Nada se esconde para siempre:** empezar un capítulo del tutorial desde la ayuda abre lo que enseña (orden
  `unlock_seen` con `what: now`), y las partidas de antes de v20 lo tienen todo abierto.
- **Carta «Nuevo: …»** (`UnlockCard`, del kit de página): qué es, la meta que trae y «Ver capítulo» si las pistas
  están encendidas. No pausa; al cerrarla queda leída. Lámina `events/unlock_<id>` del arte cuando llegue.
- **Ganchos:** con la posada en main (2026-11-05) se enganchó la **taberna** (`requires: inn`, `data/inn/`): en
  town_e la Taberna-Posada no es «la taberna de otro» de 3b.4, sino un edificio **en venta** que cualquiera puede
  comprar, sin título. Por eso el desbloqueo llega en otoño (día 5, la víspera de San Martín), presenta la taberna en
  venta como segundo negocio y trae la meta «Abre tu taberna» (`building_bought`); la fila de Ciudadano de 3b.4 sigue
  nombrando el segundo negocio, que ya no necesita el título. Con fiestas en main (2026-11-05) se engancharon la **primera
  fiesta** (cuando empieza la primera fiesta de la villa, `festival_started` de cualquiera, día 2 en una partida
  nueva; meta «Cumple un encargo de la fiesta») y la **feria** (cuando empieza `harvest_fair`, día 4; meta «Vende 5
  piezas en la feria»), solo con el calendario de fiestas encendido (`data/festivals.json` `enabled`). Con vida ya en main (2026-11-04) se engancharon
  los **sucesos** (`life/incidents`, desde el día 9, meta «Interviene en un suceso de la villa») y un desbloqueo nuevo,
  los **rumores** (`life/rumors`, día 5, marca en el libro, meta «Oye tres rumores»): la taberna de 3b.4 traía los
  rumores, pero en vida se oyen en los corrillos, así que llegan antes y la taberna queda para dados y naipes. Los
  ganchos de `life/` esperan además a que la ciudad viva esté encendida (`data/life/life.json`).
- **Cambios en la tabla de 3b.4:** la obra maestra se desbloquea cuando sale la primera (ver arriba); el tribunal,
  cuando hay un juicio o una acusación (no hay todavía una medida de «rival hostil» en el sim); cargos y tratados,
  con el título de Patricio (el de Ciudadano ya trae viajar y el duelo); «boda e hijos» y «caravanas» van juntos
  (`family_trade`: boda o carro).

**Metas siempre abiertas (§3b.5.1).** `sim/pacing/goals.gd` sobre los objetivos que ya hay. La zona de metas va
debajo del objetivo (que es la meta de **hoy**, la cadena de inicio): **esta estación** es la meta del último
desbloqueo que falta por cumplir y **este año** es la deuda en el año 1 (`year_goal`) y después la primera meta de
dinastía. Las metas de los desbloqueos cuentan los hechos de la familia desde que se abren, aparte de la cadena.
Siempre hay al menos dos (hoy y este año).

**«Saltar hasta…» (§3b.5.2, O-D3 a).** Botón «»» junto a las velocidades: el próximo evento, el amanecer o que acabe
la cola (la del edificio abierto o la primera de la familia con trabajo). Va a ×8 (`data/view.json` `skip`) y se
corta con cualquier aviso de la familia, un desbloqueo, un evento global o un microevento, una orden del jugador,
la pausa, un cambio de velocidad o al pasar un día entero. «El próximo evento» es además una pieza terminada, un
encargo nuevo, un recado que llega o un cambio de fase del día. Es estado de la sesión, como la velocidad: no se
guarda. Volver a pulsar «■» lo para.

**Bot de ritmo y partida del owner (§3b.6).** `sim/bots/bot_pacing.gd` es el novato de siempre que forja en Forja viva
y lee cada carta. Cuenta como decisión cada orden suya (las que van a menos de 3 s, como las paradas de un viaje,
cuentan como una), una decisión de la forja o una carta leída; un minuto de juego vale lo que vale a ×1 y la octava
parte cuando el jugador estaría saltando (un ciclo en marcha sin nada que decidir, o la noche); andar nunca se salta.
Diana en `data/targets.json` (`pacing`, paso `pacing` de la QA, 5 semillas). Medido el 2026-11-04 con 3 semillas:
mediana 4,7 s entre decisiones, p90 6,6 s, máximo 29-40 s, al menos 2 metas a todas horas (media 2,8-3,0) y los 9
desbloqueos del año 1 dentro de su ventana. Dos ventanas se movieron tras medir: los encargos, días 1-2 (el novato
vende el primer día o el segundo), y las mejoras, días 4-6 (con la deuda pagada pronto, los 300 de oro llegan el
quinto o el sexto día). La lista de comprobación de la partida del owner está en `docs/partida_owner.json` y sale
en el cuaderno.

**Con fiestas y vida (2026-11-05).** Con `--festivals=on --life=on` el ritmo sigue en su diana, pero en 1 de 3
semillas el novato no junta 300 de oro en el año 1 y las mejoras no se abren. El owner decide que la ventana de las
mejoras no se mueve: lo arregla el equilibrio del año 1-2 con fiestas (Ciudadano y oro). La banda con fiestas queda
como propuesta (`data/targets.json` `pacing._proposed_festivals`, sin comprobar) hasta ese equilibrio.

**Equilibrio con todo encendido (rama equilibrio, 2026-11-05).** La banda con fiestas ya es la diana: `pacing` está en
`_festivals` y fuera de `_no_life` (`data/targets.json`). Lo que lo arregló fue Equilibrio 11: el novato aceptaba
encargos de fiesta que no llegaba a hacer (miraba `deadline_days`, redondeado al día), los perdía y no juntaba los 300 de
oro. Medido (5 semillas, todo encendido): antes 4 de 5 con las mejoras sin abrir, un hueco de 198 s y 42 de oro neto al
día; después 0 fuera de ventana (14 desbloqueos), hueco máximo 26-35 s, mediana 4,7 s, ≥ 2 metas siempre y 76 de oro
al día. Con el jugador completo (3 años × 4 semillas) el hueco máximo pasa de 119-176 s a 38-47 s (el año 1, de 61-137 s
a 15 s): las obras ya no paran la forja (Equilibrio 9) y el camino entre ciudades cuenta como «Saltar hasta…». Ciudadano
llega los días 11-15 (Equilibrio 3), a tiempo para viajar, el duelo y la justa en el año 2.

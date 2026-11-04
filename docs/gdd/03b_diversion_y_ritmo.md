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
  El minijuego solo es **mejor** cuando lo haces bien (como el duelo, O-C10: jugar mal no es peor que no jugar).
- **Los empleados** siguen con la barra. Es su trabajo, y el jugador decide qué hacen en la cola.
- **La marca del maestro:** con Artesanía ≥ 7 y las tres decisiones bien, una pieza puede salir **obra maestra**:
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
| Año 3-5 · 2-3 h | **Tribunal** contra el rival, **secuestros**, **obra maestra** con nombre | Artesanía 7 o un rival hostil | «Forja una obra maestra», «Lleva a juicio al rival» |
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

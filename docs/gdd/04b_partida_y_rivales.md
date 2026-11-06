## 4 (continuación). Partida, economía global, rivales y otras clases

Continúa la sección 4 ([04_diseno_de_juego.md](04_diseno_de_juego.md)). Aprobado por el owner el 2026-11-01. Las cifras marcadas **[balance]** son valores iniciales que se ajustan con bots contra las dianas de `data/targets.json`.

### 4.16 Inicio de partida

**Partida nueva:** se elige dificultad (4.23), se crea el personaje (4.2.2: nombre, género, 5 puntos libres) y los colores de la familia (4.10.9). La partida empieza al amanecer del día 1 de primavera del año 1. Desde H12 se elige también el oficio dentro del Artesano (herrero, carpintero, albañil o sastre): cada uno tiene su inicio (`data/starts/artisan_<oficio>.json`) con las mismas cifras que el del herrero (30 de oro, deuda por dificultad, 2 encargos guionizados de su oficio), su taller en su solar de town_e y un rival de su mismo oficio (4.5.5). El nombre, el apellido y el aspecto que propone la pantalla, y la gente del pueblo, salen del reparto generado (4.11.1); el botón **«Otra familia»** vuelve a tirarlo con otra sub-semilla del reparto sin cambiar la semilla del mundo.

**Condiciones de inicio (Artesano / Herrero, dificultad Normal)** [balance]:

| Elemento | Valor |
|---|---|
| Protagonista | 20 años, soltero, título Común, reputación 0 |
| Oro | 30 |
| Edificio | **Forja con vivienda básica**, ya en pie en su parcela (4.9): horno, yunque, almacén de 10 pilas, 1 hueco de empleado vacío, sin mejoras |
| Almacén de la Forja | hierro ×8, carbón ×4 (dan para 2 espadas) |
| Inventario del personaje | martillo equipado |
| **Deuda inicial** | **200 oro** con el prestamista que adelantó la Forja, a devolver en **1 año** (antes de que acabe el día 8), sin intereses |
| Competencia | El herrero rival (4.5.5) con su Forja en la misma calle |
| Tablón de encargos | 2 encargos guionizados (ver objetivos) |

**La deuda** es una entidad `Loan` del `WorldState` (la misma que usará el Banquero en EA, 4.22):

- Se puede pagar en cualquier momento, entera o a plazos, desde el libro de cuentas (orden `RepayLoan(actor, loan, amount)`).
- Avisos urgentes en el registro 2 días y 1 día antes de vencer.
- **Si vence sin pagar:** reputación −10 y una **prórroga de 1 estación** con un recargo del 25 % sobre lo pendiente.
- **Sin salida (Equilibrio 2, 2026-11-05): nunca una partida muerta.** Si la familia se queda con menos de 15 de oro y
  existencias (almacén, bolsas y recados en camino, a precio de venta) que valen menos de 20, el prestamista ofrece un
  **préstamo de urgencia**: 60 de oro ahora y 90 a devolver en 4 días (pequeño, caro, con plazo; como mucho 2 al año;
  carta urgente y botón «Pedirlo» en el libro, pestaña Deudas, con confirmación). Si vence sin pagar, la prórroga de
  siempre; si vence la prórroga y el oro y la mercancía no alcanzan, se **embarga un bien** antes de la ruina. Si no se
  toma y la deuda de mantenimiento con la villa llega a **100**, al alba se embarga **el bien más caro que no sea la
  casa** (otro edificio, que vuelve a estar en venta y pierde a sus empleados; un carro; una pieza del equipo) al 75 %
  de su valor: paga la deuda de mantenimiento y la de urgencia, y lo que sobra es para la familia. **Sin bienes, ruina**
  con la pantalla de fin. Cifras en `data/accounts.json` `emergency`; reglas en `sim/balance/emergency.gd`; bot `broke`
  desde el escenario `broke_forge` (el bloqueo blando del caótico, día 9 sin oro y con 1 carbón).
- **Si vence la prórroga:** embargo. El prestamista se cobra primero del oro y después de la mercancía del almacén de la Forja, valorada a precio de venta del mercado. Si no alcanza, se queda la Forja: **ruina**, la partida termina con la pantalla de final (4.17). Que la ruina termine la partida está pendiente de confirmar (D18).
- La cantidad depende de la dificultad (4.23).

Cuentas de referencia: a mano se ganan ~25-60 oro netos por día (4.19); en 8 días el bot `artisan_novice` debe poder pagar la deuda y quedarse en su diana de oro al día 10.

**Objetivos de inicio (tutorial implícito).** Una cadena de objetivos visible en el HUD. No bloquean nada ni dan oro: su premio es lo que enseñan. Cada uno cumplido queda en el registro de avisos. Si un objetivo depende de un encargo guionizado y ese encargo ya no se puede cumplir (caduca, se abandona o lo coge otra familia), el objetivo **se da por fallado**: aviso en el registro que lo explica y la cadena pasa al siguiente (no se vuelve a ofrecer el encargo: el plazo incumplido también enseña). El de calidad "buena" no depende del encargo del capitán: vale cualquier encargo con calidad mínima buena.

| # | Objetivo | Qué enseña |
|---|---|---|
| 1 | Funde dos lingotes y forja una espada | Puestos, recetas, calidad |
| 2 | Véndela en la Armería del mercado | Mercado, demanda |
| 3 | Cumple el encargo del carpintero: 2 martillos en 2 días | Tablón, plazos, prima |
| 4 | Cumple un encargo de calidad "buena" | Trabajar con cuidado y toque de maestro (4.4.5) |
| 5 | Compra con recado de entrega | No cargar a mano (4.5.7) |
| 6 | Devuelve la deuda antes del día 8 | Libro de cuentas, gestión del oro |

La cadena crece con los hitos (contratar al primer empleado en H4, primera mejora en H5…). Vive en `data/objectives/`.

### 4.17 Objetivos de dinastía y final de partida

**Formas de terminar:**

| Final | Cuándo | Desde |
|---|---|---|
| **Game Over** | Muere el cabeza de familia sin heredero válido (4.10.4) | H8 |
| **Ruina** | Embargo de la deuda inicial (4.16; pendiente D18) | H3 |
| **Cierre voluntario** | El jugador da por terminada la dinastía desde el menú (pendiente D19) | H8 |

**Metas de dinastía (opcionales).** Se ven en el panel de dinastía desde el principio. Cumplir una añade una entrada a la crónica y puntos; la partida sigue. Lista en `data/goals.json`, ampliable.

| Meta | Condición [balance] | Se puede cumplir desde |
|---|---|---|
| Alcalde | Un miembro de la familia gana el cargo de Alcalde | H10 |
| Cinco generaciones | El quinto cabeza de familia toma el mando (~4 herencias, ~70 h reales) | H8 |
| Fortuna | Patrimonio (oro + valor de edificios y mejoras) ≥ 20.000 oro | H6 |

**Puntuación de dinastía.** Sale de la **crónica** (4.14): cada tipo de hecho de la crónica vale unos puntos (`data/score.json`). Regla: lo que puntúa tiene que estar en la crónica; así la puntuación se puede recalcular y auditar.

| Hecho de la crónica | Puntos [balance] |
|---|---|
| Nacimiento en la familia / boda | 10 / 20 |
| Nueva generación (herencia) | 100 |
| Título: Ciudadano / Patricio / Barón / Nobleza | 25 / 75 / 200 / 500 |
| Cargo ganado: menor / medio / mayor / Alcalde | 30 / 60 / 120 / 250, +10 por año de mandato cumplido |
| Edificio construido o comprado | 15 |
| Juicio ganado / condena leve, media, grave | +20 / −30, −60, −150 |
| Meta de dinastía cumplida | 500 |
| Patrimonio máximo alcanzado | +1 por cada 100 oro |

**Pantalla final** (cualquiera de los tres finales): crónica resumida (generaciones, cabezas de familia con fechas, títulos, cargos, juicios, oro máximo), puntuación desglosada por tipo de hecho y metas cumplidas.

### 4.18 Libro de cuentas y registro de avisos (desde H3)

**Vive en el sim** (`WorldState.ledger`) y se guarda con la partida; la UI solo lo enseña.

- **Ningún sistema cambia el oro directamente:** todo movimiento pasa por una única función que apunta el asiento (como el inventario, 5.9). Así el libro siempre cuadra con el oro y los bots pueden medir de dónde sale y adónde va.
- **Asiento:** `{día, hora, familia, edificio | null, personaje, categoría, importe (+/−), ref}` (ref = id de la orden, encargo, préstamo o evento que lo causó).
- **Categorías:** las de la tabla de 4.19.
- **Retención:** detalle de los últimos **2 años** (16 días); lo anterior se guarda resumido por año, categoría y edificio (el guardado no crece sin límite).

**Panel** (botón del HUD): pestañas *Hoy* · *Por día* (últimos 8 días: ingresos, gastos y neto) · *Por edificio* (neto de cada edificio por categoría) · *Deudas y encargos* (préstamos y encargos abiertos con su plazo) · *Avisos*.

**Registro de avisos:** `{día, hora, gravedad (info / aviso / urgente), edificio o personaje, texto_key + parámetros, leído}`.

- Recoge los avisos de la cola (4.7.4), salarios y mantenimiento impagables, encargos a punto de vencer, la deuda, microeventos (4.20), objetivos cumplidos (4.16) y ataques detectados de familias rivales (4.21).
- Los urgentes salen además como aviso emergente. Clic en un aviso → centra la cámara en el edificio o personaje o abre su panel.
- Se guardan 1 año.

### 4.19 Fuentes y sumideros de oro

Todas las entradas y salidas de oro de una familia. La columna *Contraparte* dice adónde va el oro: si va a un NPC, sigue en la economía (el NPC lo gasta); si va al mercado o a la ciudad, sale del sistema (en el MVP no hay arcas municipales).

| Flujo | Tipo | Categoría del libro | Contraparte | Desde |
|---|---|---|---|---|
| Venta en el mercado | Fuente | `market_sales` | Mercado | H3 |
| Encargos (prima +40 %) | Fuente | `contracts` | NPC cliente | H3 |
| Préstamo recibido (deuda inicial) | Fuente diferida | `loans` | Prestamista | H3 |
| Venta en mostrador | Fuente | `counter_sales` | NPC cliente | H7 |
| Microeventos con premio | Fuente | `events` | — | H7 |
| Venta de edificio / demolición (30-50 %) | Fuente | `property` | NPC comprador / mercado | H6 |
| Salario de cargo, comisión del Recaudador | Fuente | `offices` | Ciudad | H10 |
| Servicios, cosechas, botín y rescates, intereses cobrados | Fuente | `services` / `market_sales` / `loot` / `loans` | NPC / mercado | EA (4.22) |
| Compras en el mercado | Sumidero | `purchases` | Mercado | H3 |
| Sobrecoste de recados (+20 %) | Sumidero | `errands` | Mercado | H3 |
| Devolución de deuda (+ recargo) | Sumidero | `loans` | Prestamista | H3 |
| Mantenimiento de edificios | Sumidero | `upkeep` | Ciudad | H3 |
| Salarios y bonus de empleados | Sumidero | `wages` | Empleado NPC | H4 |
| Mejoras | Sumidero | `upgrades` | Mercado | H5 |
| Multas de inspección | Sumidero | `fines` | Ciudad | H5 |
| Construcción y compra de edificios | Sumidero | `property` | Mercado / NPC vendedor | H6 |
| Microeventos con coste (regateo, médico) | Sumidero | `events` | — / NPC | H7 |
| Ceremonia de título (100 / 500 / 2.000 / 10.000) | Sumidero | `titles` | Ciudad | H9 |
| Campaña electoral y sobornos | Sumidero | `politics` | Ciudad / NPC | H10 |
| Impuestos (5-15 % de las ventas) | Sumidero | `taxes` | Ciudad | H10 |
| Condenas y sobornos a testigos | Sumidero | `justice` | Ciudad / NPC | H11 |
| Dote, adopción, donaciones | Sumidero | `family` / `donations` | NPC / ciudad | POST-MVP |
| Préstamo de urgencia (Equilibrio 2) | Fuente diferida | `loans` | Prestamista | equilibrio |
| Embargo de un bien: lo que sobra tras pagar (Equilibrio 2) | Fuente | `property` | Ciudad | equilibrio |
| **Pecha** por patrimonio al cierre del año (Equilibrio 5) | Sumidero | `taxes` | Ciudad | equilibrio |

**La pecha (Equilibrio 5, 2026-11-05).** Al cerrar cada año, toda familia con un negocio paga por su **patrimonio** (oro +
mercancía de sus edificios a precio de venta) un impuesto **progresivo por tramos marginales**: nada hasta 1.000, 4 %
de 1.000 a 3.000, 8 % de 3.000 a 10.000 y 12 % por encima [balance] (`data/accounts.json` `pecha`, `sim/balance/pecha.gd`).
Lo que el oro no cubre se debe a la villa como una multa (conserva el oro de trabajo). Muerde poco en los años 1-3 (un
herrero con 1.500-2.500 paga 20-60) y mucho en la generación (con 20.000, 1.840 al año). Los sumideros grandes
(construir, restaurar ruinas, comprar negocios) son de H6.

Los regalos no son un flujo propio (el oro ya salió al comprar el objeto). Las herencias tampoco (el oro cambia de manos dentro de la familia). Los robos de mercancía no mueven oro: salen en el registro de avisos con su valor estimado.

**Dianas de oro neto por día** (`data/targets.json` → `goldflow`), medidas por los bots sobre el libro de cuentas [balance]:

| Fase | Situación de referencia | Bot | Ventana | Oro neto/día (media) |
|---|---|---|---|---|
| Inicio (H3) | A mano, con deuda | `artisan_novice` | días 1-8 | +25 a +60 |
| Forja con empleados (H4-H5) | 1-2 empleados, cola, primeras mejoras | `artisan_expert` | días 9-24 (años 2-3) | +60 a +150 |
| Dos negocios (H6-H8) | Ciudadano | `artisan_expert` | años 4-6 | +120 a +300 |
| Patricio (H9-H11) | 3 o más negocios | `artisan_expert`, `politician` | años 7-12 | +250 a +600 |
| Barón y más (EA) | Varias cadenas | por definir en H12 | — | +500 a +1.200 |

Reglas que también vigilan los bots:

- Desde H4, los sumideros recurrentes (salarios + mantenimiento + impuestos) se comen entre el **30 % y el 60 %** de los ingresos brutos [balance]. **Ingresos brutos = margen bruto**: ventas + encargos − compras de materias − recados (decisión del manager en H5: sobre la facturación no cabe, las materias ya se comen ~65 % de las ventas). Se mide en `goldflow.staff` (`sink_base: margin`).
- Con empleados la familia gana claramente más que sin ellos (razón de ser de H4): `artisan_expert_0/1/2` con las mismas semillas.
- `artisan_novice` y `artisan_expert` no tienen oro neto negativo de media en ninguna ventana de 1 año, salvo el año de una obra grande.
- Con el bot `idle`, el oro de la familia solo baja por mantenimiento y deuda (no hay fuentes gratis escondidas).
- **Conservación:** en cualquier partida (incluido `random_clicker`), la suma de asientos de cada familia es igual a la variación de su oro. Ningún oro aparece ni desaparece fuera de esta tabla.

### 4.20 Microeventos (desde H7)

Sucesos pequeños de un edificio o un personaje que rompen la rutina y piden una decisión rápida. Son **datos** (`data/microevents/<id>.json`), con el mismo formato de efectos que los eventos globales (4.13).

- **Ficha:** `id`, ámbito (edificio / personaje / familia), disparador (fase del día y condiciones), probabilidad por día, enfriamiento, opciones con efectos declarativos, opción por defecto, `text_key`.
- **Frecuencia:** como mucho 1 microevento por familia y día; probabilidad base 35 % al día, modificada por la dificultad; cada microevento tiene un enfriamiento de 1 año por edificio [balance].
- **Presentación:** tarjeta no bloqueante con las opciones; el tiempo no se pausa. Si en **2 h de juego** no se elige, se aplica la opción por defecto. Queda en el registro de avisos.
- Elegir es una orden (`ResolveMicroevent(actor, mev, choice)`): las familias IA usan la misma.

| Microevento | Disparador | Opciones [balance] | Por defecto |
|---|---|---|---|
| **Cliente que regatea** | Cliente en el mostrador con Negociación ≥ 6 | (a) Aceptar −15 % y vender. (b) Mantener el precio: SkillCheck Carisma del vendedor vs Negociación del cliente; éxito, vende al precio; fallo, se va sin comprar y queda Ofendido. (c) Echarle: se va, relación −5. | (a) |
| **Empleado enfermo** | Amanecer, edificio con empleados | (a) Pagar al médico 10 oro: vuelve mañana, lealtad +5. (b) Día libre pagado: falta hoy, cobra el salario, lealtad +2. (c) Descontarle el día: falta 1-2 días, lealtad −5. | (b) |
| **Ladrón nocturno** | Noche, edificio propio con mercancía | Sin nadie dentro: roba 1-3 unidades del producto más valioso, salvo que lo frustre la protección de Seguridad (20 / 40 / 60 %). Con un familiar dentro: (a) Enfrentarse: SkillCheck Arte Marcial vs 5; éxito, huye sin nada; fallo, roba igual. (b) Dejarle: roba. | (b) |

### 4.21 IA de las familias rivales

**Requisito: este diseño se cierra y lo aprueba el owner [Gate] antes de empezar H6**, porque la competencia por parcelas ya la necesita.

**Diseño detallado** (perfiles, arquitectura por módulos, rivalidad, ataques, dificultad, hitos, dianas y preguntas abiertas): [04c_ia_rival.md](04c_ia_rival.md). Lo que allí se precisa sobre esta sección está resumido en su 4.21.1.

**Quién la usa:** toda familia con `controlled_by: "ai"`: el herrero rival desde H3 (con la versión simple de 4.5.5), las 5 familias rivales del EA y, [POST-MVP], las ramas cadetes (4.10.4).

**Reglas de juego limpio:**

- **Usa las mismas órdenes que el jugador** (5.5) y pasa las mismas validaciones. La IA no hace trampas en ningún nivel de dificultad: la dificultad cambia **cómo decide**, no lo que puede hacer.
- **Ve lo que vería un jugador:** precios, demanda, parcelas libres, cargos, reputación y títulos públicos. No ve el oro ni los inventarios de otras familias: usa estimaciones con ruido.

**Cómo decide (utility AI):**

- Al amanecer hace el plan del día y en cada cambio de fase lo reajusta. Coste acotado: como mucho N candidatos por familia y decisión, medido con `sim_bench`.
- Unos módulos proponen acciones candidatas: economía (comprar, producir, vender, contratar, mejorar), construcción (comprar parcela, construir, vender, quebrar), familia (cortejar, casarse, designar heredero), política (pedir título, presentarse, acciones de campaña) y hostilidad (ver abajo).
- Cada candidata se puntúa:
  ```
  utilidad = Σ peso_objetivo(perfil) × avance_estimado(acción, objetivo)
             − coste_oro_normalizado − riesgo × aversión_al_riesgo(perfil) + ruido(semilla, dificultad)
  objetivos: oro (patrimonio esperado en 1 año) · título (avance hacia el siguiente) · cargo (probabilidad de ganar el que quiere)
  ```
- Necesidad básica por encima de los objetivos: si la familia se queda sin heredero, cortejar y casarse pasan delante (para que las familias IA sobrevivan a las generaciones).
- **Perfil** (`data/ai_profiles/<id>.json`): pesos de oro, título y cargo; agresividad (0-1); aversión al riesgo; umbral de rivalidad; oficios preferidos. La honestidad sale de la actitud moral de la familia (4.2.3). Las 5 familias del EA tienen perfiles distintos (p. ej. una mercantil, una trepadora, una política, una agresiva, una devota).

**Rivalidad con el jugador** (0-100, por familia rival hacia cada familia) [balance]:

| Sube | | Baja | |
|---|---|---|---|
| Le ganas una parcela o una elección que quería | +20 | Con el tiempo | −1/día |
| Tu cuota de ventas de un objeto que ella también vende supera el 50 % | +1/día | Regalos y buena relación entre cabezas de familia | según relación |
| La acusas, la saboteas o le robas | +30 | | |
| Relación entre cabezas de familia < −30 | +1/día | | |

**Cuándo ataca al jugador:** rivalidad ≥ umbral, ha pasado el enfriamiento desde su último ataque y no es el **primer año de partida** (protección del inicio). Elige el ataque con la misma utilidad (lo que avanza sus objetivos menos el riesgo):

| Ataque | Requisitos | Efecto | Desde |
|---|---|---|---|
| **Guerra de precios** | Produce un objeto que el jugador vende | Durante 1 estación vende ese objeto aunque la demanda baje hasta 0,5 (ignora su umbral de venta), mientras su oro esté por encima de su reserva. Hunde la demanda y tus precios. | H6 |
| **Competir por parcela o cargo** | — | Compra la parcela que te interesa (respetando la válvula de 4.9) o se presenta contra ti. | H6 / H10 |
| **Juicio** | Motivo real (sabe de tus mejoras de Secretos por una inspección o un testigo; vio un robo) o, si su honestidad es baja, pruebas fabricadas (check de Sigilo) | Orden `Accuse` → tribunal (4.12.5). | H11 |
| **Sabotaje** | Intrigas [EA] | Daña un edificio (estado Dañado) o destruye la última mejora de una rama; la Seguridad lo reduce. | H13 |

Cada ataque detectado se apunta en el registro de avisos y en la crónica.

**Escala con la dificultad** [balance]:

| | Fácil | Normal | Difícil |
|---|---|---|---|
| Elección | Al azar entre las 3 mejores | La mejor, ruido medio | La mejor, ruido bajo |
| Umbral de rivalidad para atacar | 80 | 60 | 40 |
| Enfriamiento entre ataques | 2 años | 1 año | 1 estación |
| Peso de las acciones hostiles | ×0,5 | ×1 | ×1,5 |
| Expansión (comprar parcelas y construir) | ×0,5 | ×1 | ×1,5 |

**Implantación por hitos:** H3 herrero rival con IA fija (4.5.5) · H6 módulos de economía y construcción, quiebra y guerra de precios · H8 módulo de familia (bodas y herencias de las familias IA) · H9 títulos · H10 cargos · H11 juicio · H13 las 5 familias con perfil propio y sabotaje.

**Dianas** (sim de 10 años en Normal) [balance]: ninguna familia tiene más del 60 % de las parcelas de producción; al menos 2 familias IA suben de título; el jugador recibe entre 1 y 4 ataques; la válvula de parcelas se respeta siempre.

### 4.22 Sistemas propios de las otras clases [EA, diseñar en detalle antes de H12]

**Diseño detallado** (piezas comunes, Patrón, Erudito, Pícaro, guardado, órdenes, bots, arte y decisiones del owner): [04d_otras_clases.md](04d_otras_clases.md). Lo que allí se precisa sobre esta sección está resumido en su 4.22.1.

El Artesano se juega con los sistemas del MVP, pero las otras tres clases **no son solo datos**: cada una necesita un sistema nuevo en `sim/`. Aquí va el esbozo; el diseño detallado de cada uno se cierra y lo aprueba el owner [Gate] antes de empezar H12. La arquitectura reserva desde ya sus huecos (5.3 y 5.5) para no tener que rehacer nada.

**Pícaro: combate, robo y guardias**

- **Combate como orden** (`Attack(actor, target)`), resuelto en el sim, no de acción: asaltos de SkillCheck Arte Marcial contra Arte Marcial, modificados por equipo y Constitución. Resultado: vence, huye o cae derrotado. El derrotado queda herido (no actúa 1 día). La muerte solo en combates a muerte (sicarios, duelos), por decidir en el diseño detallado.
- **Robo** (`Rob(actor, target)`): a un edificio de noche (su almacén) o a una persona (carterista). Sigilo y Destreza contra la vigilancia: guardias, Seguridad del edificio y testigos. El botín es mercancía robada que solo compra un perista y por menos. Hay que decidir cómo se marca lo robado en el inventario (afecta a la clave de pila de 5.9).
- **Guardias:** NPC con rutina de patrulla nocturna por rutas del mapa. Ven un delito con su percepción contra el Sigilo del autor y arrestan (inicia juicio, 4.12.5). Los ladrones NPC de 4.12.6 y el ladrón nocturno de 4.20 usan el mismo sistema.
- Edificios: Guarida de ladrones y Nido de bandidos; cadena CRIMINAL (4.4.4): mercancía robada y rescates.

**Erudito: servicios que no son objetos**

- **Receta de tipo servicio** (`kind: "service"`): ocupa el puesto un tiempo, puede consumir entradas (vendas, hierbas, velas) y, en vez de un objeto, aplica un **efecto** a un cliente o a la ciudad y cobra un precio.
- **Médico:** curar a un enfermo o herido; la demanda sube con las epidemias (4.13) y con el combate del Pícaro.
- **Sacerdote:** misas en la Iglesia a horas fijas; los asistentes dejan donativo; da reputación y puede dejar el estado Inspirado.
- **Banquero:** **préstamos** (entidad `Loan`: prestamista, deudor, principal, interés, plazo, cuotas, garantía). Presta a NPC y a familias, cobra intereses y ejecuta garantías por el tribunal. La deuda inicial (4.16) ya usa esta entidad.
- Escriba y Alquimista producen objetos (documentos, pociones) con las recetas normales.
- Los clientes de servicios son NPC con una necesidad (enfermedad, fe, crédito) que llegan como los clientes de mostrador (4.5.4).

**Patrón: cultivos por estación**

- Los **campos** de las parcelas rústicas tienen estado (vacío → sembrado → creciendo → listo → cosechado) que avanza con las estaciones: se siembra en primavera y se cosecha en verano u otoño; en invierno no hay cultivo. Con D1(b) un ciclo de trigo dura ~2 estaciones (4 días, 20 min reales) [balance].
- Arar, sembrar y cosechar son puestos exteriores con las reglas de los puestos (4.4.3). El rendimiento depende de la estación y de los eventos (hambruna, buena cosecha).
- El ganado produce de forma continua (lana, carne) y come (sumidero de trigo).
- Posada y taberna venden servicios (comida y cama) con la receta de tipo servicio.
- El estado del campo vive en la parcela del `WorldState`.

### 4.23 Dificultad (D7)

Tres niveles: **Fácil, Normal, Difícil**. Se elige al crear la partida y se guarda en el `WorldState`. Cada palanca entra con su sistema. Las dianas de `data/targets.json` son las de Normal; los bots también corren Fácil y Difícil para comprobar que el orden se respeta (más oro neto en Fácil que en Normal, y en Normal que en Difícil).

| Palanca [balance] | Fácil | Normal | Difícil | Desde |
|---|---|---|---|---|
| Deuda inicial (4.16) | 100 | 200 | 300 | H3 |
| Herrero rival: Artesanía / demanda mínima para vender (4.5.5) | 4 / 0,9 | 5 / 0,8 | 6 / 0,7 | H3 |
| Precio de compra en el mercado | ×0,9 | ×1 | ×1,1 | H3 |
| Expansión de NPC y familias IA (4.9) | ×0,5 | ×1 | ×1,5 | H6 |
| IA rival: elección, umbral, enfriamiento (4.21) | ver 4.21 | | | H6 |
| Probabilidad de microeventos (4.20) | ×0,7 | ×1 | ×1,3 | H7 |
| Frecuencia de eventos globales (4.13) | ×0,7 | ×1 | ×1,3 | H13 |

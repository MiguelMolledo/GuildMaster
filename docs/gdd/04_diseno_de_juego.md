## 4. Diseño de juego

### 4.1 Tiempo y calendario

**Un único reloj de juego.** La unidad mínima de simulación es el **minuto de juego**.

| Unidad | Valor | Notas |
|---|---|---|
| Día | 24 h de juego = **5 min reales** (300 s) | D4. |
| Hora de juego | 12,5 s reales | 1 minuto de juego ≈ 0,21 s reales. |
| Estación | **2 días** (10 min reales) | Primavera, Verano, Otoño, Invierno. D1(b). |
| Año | 4 estaciones = **8 días** (40 min reales) | **Un único "año"** para el calendario, la edad, los mandatos y las estaciones (D1(b)). Cada año de calendario la gente cumple un año. |
| Generación | ~25 años ≈ 200 días ≈ **17 h reales** | Del nacimiento del heredero a que tiene sus propios hijos. |

**Variante de desarrollo** (`data/time.json` → `dev`): solo acorta el día (30 s reales). El calendario (2 días por estación, 8 por año) y todas las duraciones de la tabla de abajo se mantienen, para que lo que se prueba en dev mida lo mismo que el juego. Para no esperar se cargan escenarios guardados o se corre el sim sin ventana.

**Fases del día** (proporciones de primavera/otoño; el reloj las recalcula por estación):

| Fase | % del día | Horas | Ambiente y reglas |
|---|---|---|---|
| Amanecer (DAWN) | 10 % | 05-07 | Luz dorada. NPC salen de casa. Empleados llegan. Mercado cerrado. |
| Día (DAY) | 50 % | 07-19 | Luz plena. Producción y mercado abiertos. |
| Atardecer (DUSK) | 10 % | 19-21 | Luz naranja. Empleados se van, mercado cierra al final. Vida social. |
| Noche (NIGHT) | 30 % | 21-05 | Oscuridad, antorchas. Sin producción de empleados ni mercado. Solo taberna/posada ingresan. Acciones de intriga. |

| Estación | Amanecer | Día | Atardecer | Noche |
|---|---|---|---|---|
| Primavera | 10 % | 50 % | 10 % | 30 % |
| Verano | 8 % | 58 % | 8 % | 26 % |
| Otoño | 12 % | 44 % | 12 % | 32 % |
| Invierno | 8 % | 38 % | 8 % | 46 % |

**Reglas:**
- El tiempo **no se pausa** al abrir paneles de edificio, mercado o inventario. Solo se pausa con la pausa (o el menú de pausa).
- Velocidades: ×1, ×2, ×4 y pausa (D4).
- **Pausa activa:** con el juego en pausa se pueden seguir dando órdenes. No se ejecutan: se **encolan por personaje** (se ven como una lista numerada sobre su retrato) y empiezan al reanudar, en orden. Cada personaje tiene su cola de órdenes; una orden dada sin pausa sustituye a lo que quede en su cola. El menú de pausa (ESC sin paneles abiertos) sí bloquea las órdenes.
- Eventos del reloj: `minute_ticked`, `hour_changed`, `phase_changed`, `day_started`, `season_changed`, `year_changed`, `lights_on`/`lights_off`.

**Duraciones de referencia.** Todas las duraciones del diseño en un solo sitio. Regla de unidades: lo que pasa dentro de una jornada va en **horas de juego**; lo que dura de una jornada a una estación, en **días**; lo que dura más, en **estaciones o años**. Nunca en segundos reales (L8). Las cifras marcadas [balance] se ajustan con bots.

| Qué | Duración | Real a ×1 | Sección |
|---|---|---|---|
| Receta | 1-5 h | 12-62 s | 4.4.1 |
| Trabajo a mano "rápido" / "con cuidado" | duración ×0,7 / ×1,5 [balance] | — | 4.4.5 |
| Ventana del toque de maestro | 1 h | 12 s | 4.4.5 |
| Cliente de mostrador | 1 cada 1-2 h de DÍA | 12-25 s | 4.5.4 |
| Llegada de un recado de entrega | 2 h [balance] | 25 s | 4.5.7 |
| Actividades sociales de NPC | 15 min – 5,5 h | 3-70 s | 4.11.3 |
| Recuperación de la demanda | +0,4 por día [balance] (H5; era +0,1) | — | 4.5.3 |
| Salario impagado: gracia | 1 día | 5 min | 4.7.3 |
| Contratación / despido | efecto al amanecer siguiente / al final del día | — | 4.7.1 |
| Plazo de un encargo | 1-3 días [balance] | 5-15 min | 4.5.6 |
| Obra de mejora | 0,5-2 días [balance] | 2,5-10 min | 4.8 |
| Construcción de edificio | 1-4 días según tipo; Forja 2 [balance] | 5-20 min | 4.9 |
| Estados emocionales | 12 h – 7 días según estado [balance] | 2,5-35 min | 4.11.5 |
| Decisión de un microevento (caduca) | 2 h | 25 s | 4.20 |
| Campaña electoral | 1 estación (la última del mandato) | 10 min | 4.12.4 |
| Visita a familia influyente (campaña) | 4 h [balance] | 50 s | 4.12.4 |
| Preparación de un juicio | 1 estación | 10 min | 4.12.5 |
| Deuda inicial: plazo / prórroga | 1 año / 1 estación [balance] | 40 / 10 min | 4.16 |
| Primer hijo posible tras la boda | 1 estación; luego 10 %/día; 1 año entre hijos [balance] | — | 4.10.3 |
| Ascenso Aprendiz → Oficial / Oficial → Maestro | 1 año / 2 años más trabajados [balance] | 40 min / 80 min | 4.7.2 |
| Ladrón huido: no recontratable | 1 año | 40 min | 4.7.3 |
| Destierro | 1 año [balance] | 40 min | 4.12.5 |
| Mandatos | 1-4 años según cargo | 40 min – 2 h 40 | 4.12.3 |
| Enfriamiento entre ataques de una familia rival | 2 años (fácil) / 1 año (normal) / 1 estación (difícil) [balance] | — | 4.21 |
| Eventos globales | 1 estación – 1 año; fiestas y visitas 1-2 días [balance] | — | 4.13 |
| Edades del ciclo de vida | en años (8 días cada uno) | 16 años ≈ 10 h 40 | 4.2.5 |
| Libro de cuentas: detalle guardado | 2 años; después, resumen por año | — | 4.18 |
| Autoguardado | cada día al amanecer | — | 5.8 |

### 4.2 Personaje

#### 4.2.1 Clases y profesiones

| Clase | Fantasía de poder | Estilo | Profesiones |
|---|---|---|---|
| **Artesano** | Dominar la producción y el comercio | Gestión económica, cadena de suministro | Herrero, Carpintero, Albañil, Sastre |
| **Patrón** | Controlar los recursos básicos | Autosuficiencia, monopolios alimentarios | Granjero, Molinero, Panadero, Carnicero, Posadero |
| **Erudito** | El conocimiento como poder | Servicios especializados, banca tardía | Médico, Sacerdote, Alquimista, Escriba, Banquero |
| **Pícaro** | Poder desde las sombras | Combate, robo, microgestión alta | Ladrón, Bandido, Espía, Mercenario |

- La clase se elige al crear el personaje y **no cambia nunca**. Los hijos heredan la clase de la familia.
- La profesión se desbloquea con el primer edificio de ese tipo y puede cambiar dentro de la clase.
- A los 12 años, un hijo elige profesión dentro de la clase familiar.
- El Artesano funciona con los sistemas del MVP. Pícaro, Erudito y Patrón necesitan además **sistemas propios** (combate, robo y guardias; servicios; cultivos por estación): esbozo en 4.22.

#### 4.2.2 Atributos (10, rango 1-10)

| Atributo | Clave | Efecto principal |
|---|---|---|
| Carisma | `carisma` | Persuasión, cortejo, venta en mostrador |
| Empatía | `empatia` | Hacer aliados, detectar intenciones, duración de estados emocionales |
| Negociación | `negociacion` | Precios de compra/venta [Fase 2 de economía] |
| Conocimiento Arcano | `arcano` | Alquimia, medicina, recetas avanzadas (Erudito) |
| Destreza | `destreza` | Robo, esquivar, dados |
| Artesanía | `artesania` | Velocidad y calidad de producción, recetas desbloqueadas |
| Arte Marcial | `arte_marcial` | Combate, intimidar |
| Constitución | `constitucion` | Peso que puede cargar, salud, longevidad |
| Retórica | `retorica` | Debates, tribunal, discursos de campaña |
| Sigilo | `sigilo` | Espionaje, actividades ilegales sin ser detectado |

**Distribución inicial por clase:**

| Atributo | Artesano | Patrón | Erudito | Pícaro |
|---|---|---|---|---|
| Carisma | 4 | 5 | 5 | 3 |
| Empatía | 3 | 5 | 6 | 2 |
| Negociación | 6 | 6 | 4 | 3 |
| Arcano | 1 | 1 | 6 | 1 |
| Destreza | 4 | 3 | 2 | 7 |
| Artesanía | 7 | 4 | 3 | 2 |
| Arte Marcial | 3 | 2 | 1 | 7 |
| Constitución | 5 | 5 | 4 | 5 |
| Retórica | 3 | 5 | 6 | 2 |
| Sigilo | 2 | 2 | 1 | 7 |

> El código actual tiene Carisma 3 para el Artesano y el GDD 4. Usar el GDD (4).

**Creación de personaje (D5):** sobre la distribución de su clase, el jugador reparte **5 puntos libres** (rango 1-10 por atributo). También elige nombre, género y los colores de la familia (4.10.9).

**Capacidad de carga:** `60 kg + (constitucion - 5) × 3 kg` [propuesta; implementado: 60 kg fijos [balance], 30 → 60 en H5: con 30 kg (3 espadas) los viajes a vender se comían la jornada del dueño en cuanto la forja producía más].

#### 4.2.3 Actitudes morales de la dinastía (3 ejes, -100 a +100)

| Actitud | Sube con | Baja con |
|---|---|---|
| Honestidad | Negocios legales, pagar impuestos | Ilegalidad, sobornos, fraude, manipular juicios (-20) |
| Generosidad | Donaciones, eventos públicos, caridad | Acaparar, subir precios |
| Diplomacia | Alianzas, trato amable | Amenazas, guerras comerciales, insultos |

- Afectan a: probabilidad de inspección (Honestidad), voto de NPC, tolerancia de gremios [POST-MVP: expulsión al superar umbrales].
- Herencia: `actitud_hijo = (actitud_padre + actitud_madre) / 2 × 0,5`.

#### 4.2.4 Resolución de acciones (SkillCheck)

```
umbral = 50 + (stat_actor - stat_objetivo) × 5 + modificadores (equipo, estados, mejoras)
tirada = d100
  tirada ≤ 5   → éxito crítico
  tirada ≥ 96  → fallo crítico
  tirada ≤ umbral → éxito
```

Se usa para: halagar (Carisma vs Empatía), intimidar (Arte Marcial vs Arte Marcial), discurso (Retórica), convencer testigo (Retórica), fabricar pruebas y escándalos (Sigilo), etc. Debe ser **determinista con semilla** para poder testearse.

#### 4.2.5 Ciclo de vida

| Edad | Etapa | Mecánica |
|---|---|---|
| 0 | Nacimiento | Hereda stats (fórmula en 4.10.3). |
| 0-8 | Niño | Vive en la residencia. No controlable ni interactuable. Sin inventario propio. |
| 8 | Escuela | El jugador elige +1 a un atributo. |
| 12 | Aprendiz | Elige profesión (dentro de la clase). Se asigna a un edificio familiar. |
| 16 | Mayoría de edad | Se une al grupo de personajes controlables. Puede trabajar, casarse, heredar. |
| 18-25 | Plenitud joven | Máxima velocidad de aprendizaje. |
| 25-45 | Madurez | Stats estables, máxima productividad. |
| 45-55 | Declive | -1 Constitución cada 5 años; -1 Destreza. |
| 55-70 | Vejez | Declive acelerado, riesgo de enfermedad, +1 Retórica. |
| 60-75 | Muerte natural | Probabilidad anual creciente, modificada por Constitución. |

Con D1(b) un año son 8 días: un recién nacido llega a los 16 en ~10 h 40 reales y el protagonista (empieza con 20, ver 4.16) llega a los 55 en ~23 h. Las edades se cumplen todas a la vez al cambiar de año (`year_changed`).

**Probabilidad de muerte** [propuesta, el actual no la tenía cerrada]: a partir de 55 años, `p_anual = 0,02 × 1,25^(edad - 55) × (1 - (constitucion - 5) × 0,05)`, tirada una vez al cambiar de año. Con Constitución 5: ~10 % a los 62, ~33 % a los 68.

#### 4.2.6 Necesidades: dormir y comer

Hambre, descanso, social y diversión (0-100, `data/family.json` → `needs`). Para no convertirlo en un juego de
supervivencia (The Guild 3 quitó hambre y sed por microgestión; en The Guild II se dormía en casa para recuperarse),
al **personaje que controla el jugador solo le cuentan dos: Descanso y Hambre** (owner, 2026-11-07: «si no tienen que
dormir nunca puedo trabajar 24-7… al menos dormir y quizás comer de vez en cuando»). Social y diversión siguen como
estaban para los familiares IA (H14: moral = media, productividad hasta ×0,8). Las cifras son [balance].

**Descanso**
- Baja despierto, −4 por hora; trabajando de noche, −6 (×1,5). Desde lleno da para ~25 h despierto (16 h de día y
  unas 6 de noche trabajando: una noche en vela entera lo deja a cero al amanecer).
- Se recupera **durmiendo en casa** (+13 por hora: ~8 h lo llenan). Duerme quien está en casa de noche sin trabajar,
  o con un sueño en curso (Rendido, o un familiar IA que se va a descansar). Sin casa, donde esté.
- Por debajo de 30, **Cansado**: trabaja ×0,75 (la duración del ciclo se divide). Antes, por debajo de 40, avisa:
  «se está cansando: que duerma pronto».
- A 0, **Rendido**: deja lo que hace (para el ciclo; D11 devuelve las entradas), se va solo a casa a dormir, no
  obedece órdenes ni puede trabajar hasta tener 50. Aviso urgente.

**Hambre**
- Baja −3 por hora despierto. Se come de dos formas: **la cena va incluida al dormir en casa** (+6 por hora de sueño
  en casa) o con la orden **Comer** (1 h, +60): en casa gratis, o a la puerta de una Taberna-Posada por 1 moneda (a la
  familia dueña) y +10 de social.
- Por debajo de 30, **Hambriento**: trabaja ×0,85 (con Cansado, ×0,64). Nunca mata ni enferma.
- Así, quien duerme cada noche en casa casi nunca tiene que pensar en comer.

**Sin microgestión: la Rutina.** Cada personaje controlado tiene el interruptor **Rutina** en su ficha, encendido por
defecto: de noche lo manda a dormir a casa y al mediodía (12-15 h) a comer si el hambre baja de 60, sin que se lo
pidas. Antes de la noche no repite un ciclo que acabaría más de una hora después de que empiece; al llegar la noche,
un ciclo al que le quede más de una hora se para (las entradas vuelven al almacén) y uno más corto se acaba. **Una
orden manual siempre manda**: la que se da con la Rutina queriendo algo se cumple (trabajar de noche a mano repite
toda la noche, pagándolo en descanso); al acabarla, vuelve la Rutina. Quien la apague decide él y lo paga en descanso.
Si su rutina programable (4.10.8) pone Trabajar de noche, la Rutina no lo acuesta; si pone Descansar, descansa ella.

**Familiares.** Los familiares controlados y los IA usan las mismas reglas: los IA duermen de noche (`ai_rest_phases`)
y, con hambre o descanso bajos, comen o duermen en casa antes que seguir su directiva (4.10.6).

**Interfaz.** Dos barritas junto a cada retrato del grupo (descanso azul, hambre dorado; rojas por debajo de 30, con
las cifras y el estado en el tooltip); el estado (Cansado, Rendido, Hambriento) junto al nombre en la tarjeta del HUD y
en la ficha, con el interruptor Rutina y los botones Comer y Taberna; una línea del tutorial (Primeros pasos) lo
explica. Sim: `sim/family/needs.gd` y `sim/family/needs_routine.gd`; órdenes `eat` y `set_needs_routine`.

Los bots juegan como un jugador con la Rutina encendida (`NeedsRoutine.bot_filter`: no dan órdenes a un personaje
mientras duerme, come o la Rutina lo lleva). Las partidas viejas cargan sin versión nueva: los campos nuevos
(`needs_routine`, `vitals`) faltan y valen lo de por defecto (Rutina encendida, sin nada en curso).

### 4.3 Objetos e inventario

#### 4.3.1 Categorías

| Categoría | Pila máx. | Peso típico | Precio base típico | Ejemplos |
|---|---|---|---|---|
| Materias primas | 99 | 1-3 kg | 3-6 | hierro, carbón, trigo, lana, madera, hierbas, piedra |
| Materiales | 50 | 2-5 kg | 12-18 | lingote de hierro, harina, tablas, tela |
| Productos | 20 | 1-10 kg | 30-80 | espada, pan, ropa común |
| Herramientas | 1 | 0,5-7 kg | 25-40 | martillo, sierra, aguja, azadón |
| Equipamiento | 1 | 2-10 kg | 35-80 | ropa de trabajo, capa de viaje, armadura |
| Consumibles | 10 | 0,5-1 kg | 8-10 | vendas, comida preparada |
| Especiales | 5 | 0,1 kg | 3-8 | documento, llave, contrato |

#### 4.3.2 Catálogo inicial (MVP)

| ID | Categoría | Peso | Precio base | Puesto de mercado |
|---|---|---|---|---|
| `hierro` | materia prima | 2,0 | 5 | recursos |
| `carbon` | materia prima | 1,0 | 3 | recursos |
| `madera` | materia prima | 3,0 | 6 | recursos |
| `piedra` | materia prima | 3,0 | 4 | recursos (**añadir**: la pide una mejora) |
| `trigo` | materia prima | 1,0 | 4 | recursos |
| `lana` | materia prima | 1,0 | 5 | recursos |
| `hierbas` | materia prima | 0,5 | 3 | boticario |
| `lingote_hierro` | material | 4,0 | 18 | materiales |
| `harina` | material | 2,0 | 12 | materiales |
| `tablas` | material | 3,0 | 15 | materiales |
| `tela` | material | 2,0 | 14 | materiales |
| `espada` | producto | 8,0 | 65 | armería |
| `armadura` | equipamiento (ropa) | 10,0 | 80 | armería |
| `pan` | producto | 1,0 | **8** | alimentos (el actual tiene 35, incoherente con el GDD: 5) |
| `ropa_comun` | producto | 3,0 | 45 | ropería |
| `martillo` | herramienta | 6,0 | 35 | armería |
| `sierra` | herramienta | 7,0 | 40 | armería |
| `aguja` | herramienta | 0,5 | 25 | armería |
| `azadon` | herramienta | 5,0 | 30 | armería |
| `ropa_trabajo` | equipamiento | 3,0 | 35 | ropería |
| `capa_viaje` | equipamiento | 2,0 | 40 | ropería |
| `vendas` | consumible | 1,0 | 8 | boticario |
| `comida_preparada` | consumible | 0,5 | 10 | alimentos |
| `documento`, `llave`, `contrato` | especial | 0,05-0,1 | 3-8 | — |

#### 4.3.3 Calidad

Todo objeto producido tiene calidad: **normal (×1,0)**, **buena (×1,3)**, **excelente (×1,6)** sobre el precio. Se muestra como sufijo ("Espada buena"). Objetos de distinta calidad **no** se apilan juntos. Los NPC prefieren la calidad superior.

#### 4.3.4 Quién tiene inventario

| Entidad | Restricción | Límite base |
|---|---|---|
| Personaje (≥16 años) | Peso | 60 kg [balance] (ver 4.2.2) |
| Edificio productivo | Nº de pilas | 10 pilas; +10 con "Almacén ampliado" |
| Residencia familiar | Nº de pilas | 50 pilas (almacén de la familia) |
| Carreta [POST-MVP] | Peso | 50 / 150 / 300 kg según tipo |

- **Un único inventario por edificio** con materias primas y productos juntos.
- **Ranuras de equipo** por personaje: herramienta, ropa, accesorio. Equipar no saca el objeto del peso total.
- Herramienta adecuada equipada: +10 % de probabilidad de subir un nivel de calidad y bonus de velocidad.
- **Transferencias** solo con proximidad física: personaje ↔ edificio (dentro, panel de almacén), personaje ↔ personaje de la familia (cerca), personaje ↔ carreta [POST-MVP].
- Al morir, el inventario del difunto pasa al almacén de la residencia (o al heredero si no hay residencia).

### 4.4 Producción y recetas

#### 4.4.1 Recetas

Cada receta define: `id`, `building_type`, `zone_type` (puesto donde se hace), `inputs` (lista de item+cantidad), `output` + `output_qty`, `duration` (**en horas de juego**), `min_skill` (Artesanía mínima).

**Recetas de la Forja (MVP):**

| ID | Puesto | Entradas | Salida | Duración | Artesanía mín. |
|---|---|---|---|---|---|
| `forja_lingote` | horno | hierro ×2 | lingote_hierro ×1 | 1,3 h [balance] | 1 |
| `forja_martillo` | yunque | lingote ×1 + carbón ×1 | martillo ×1 | 2,6 h [balance] | 2 |
| `forja_espada` | yunque | lingote ×2 + carbón ×1 | espada ×1 | 3,9 h [balance] | 4 |
| `forja_armadura` | yunque | lingote ×3 + carbón ×1 | armadura ×1 | 6,5 h [balance] | 6 |
| `forja_acero` | horno | lingote ×2 + carbón ×2 | acero ×1 | 3,9 h [balance] | 6 (**crear**: la desbloquea "Forja de maestro") |

> Duraciones [balance] ×1,3 en H5 (D14, bot `artisan_expert`): con las de antes el dueño solo producía tanto que un empleado no añadía nada; ahora la mano de obra del dueño es escasa y el empleado la multiplica. El novato sigue en su diana de H3.

> Las duraciones actuales eran 3-7 segundos reales. Se pasan a horas de juego para que un empleado haga varias piezas por jornada (≈12 h de día) y no cientos. Ajustar en balance.

**Recetas del resto del Artesano (H12)** [balance]. Cada taller copia la Forja: un puesto para el intermedio (como el horno), otro para los productos (como el yunque), mostrador y almacén; huella de 4.6.1 (Carpintería y Albañilería 3×4, Taller de sastre 3×3), mantenimiento 20, 10 pilas, 1 empleado, vivienda básica. La materia prima que en EA sale de otra cadena (madera del aserradero, lana de la granja, piedra) se compra de momento en el puesto de Recursos, como el hierro. Cifras puestas para que el margen por hora con Artesanía 7 quede como el de la Forja (espada ≈ 4,3 oro/h); la costura, un 15 % más lenta tras medir con el bot (el sastre tiene el taller más cerca de la plaza y salía por encima de la diana).

| Oficio (herramienta) | Puesto | Receta | Entradas | Salida (precio base) | Duración | Artesanía mín. |
|---|---|---|---|---|---|---|
| Carpintero (sierra) | caballete | `carpentry_planks` | madera ×2 | tablas (15) | 1,3 h | 1 |
| | banco | `carpentry_barrel` | tablas + hierro (herrajes) | barril (35) | 2,6 h | 2 |
| | banco | `carpentry_chest` | tablas ×2 + hierro | arcón (65) | 3,9 h | 4 |
| | banco | `carpentry_cabinet` | tablas ×3 + hierro | armario (80) | 6,5 h | 6 |
| | caballete | `carpentry_cart_wheel` | tablas ×2 + hierro | rueda de carro (65) | 5,2 h | 6 (la desbloquea Producción 3) |
| Albañil (martillo) | banco de corte | `masonry_ashlar` | piedra ×2 | sillar (12) | 1,3 h | 1 |
| | banco de tallar | `masonry_grindstone` | sillar + madera | piedra de afilar (32) | 2,6 h | 2 |
| | banco de tallar | `masonry_trough` | sillar ×3 | abrevadero (60) | 3,9 h | 4 |
| | banco de tallar | `masonry_millstone` | sillar ×4 + piedra ×2 | muela de molino (80) | 6,5 h | 6 |
| | banco de tallar | `masonry_statue` | sillar ×5 | estatua (110) | 7,8 h | 6 (Producción 3) |
| Sastre (aguja) | telar | `tailor_cloth` | lana ×2 | tela (14) | 1,3 h | 1 |
| | mesa de costura | `tailor_work_clothes` | tela + lana | ropa de trabajo (35) | 3,9 h | 2 |
| | mesa de costura | `tailor_travel_cloak` | tela + lana | capa de viaje (40) | 4,55 h | 3 |
| | mesa de costura | `tailor_common_clothes` | tela + lana ×2 | ropa común (45) | 4,55 h | 4 |
| | mesa de costura | `tailor_fine_clothes` | tela ×3 + lana | ropa fina (80) | 6,5 h | 6 (Producción 3) |

Sillar (material), barril, arcón, armario, rueda, piedra de afilar, abrevadero, muela, estatua y ropa fina son objetos nuevos (`data/items/`). Cada oficio tiene su ficha en `data/professions/` (taller, herramienta, inicio y tabla de encargos).

- Las recetas por debajo de `min_skill` se ven bloqueadas con candado; las que no tienen entradas suficientes en el almacén, deshabilitadas.
- La duración efectiva: `duracion / (velocidad_trabajador × multiplicador_mejoras)`.

#### 4.4.2 Calidad resultante

Se decide **al terminar** la producción según la Artesanía de quien la hace:

| Artesanía | Normal | Buena | Excelente |
|---|---|---|---|
| 1-3 | 80 % | 18 % | 2 % |
| 4-6 | 50 % | 40 % | 10 % |
| 7-9 | 20 % | 50 % | 30 % |
| 10 | 5 % | 40 % | 55 % |

Modificadores: herramienta adecuada +10 % de subir un nivel; mejoras de rama Calidad +1/+2/+3 escalones de bonus [definir en datos].

#### 4.4.3 Producción por puestos (WorkZones)

- Cada edificio tiene **puestos** (horno, yunque, mostrador, almacén…). Cada puesto admite **una persona a la vez**.
- Trabajar en un puesto = consumir las entradas al **empezar** el ciclo, producir al **terminar**. Si se interrumpe, las entradas **se devuelven** al almacén del edificio (D11); si no caben, quedan en el inventario de quien trabajaba o, si tampoco, en el suelo del puesto hasta que alguien las recoja.
- Si el almacén está lleno, el puesto se bloquea y avisa.
- **Auto-repetición:** quien trabaja repite la receta mientras haya entradas, salvo que se le ordene parar.
- **Restricción nocturna:** los empleados no trabajan de noche. El jugador sí puede trabajar a mano de noche en Forja/Horno, pagándolo en descanso (×1,5) y con su Rutina queriendo llevarlo a dormir salvo que se lo mande a mano (4.2.6).
- Requisitos para producir: edificio en estado Normal (ni en obras ni dañado), alguien en el puesto, entradas suficientes, hueco en el almacén.

#### 4.4.4 Cadenas de producción (EA)

```
METAL:     Mina de hierro → Forja → herramientas, armas, armaduras
PAN:       Granja (trigo) → Molino → Panadería → pan, pasteles
TEXTIL:    Granja (lana) → Taller de sastre → ropa, telas de lujo
MADERA:    Aserradero → Carpintería → muebles, barriles
ALQUIMIA:  Herbolario → Botica → Alquimista → pociones, venenos
CARNE:     Granja (ganado) → Carnicería → carne, embutidos
CRIMINAL:  Nido de bandidos → Guarida → mercancía robada, rescates
SERVICIOS: Taberna, Posada, Scriptorium, Banco (sin materia prima)
```

#### 4.4.5 Trabajar a mano: modo y toque de maestro

> **El toque de maestro está sustituido por la «Forja viva»** (calentar, batir, templar: [03b_diversion_y_ritmo.md](03b_diversion_y_ritmo.md)
> §3b.2 y §3b.8; owner, 2026-11-05). La orden `master_touch` ya no la da la interfaz: el puesto no parpadea ni pinta
> la ventana, un clic en él solo lleva al puesto y no hay pista de tutorial; en el yunque de la forja el modo «con
> cuidado» lo ocupa la Forja viva, y en los otros oficios «con cuidado» sigue (×1,5 de tiempo, Artesanía +2) pero sin
> toque. En el sim la orden y su ventana siguen, para cargar partidas viejas con un ciclo «con cuidado» a medias y
> para los bots que la dan (el novato del herrero en los encargos con calidad y los novatos de los otros oficios);
> pasar al novato a la Forja viva mueve sus dianas y espera al owner (`live_for_quality`, §3b.8). Lo de abajo
> describe esa regla del sim.

Cuando un personaje **controlado por el jugador** trabaja en un puesto (orden `WorkAt`), no se limita a esperar la barra: elige **cómo** trabaja y puede intervenir durante el ciclo.

| Modo | Duración | Calidad (tabla de 4.4.2) | Para qué |
|---|---|---|---|
| **Rápido** | ×0,7 | se lee con Artesanía −3 (mín. 1) | Cumplir un plazo, vender volumen cuando la demanda está alta. |
| **Normal** | ×1,0 | Artesanía real | Por defecto. |
| **Con cuidado** | ×1,5 | se lee con Artesanía +2 (máx. 10) y habilita el toque de maestro | Encargos con calidad mínima, piezas para el mostrador. |

Cifras [balance].

- El modo se elige al empezar (menú contextual del puesto: Trabajar rápido / Trabajar / Trabajar con cuidado) y se puede cambiar entre ciclos. Se repite con la auto-repetición.
- **Toque de maestro** (solo "con cuidado"): a mitad de cada ciclo se abre una ventana de **1 h de juego** (12 s a ×1) marcada sobre el puesto. Si el jugador da la orden `MasterTouch` en ella (clic en el puesto) con ese personaje dentro, la pieza gana **+15 % de probabilidad de subir un escalón de calidad** [balance]. Si no lo da, no se pierde nada. Así trabajar a mano premia la atención sin castigar al que está mirando otra cosa.
- La ventana es un hecho del sim (minuto de inicio y fin), no de la vista: la orden se valida contra el reloj y es determinista.
- Los empleados y los familiares con directiva IA trabajan siempre en modo Normal y sin toque de maestro: la ventaja de calidad de trabajar a mano es del jugador.
- El modo afecta solo al ciclo en curso: si se interrumpe, se aplica D11 (entradas devueltas).

### 4.5 Mercado y precios

#### 4.5.1 La plaza del mercado

- **3 puestos exteriores** (interacción directa, sin cambiar de vista): Recursos (materias primas), Alimentos (comida, consumibles), Materiales (lingotes, harina, tablas, tela).
- **3 tiendas con interior** (se entra como en un edificio): Armería (herramientas, armas, armaduras), Ropería (equipamiento, ropa), Boticario (hierbas, vendas, pociones).
- Todos abren el **mismo panel** con pestañas *Comprar* y *Vender*, filtrado por las categorías de ese puesto.
- **[H12, decidido 2026-11-03]** Mientras no haya tiendas con interior para ellos, la Ropería es un puesto exterior más de la plaza y hay un cuarto puesto exterior, **Enseres** (muebles, barriles y piedra labrada). La Ropería pasará a tienda con interior cuando lleguen las tiendas de EA.

- La plaza es pública: no se compra ni se mejora. El jugador no trabaja en los puestos.
- Horario: abierto solo en **DÍA** y **ATARDECER**; cerrado en amanecer y noche.

#### 4.5.2 Panel de compra/venta

- *Comprar*: lista con icono, nombre, precio unitario, selector de cantidad (+/−), botón Comprar. Deshabilitado si no hay oro o no cabe por peso (tooltip con el motivo). Stock ilimitado en Fase 1.
- *Vender*: objetos del inventario del personaje que encajan en el puesto, con cantidad, precio de venta, botones "Vender 1" / "Vender todo". **Nunca** se puede vender más de lo que hay; la lista se refresca tras cada venta.
- Oro actual siempre visible. Se cierra con ESC, con X o si el personaje se aleja.

#### 4.5.3 Fórmula de precios

**Fase 1 (MVP):**
```
precio_compra  = round(precio_base × calidad × demanda × mod_estado_npc × mod_regulacion)
precio_venta   = round(precio_compra × 0,70)
demanda        ∈ [0,5 ; 2,0]   (por objeto)
   - baja 0,04 [balance] por unidad que vende en el mercado cualquier actor (jugador, herrero rival, familias IA), unidad a unidad: vender n de golpe cobra lo mismo que vender n veces 1 (0,05 → 0,1 en H3 con artisan_novice; 0,1 → 0,04 en H5 con artisan_expert: con 0,1 el dueño solo ya llenaba el mercado y un empleado no tenía dónde vender)
   - se recupera +0,4 [balance] por día hacia 1,0 (era +0,1; H5)
```

Las entregas de encargos (4.5.6) no tocan la demanda del mercado. Si las ventas en mostrador la tocan está pendiente (D16).

**Fase 2 (EA):**
```
precio = precio_base × calidad × demanda × mod_estación × mod_evento × mod_estado_npc × mod_negociación × mod_regulación
mod_estación (por categoría):
  Primavera: alimentos ×0,8
  Verano:    alimentos ×0,7, textiles ×0,9
  Otoño:     madera ×1,2
  Invierno:  alimentos ×1,5, construcción ×1,3, medicina ×1,4
mod_evento: hambruna alimentos ×2,5 · epidemia medicina ×3,0 · guerra armas ×1,5 (era ×2,0; owner, 2026-11-03) y alimentos ×1,5
mod_negociación: descuento del 1 % por punto de Negociación por encima de 5 [propuesta]
demanda: oferta/demanda reales de la ciudad, límites [0,3 ; 3,0]
```

#### 4.5.4 Venta en mostrador (en tu propio edificio)

Requiere la mejora *Mostrador de venta*. Los NPC clientes entran, esperan, un empleado (o el jugador) los atiende en el mostrador y se llevan un producto.

```
precio = precio_base × calidad × (1 + bonus_vendedor + bonus_edificio + bonus_reputación)
bonus_vendedor   = carisma/100 + bonus_equipo + bonus_rango (aprendiz 0 / oficial 0,05 / maestro 0,10)   → +5 % a +25 %
bonus_edificio   = mejoras de Comercio + Fachada                                                          → +5 % a +20 %
bonus_reputación = min(reputación_familia / 100 × 0,15 ; 0,15)                                             → 0 a +15 %
```

Frecuencia de clientes [propuesta]: 1 cliente cada 1-2 h de juego durante el DÍA; `customer_bonus` de las mejoras de Comercio la aumenta.

**D16 (2026-11-05):** cada unidad vendida en el mostrador baja también la demanda del mercado **−0,025** (la mitad que
en la plaza; `data/town.json` `counter.demand_drop_per_unit`). **Equilibrio 13:** la **fama del taller** (0,5-2,0, 04g
§4.6.5.7) divide el tiempo entre clientes y suma `(fama − 1) × 0,1` al precio.

#### 4.5.5 Competencia: el herrero rival (desde H3)

Desde la rebanada vertical el jugador no está solo en el mercado: **un herrero NPC con su propia Forja** compite por la misma demanda.

- Es un personaje completo de una familia IA (`controlled_by: "ai"`, perfil `rival_smith` en `data/ai_profiles/`), con Forja propia en otra parcela de la calle, Artesanía 5, 80 oro y sin deuda [balance].
- **Usa las mismas órdenes que el jugador** (`Buy`, `WorkAt`, `Sell`, `AcceptContract`, `DeliverContract`): no tiene atajos. Sus ventas bajan la demanda igual que las tuyas (4.5.3) y también puede aceptar encargos del tablón (4.5.6): el primero que acepta se lo queda.
- **IA simple (rebanada):** al amanecer y en cada cambio de fase decide por este orden:
  1. **Vender** lo que tiene, objeto a objeto, mientras su demanda esté ≥ 0,8 [balance]. Por debajo, guarda.
  2. **Elegir receta:** la de mayor margen esperado `precio_venta_actual − coste_entradas` entre las que su Artesanía permite.
  3. **Comprar** las entradas para un día de trabajo si le alcanza el oro, dejando una reserva de 20 oro [balance].
  4. **Producir** durante el DÍA en su Forja, en modo Normal.
  5. **Encargos:** acepta uno del tablón si su Artesanía permite la receta y calcula que llega al plazo con su producción del día; le da prioridad sobre la venta libre.
- No contrata, no mejora y no quiebra en la rebanada: si se queda sin oro, deja de comprar hasta vender. Desde H6 pasa a regirse por la IA de familias rivales (4.21), con contratar, mejorar, construir y quebrar.
- La dificultad (4.23) cambia su Artesanía y su umbral de venta.
- **Talleres competidores (H12):** en town_e hay un taller de cada oficio del Artesano. El del oficio con el que empiezas es tuyo; los demás son de una familia IA cada uno (perfil `rival_artisan`) que juega con esta misma IA, sin títulos, cargos ni acusaciones hasta que 04c se apruebe, y que empieza casada (una familia casada no corteja: el pueblo guarda sus solteros para el rival y el jugador). **El rival es siempre de tu oficio** (decidido 2026-11-03): si empiezas de carpintero, albañil o sastre, un rival de ese oficio ocupa el solar que la Forja del jugador deja libre junto a la plaza (`rival_<edificio>` del mapa) con el perfil `rival_smith`, y el herrero Bernat pasa a ser un competidor más. Así la dificultad (Artesanía y umbral de venta del rival) pesa igual en todos los oficios.

- Diana: el rival termina los primeros 10 días con oro en `[40, 300]` y la demanda de la espada no pasa más de 1 día seguido por debajo de 0,6 por su culpa (bot `idle` + rival) [balance].

#### 4.5.6 Encargos de NPC (contratos, desde H3)

Los NPC piden piezas concretas con plazo. Es dinero mejor pagado que el mercado y, en las primeras horas, un **tutorial implícito** (cada encargo enseña una receta o un modo de trabajo).

| Campo | Valor inicial [balance] |
|---|---|
| Objeto y cantidad | 1-5 unidades de un producto que el cliente necesita (al principio, solo de la Forja) |
| Calidad mínima | En ~30 % de los encargos (buena o excelente) |
| Plazo | 1-3 días desde que se acepta |
| Pago | `cantidad × precio_venta_actual(objeto, calidad) × 1,4` (**prima +40 %**), fijado al publicarse |
| Cumplir | Pago + reputación +2 + relación con el cliente +5 |
| Incumplir (vence o se abandona) | Reputación −5, relación con el cliente −15, el cliente no ofrece encargos en 1 año |

- Se publican en un **tablón de encargos** de la plaza (objeto del mapa): como mucho 3 visibles; sale 1 nuevo cada amanecer si hay hueco.
- `AcceptContract(actor, contrato)` en el tablón; como mucho 2 aceptados a la vez por familia. `DeliverContract(actor, contrato)` en el tablón con las piezas en el inventario del personaje: se quitan del inventario y se cobra.
- Los encargos de inicio están guionizados en el escenario de partida nueva (4.16); después salen de una tabla de datos por profesión (`data/contracts/`). Desde H12 el tablón saca los encargos de la tabla del oficio del cabeza de familia del jugador (un carpintero recibe encargos de carpintería); si no hay ninguna, de todas.
- El libro de cuentas los apunta en su categoría y el registro de avisos avisa 1 día y 2 h antes de que venzan (4.18).

#### 4.5.7 Recado de entrega (desde H3)

Comprar en un puesto del mercado y que la mercancía **llegue sola al almacén** de un edificio propio, a cambio de un sobrecoste.

- En el panel de compra, junto a *Comprar*, el botón *Comprar y enviar a…* con la lista de edificios propios. Orden `Buy(actor, stall, item, qty, deliver_to = bld)`.
- El personaje tiene que estar en el puesto y el mercado abierto (es una compra normal); lo que se ahorra es **cargar el peso** y el viaje.
- Sobrecoste **+20 %** sobre el precio de compra [balance]. Llega al almacén en **2 h de juego**. El hueco del almacén se comprueba y se reserva al pedir: si no cabe, la orden se rechaza con el motivo.
- El sobrecoste sale aparte en el libro de cuentas (categoría `recados`) para que se vea lo que cuesta la comodidad.
- El aprovisionamiento **automático** (sin ir al mercado) sigue siendo [POST-MVP] (4.7.6) y es más barato (+10 %) porque lo desbloquea una mejora.

### 4.6 Edificios

#### 4.6.1 Catálogo y tamaños (huella en casillas isométricas)

| Categoría | Edificio | Huella | Notas |
|---|---|---|---|
| Residencia | Choza / Casa / Mansión | 2×2 / 3×3 / 5×5 | Mansión ocupa 2 parcelas de vivienda. |
| Extractivo | Granja (base) | 4×6 | Ampliable con parcelas rústicas adyacentes (4×4). |
| | Mina de hierro / Aserradero / Herbolario | 4×4 / 4×5 / 3×3 | |
| Taller | Forja / Carpintería / Albañilería | 3×4 | |
| | Taller de sastre / Molino | 3×3 / 4×4 | |
| Alimentación | Panadería / Carnicería | 3×3 | |
| Servicios | Taberna / Posada / Iglesia | 4×4 / 4×5 / 4×6 | |
| | Consulta médica / Botica / Scriptorium | 3×3 / 3×3 / 3×4 | |
| Comercial | Armería / Ropería / Boticario | 3×4 / 3×3 / 3×3 | Tiendas públicas del mercado. |
| Financiero | Banco / Almacén | 4×5 / 4×4 | |
| Gobierno (no comprables) | Ayuntamiento / Tribunal / Mercado / Catedral | 6×6 / 5×5 / 8×6 / 6×8 | Fijos en el mapa. |
| Criminal | Guarida de ladrones / Nido de bandidos | 3×3 / 4×4 | |

#### 4.6.2 Estados

| Estado | Efecto |
|---|---|
| En construcción | No produce. Andamiaje visible. Contador de días. |
| Normal | Funciona. |
| Dañado | Eficiencia reducida; hay que repararlo. Lo causan sabotaje, incendio, revuelta. |

#### 4.6.3 Propiedad y vivienda

- Cada edificio tiene **un dueño** (ID de personaje o de familia) o ninguno (público).
- **Todo negocio incluye vivienda básica**: no hace falta casa aparte al principio. Cuando hay pareja e hijos se necesita una casa separada [propuesta: penalización de moral/reputación si la familia ≥3 vive en el taller].
- **Mantenimiento diario** por edificio (`upkeep` en la ficha; 20 oro la Forja [balance]: era 2, subido en H5 para que los sumideros recurrentes pesen 30-60 % del margen bruto y el rival sin competencia no acumule oro) **entra en el MVP** (D12), desde H3: se cobra cada amanecer junto con los salarios, sale en el libro de cuentas y da sentido a no acumular edificios vacíos. Qué pasa si no se puede pagar está pendiente (D15).

#### 4.6.4 Interiores

> Ampliado en [04g_interiores.md](04g_interiores.md) (4.6.5, 2026-11-04): biblioteca de props a partir de referencias de fal, interiores por datos con habitaciones, desniveles y dos plantas, paredes que se abren, mostrador con cola y clientes que aparecen en su sitio de acción.

- Al entrar (personaje o modo gestión) la vista pasa a una **escena interior isométrica** propia de cada tipo de edificio. El exterior se ve negro. Transición: fundido de ~0,3-0,5 s. El juego no se pausa.
- **Entrar con personaje:** el personaje camina a la puerta y aparece dentro; se mueve libre por el interior (limitado al suelo navegable).
- **Gestionar (modo omnisciente):** se abre el interior sin personaje, para gestionar con el ratón: almacén, empleados, cola, mejoras.
- **Salir:** puerta de salida o ESC → vuelve al mapa delante del edificio.
- Barra de herramientas del interior (arriba a la derecha): **Mejoras · Almacén · Empleados · Producción**.
- Clic izquierdo en un puesto = ir allí; clic derecho = menú contextual (Trabajar, Cambiar receta, Examinar).
- Puestos ocupados muestran indicador. Barra de progreso sobre el puesto activo.
- Las mejoras se ven en el interior (nuevo yunque, tapices, suelo de piedra) y algunas en el exterior (cartel, cerradura, fachada).
- **Interiores con kit modular:** todos los interiores se montan con las mismas piezas (suelos, paredes, puerta, ventanas, mobiliario genérico) más los **puestos propios del oficio** (horno, yunque, telar…). Las mejoras de las ramas comunes (Capacidad-almacén, Personal, Fachada, Seguridad, Secretos, Comercio) usan **visuales genéricos reutilizables** entre oficios (estantería llena, literas, mesa de comedor, tapices, caja fuerte, mostrador); solo Producción y Calidad piden una variante del puesto del oficio. Presupuesto de arte en 9.3.
- Solo se entra en edificios propios o públicos (tiendas del mercado). [POST-MVP: entrar en edificios ajenos, p. ej. taberna].

### 4.7 Trabajadores

#### 4.7.1 Contratación

- Candidatos: NPC adultos de la ciudad **sin empleo**. El panel muestra retrato, nombre, rango, atributos relevantes (Artesanía, Carisma, Constitución) y salario.
- Requisitos: hueco de empleado libre en el edificio, NPC desempleado, oro para el salario.
- El empleado empieza a trabajar **al día siguiente**, al amanecer.
- Los empleados **son NPC del mundo** (mismo personaje que pasea por la ciudad): llegan al amanecer caminando, trabajan, se van al atardecer a su casa.
- Huecos de empleado: 1 al principio; +1 por mejoras de rama Personal.

#### 4.7.2 Rangos

| Rango | Salario/día | Eficiencia | Velocidad | Disponibilidad | Asciende |
|---|---|---|---|---|---|
| Aprendiz | 7 oro [balance] | 50 % | ×1,0 [balance] | Abundante | → Oficial tras **1 año** (8 días) trabajado si lealtad > 50 [balance] |
| Oficial | 20 oro [balance] | 100 % | ×2,0 [balance] | Media | → Maestro tras **2 años** más (16 días) si lealtad > 70 [balance] |
| Maestro | 40 oro [balance] | 150 % | ×3,0 [balance] | Escasa (requiere mejora "Taller de maestro") | — |

> Salarios y velocidades [balance] cambiados en H5 (D14, bot `artisan_expert` con 0/1/2 empleados): antes 1/3/6 oro y ×0,5/×1/×1,5. Un empleado trabaja de alba a atardecer (~11 h) y el dueño también de noche; con ×1 un oficial aportaba un 30 % de lo que hace el dueño y no compensaba ni su salario. Con ×2 un oficial produce como el dueño en su jornada; con 20 oro/día los salarios + mantenimiento pesan un 30-60 % del margen bruto (4.19).

- Al poder ascender, se avisa al jugador: aceptar (+15 lealtad, sube el salario) o rechazar (-10 lealtad).
- Eficiencia efectiva: `base_rango × mod_lealtad × mod_estado (cabreado 0,8 / agradecido 1,1) × mod_equipo`. Siempre produce al menos 1 unidad por ciclo.

#### 4.7.3 Lealtad (0-100)

| Sube | | Baja | |
|---|---|---|---|
| Salario pagado a tiempo | +1/día | Salario impagado | -5/día |
| Bonus manual (+5 oro) | +5 | Rechazar ascenso | -10 |
| Ascenso | +15 | Edificio dañado | -2/día |
| Mejora de Fachada | +5 | | |
| Mejora "Comedor" | +10 una vez | | |

| Lealtad | Consecuencia |
|---|---|
| 70-100 | Normal. |
| 40-69 | Eficiencia -20 %; rumores (reputación -1). |
| 20-39 | 5 %/día de **abandonar** sin aviso. |
| 0-19 | 3 %/día de **robar** 1-3 unidades del producto más valioso y huir (no recontratable en 1 año). La rama Seguridad divide la probabilidad entre 2. |

- **Salarios reales:** se cobran del oro del dueño cada amanecer. Si no hay oro: aviso, 1 día de gracia, luego -5 lealtad/día y reputación -2.
- **Despido:** el NPC se va al final del día. Si su lealtad era > 70: reputación -2.
- No se puede demoler un edificio con empleados.

#### 4.7.4 Cola de producción

El jugador no da órdenes individuales: define **qué quiere producir** y el sistema reparte el trabajo.

- La cola es una lista ordenada de entradas `{receta, cantidad (1, 5, 10, ∞)}` con opción **bucle** global y botón **pausar**.
- **Resolución por unidad con dependencias:** para producir 1 espada, si faltan lingotes y hay hierro, primero se funden los lingotes necesarios para *esa* espada, luego se forja. Nunca se acumulan 100 intermedios antes del primer producto.
- Si una entrada no se puede producir (falta materia prima base), se marca con **aviso** y se salta a la siguiente. Si ninguna se puede, aviso general y empleados ociosos.
- **Rol de cada empleado:** cada empleado tiene una tarea asignada (`horno`, `yunque`, `mostrador` o `cualquiera`). **Regla corregida tras BUG-023:** un empleado con rol fijo **solo** trabaja en su tipo de puesto; solo `cualquiera` va donde haga falta.
- **Prioridades** de un empleado libre: 1) atender cliente si es su rol (o si es `cualquiera` y nadie más puede); 2) tarea de la cola en su tipo de puesto; 3) idle.
- Un puesto, una persona. Con más de un empleado y un solo yunque, el segundo espera o hace otra cosa permitida por su rol.
- Avisos: falta de materias primas, almacén lleno, empleado ocioso (icono sobre el edificio en el mapa exterior), abandono, robo, salario impagable. Todos quedan en el **registro de avisos** del libro de cuentas (4.18).
- **La cola corre en la simulación**, se esté mirando el edificio o no.

#### 4.7.5 Equipo de empleados [POST-MVP]

Mismas 3 ranuras que el jugador. Herramienta: +velocidad/+calidad; ropa: +eficiencia; accesorio: +lealtad/+carisma de venta. Si el empleado roba y huye, se lleva su equipo.

#### 4.7.6 Aprovisionamiento automático [POST-MVP]

En el MVP, la forma de no cargar a mano es el **recado de entrega** (4.5.7, desde H3). Lo automático llega después:

- **Pedido automático** (Comercio nivel 3): el edificio compra del mercado cuando un recurso baja de un umbral configurable; +10 % de sobrecoste; presupuesto diario máximo.
- **Rol Corredor** (Personal nivel 3): un empleado va caminando al mercado, compra a precio normal y vuelve. Ocupa un hueco.

### 4.8 Árbol de mejoras

- Cada tipo de edificio tiene su propio árbol: **8 ramas × 3 niveles** (ampliable).
- Ramas: **Producción** (velocidad, recetas), **Capacidad** (puestos y almacén), **Calidad**, **Comercio** (mostrador, clientes), **Personal** (huecos, lealtad), **Fachada** (reputación, requisito de títulos), **Seguridad** (robo, sabotaje), **Secretos** (ilegal: beneficio a cambio de riesgo de inspección).
- Coste: oro + materiales (del almacén del edificio) + atributo mínimo del dueño + título mínimo + días de obra.
- Dentro de una rama, el nivel N requiere el N-1. Además hay prerrequisitos cruzados.
- **Solo una obra a la vez** por edificio. ~~Durante la obra el edificio no produce.~~ **Equilibrio 9 (2026-11-05):** la
  obra **pequeña** (≤ 1 día de obra, `data/upgrade_rules.json` `works.small_max_days`) se hace **de noche**: queda lista
  al alba siguiente y el edificio no para; la **grande** deja el edificio trabajando **a medio ritmo** (los ciclos que
  empiezan durante la obra tardan el doble, `works.big_speed` 0,5) mientras dura. Por qué: el jugador completo pasaba
  14-25 h parado en cada obra (5-7 atascos por partida de 3 años) y el ritmo de 03b §3b.5 («ningún tramo de más de
  60 s sin decidir») no se cumplía en días de obras. Las obras guardadas antes siguen con la regla vieja (cerrado) hasta
  acabar. Los bots de antes de H5 la fijan cerrada en sus pruebas (`tests/balance_pins.gd`).
- Las mejoras son permanentes. Un evento (incendio, sabotaje, revuelta) puede destruir **la última mejora** de una rama; hay que pagarla de nuevo. Seguridad reduce la probabilidad.
- Cada mejora tiene efectos declarativos (`production_speed`, `extra_storage`, `new_zone`, `max_employees`, `quality_bonus`, `price_multiplier`, `customer_bonus`, `loyalty_bonus`, `reputation`, `protection`, `inspection_risk`, `illegal_profit`…) y visuales (nodo interior / overlay exterior que aparece).

Los árboles de la Carpintería, la Albañilería y el Taller de sastre (H12) copian el de la Forja con las mismas cifras: cambian el material (tablas, sillares o tela en vez de lingotes; hierro, piedra o lana en vez de carbón), los puestos nuevos de Capacidad (segundo banco / segundo caballete, etc.) y la receta que desbloquea Producción 3 [balance].

**Árbol de la Forja (implementado en el primer intento, conservar):**

| Rama | Nivel 1 | Nivel 2 | Nivel 3 |
|---|---|---|---|
| Producción | Fuelle mejorado — 15 oro, 2 madera, 0,5 d → velocidad ×1,2 | Temple avanzado — 40 oro, 5 lingotes, 1 d → ×1,4 | Forja de maestro — 100 oro, Artesanía 6, 1 d → ×1,6 + receta acero |
| Capacidad | Segundo yunque — 50 oro, 5 lingotes, 3 madera, 1 d → puesto yunque 2 | Almacén ampliado — 40 oro, 8 madera, 1 d → +10 pilas | Tercer horno — 125 oro, 10 lingotes, Artesanía 5, 1,5 d → puesto horno 2 |
| Calidad | Acero templado — 25 oro, 3 carbón, 1 d → calidad +1 | Grabado fino — 60 oro, Artesanía 5, 1 d → +2 | Sello de maestro — 150 oro, Artesanía 7, 1,5 d → +3 y precio ×1,5 |
| Comercio | Mostrador de venta — 30 oro, 4 madera, 1 d → ventas directas | Escaparate exterior — 75 oro, 3 lingotes, 1 d → clientes +30 % | Reputación comercial — 125 oro, requiere Fachada 1, 1 d → clientes +50 %, precio ×1,1 |
| Personal | Dormitorio aprendiz — 40 oro, 6 madera, 1 d → +1 empleado | Comedor — 60 oro, 5 madera, 1,5 d → lealtad +10 | Taller de maestro — 150 oro, requiere Capacidad 2, 1,5 d → +1 empleado, permite maestros |
| Fachada | Fachada de piedra — 75 oro, 10 piedra, 1,5 d → reputación +10 | Jardín y plantas — 100 oro, 5 madera, 1,5 d → +20 | Fachada noble — 200 oro, título Ciudadano, 2 d → +30 |
| Seguridad | Cerradura reforzada — 25 oro, 2 lingotes, 1 d → protección 20 % | Guardia contratado — 75 oro, 1 d → 40 % | Caja fuerte — 150 oro, 8 lingotes, 1 d → 60 % |
| Secretos | Doble contabilidad — 50 oro, 1 d → impuestos -10 %, riesgo inspección +5 % | Pasadizo oculto — 100 oro, 5 madera, Sigilo 3, requiere Seguridad 1, 1 d → escapar de una inspección | Contrabando — 175 oro, Sigilo 5, 1 d → beneficio ilegal ×2, riesgo +15 % |

> Días de obra [balance]: la mitad que en el primer intento, para que con D1(b) (año = 8 días) una obra de nivel 3 no pare la producción casi medio año.
>
> Costes en oro [balance] ×5 en H5 (D14, bot `artisan_expert`): la tabla ya da las cifras nuevas (antes 3, 8, 20…). Con ×5 el experto sigue en su diana de oro neto (4.19); más caro retrasa las primeras mejoras más allá del año 3.

**Inspecciones (rama Secretos):** cada día, por edificio con mejoras de Secretos: `p = Σ inspection_risk × (1 - honestidad_dueño/200)`. Si te pillan: multa y juicio automático (ver 4.12). El "Pasadizo oculto" permite evitar una inspección.

### 4.9 Parcelas y construcción

- El mapa tiene **parcelas predefinidas**. No se construye fuera de ellas. Tres tipos con zonificación estricta:
  - **Rústica** (campos, afueras): granjas, mina, aserradero, herbolario.
  - **Producción** (barrio artesano, centro): talleres, alimentación y servicios.
  - **Vivienda**: choza, casa, mansión.
- **Parcela = huella** del edificio que admite (la parcela guarda su tamaño en casillas).
- **Modo construcción** (botón del HUD o tecla): el mapa resalta las parcelas — verde rústica, naranja producción, azul vivienda, gris ocupada. Se elige parcela → lista de edificios compatibles con coste y requisitos → confirmar → pagar → obra.
- **El primer edificio del jugador ya está en pie al empezar** (MVP: la Forja con vivienda, ver 4.16). Los siguientes tardan **1-4 días** según tipo (`build_days` de la ficha; Forja 2) [balance].
- **Comprar edificio a un NPC:** `precio = (coste_construcción + valor_mejoras) × mod_relación` con `mod_relación` de 0,8 (muy buena) a 1,5 (mala); por debajo de un umbral el NPC se niega. Tras vender, el NPC: relación buena/neutra → acepta trabajar para ti; regular → monta negocio en otra parcela; mala → se va de la ciudad.
- **Demoler** (solo propios, sin empleados): instantáneo, devuelve 30-50 % del coste, las mejoras se pierden. Los vecinos con buena relación reaccionan mal.
- **Granjas ampliables:** se compran parcelas rústicas adyacentes que se vinculan como puestos exteriores; no cuentan como edificio extra.
- **Competencia NPC:** los NPC también compran parcelas y construyen, decidido por la IA de familias rivales (4.21, diseñada antes de H6). Velocidad según dificultad (4.23). **Válvula anti-bloqueo:** siempre quedan al menos 2 parcelas libres por tipo; los NPC con negocios poco rentables quiebran o venden.

#### 4.9.1 Solares, ruinas y negocios en venta (petición del owner, 2026-11-05)

> «En las ciudades tiene que haber también zonas libres para poder construir de cero, tanto dentro como fuera de la
> ciudad, o edificios en ruinas, o edificios en buena localización que tengan su negocio pero se lo puedas comprar y
> reconvertirlo a lo que quieras».

Cada mapa trae, además de los edificios del inicio, una lista de **parcelas** (`plots` en `data/maps/<mapa>.json`):

| Estado | Qué es | Qué se puede hacer [balance] |
|---|---|---|
| **Solar libre, dentro** | Hueco entre casas, en la calle mayor o en una secundaria | Construir de cero (4.9), caro si está bien situado |
| **Solar libre, fuera** | En el arrabal, junto a un camino o en el campo (rústica) | Construir más barato; menos clientes de paso |
| **Ruina** | Un edificio abandonado (techo hundido, muros en pie) | Comprar barata (×0,3 del coste de construir) y **restaurar** con una obra (×0,5 y la mitad de días) para el uso que quieras de los que caben en su huella |
| **Negocio de un NPC** | Un taller, una tienda o una casa con dueño y su oficio | **Comprarlo** (fórmula de 4.9, con `mod_relación`) y quedarte con su oficio, o **reconvertirlo**: una obra (×0,4 del coste y 1 día) que lo pasa a otro edificio de su misma huella y zona (una tienda de telas se vuelve armería). El antiguo dueño se queda de empleado o se va (4.9) |

- **Situación** (`location` 0-1 por parcela): sale de la distancia a la plaza, a la calle mayor y a las puertas, y del
  paso de gente. Multiplica el precio y los clientes de la comarca (04g §4.6.5.7). Una ruina en la calle mayor es la
  ganga; un solar en el arrabal, lo barato.
- **Dentro y fuera de la muralla:** en las ciudades con muralla (Bellcaire, Montsacre) hay parcelas a los dos lados.
  Las de fuera no pagan el impuesto de la villa [propuesta], pero sus vecinos están más expuestos a los bandidos
  (4.24.5).
- **El generador de ciudades** (tools/city) reparte las parcelas por reglas: en cada ciudad deja al menos 2 solares
  dentro, 2 fuera, 1-3 ruinas y los negocios de NPC que salgan, y marca su situación. Además respeta la válvula
  anti-bloqueo de 4.9: siempre quedan parcelas libres de cada tipo.
- **Cómo se ve:** el solar es un descampado con estacas, la ruina un greybox de muros rotos (sprite más adelante), y el
  negocio en venta lleva un cartel «Se vende».
- **Comprar, construir, restaurar y reconvertir son de H6** (con la IA rival construyendo, 4.21), que espera el Gate de
  04c. Las parcelas y su aspecto en los mapas se pueden preparar ya. Hoy ya existe la compra de un edificio en venta
  (la Taberna-Posada, 04f §4.27).

**Implementado en H6 (la parte del jugador y de los NPC, rama posada, 2026-11-06)** [balance, `data/construction.json`]:
`sim/build/plots.gd` (Plots) lleva el estado de las parcelas del mapa en `state.parcels` (solo lo que cambia: una
partida vieja lee lo mismo, sin versión nueva), `sim/build/construction.gd` (Construction) termina las obras y decide la
construcción de las familias IA. En la interfaz, el **modo construcción** (B) pinta las parcelas por zona (verde rústica,
naranja producción, azul vivienda, gris ocupada) y un clic abre su **carta** (`game/build/plot_card.gd`) con zona,
tamaño, lugar (dentro o extramuros) y situación, y lo que se puede hacer con su precio y sus días o por qué no.

- **Construir** en un solar: el coste de construir del edificio × la situación (de ×0,8 a ×1,3 según `location`), y
  ×0,85 extramuros; la obra dura sus `build_days`. **Restaurar** una ruina: ×0,3 de compra + ×0,5 de obra y la mitad de
  días. Una casa cuesta 120. Cabe lo que entra en la parcela, también girado un cuarto.
- **La obra**: el edificio está en estado `construction` (andamio y barra en el mapa, la cara «en obra» de su fachada):
  no produce, no paga mantenimiento y no cuenta todavía como negocio para los títulos; al acabar avisa.
- **Reconvertir** uno propio a otro de su zona que quepa: ×0,4 del coste del nuevo y 1 día; se pierden sus mejoras.
- **Derribar** uno propio sin empleados ni nadie dentro: devuelve el 40 % (decidido 2026-11-02) y la parcela vuelve a
  ser un solar; no el único techo de la familia; reputación −2 con los vecinos.
- **Comprar a un NPC** su negocio (botón «Comprar…» de su barra o su carta): `(coste + oro de sus mejoras) × mod_relación
  × situación`, con mod_relación de 0,8 (relación ≥ +60) a 1,5 (≤ −60); por debajo de −40 no vende. Sus empleados se van
  con él. Después, según la relación: ≥ +20 se queda en el pueblo sin negocio (`after_sale.fate` stays; «acepta trabajar
  para ti» queda [provisional]: a los miembros de una familia IA aún no se les contrata), ≥ −20 monta negocio en otra
  parcela (la construcción de su familia lo busca primero), por debajo se va y no construye más.
- **Tope por título**: cuenta todos los edificios de la familia menos la taberna (O-V11) y los que están en obra sí
  cuentan. Un Plebeyo con su forja no construye: para el segundo negocio hace falta ser Ciudadano. La taberna cuenta
  como negocio para los requisitos de los títulos (decisión «Equilibrio 4 · Barón»).
- **Válvula**: una familia IA solo toma una parcela libre si después quedan al menos 2 de esa zona; el jugador puede
  tomar la última.
- **La IA** (04c §4.21.6.2): al amanecer, desde el día 9 y con un enfriamiento de 8 días por familia, cada familia IA
  con perfil mira las 3 parcelas libres de producción mejor situadas donde cabe un taller de sus oficios y los edificios
  en venta de sus oficios; puntúa `beneficio esperado × 16 días × expansión / precio` y construye o compra la mejor que
  pase de 1 y pague con su oro por encima de su reserva. Una familia que vendió su taller toma la mejor que pueda pagar.
  Las órdenes (`build`, `buy_building`) son de gestión, como las del jugador. `data/construction.json` `ai.enabled`
  apaga este paso cuando la agenda de 04c (sim/ai) lo llame por su cuenta (`Construction.candidates` / `choose` /
  `order_for`, contrato en 04c §4.21.6.2). Un **segundo** edificio (con su taller en pie) espera a `ai.expand`, apagado
  hasta que la economía de sim/ai sepa llevarlo (contratar, cola, vender de su almacén): hoy una forja nueva de la IA
  se queda vacía y la arruina. Sin él, solo monta taller la familia que vendió el suyo.
- **Cuántas parcelas libres trae una ciudad** (regla del owner, 2026-11-06): **4-5 de producción** (solares y ruinas),
  **al menos 2 del tamaño de un taller (3×4 o 4×3)**, y **3-4 de vivienda de 3×3** (una casa). Así la IA puede tomar
  2-3 sin tocar la válvula y siempre quedan 2 de cada zona para el jugador. Vilarrasa (town_e) la cumple con
  `tools/maps/make_town_e.py`: la ruina 3×3 y el solar 3×2 de dentro, dos solares de taller de 3×4 al norte del
  callejón de arriba (plot_21 extramuros y plot_22 dentro) y cuatro de vivienda de 3×3 en esa franja; las otras cinco
  ciudades, `tools/city/plots.py` (plantillas, 2026-11-07: `tools/city/reglas.json` `plots.rule`, que el validador
  exige en las seis): 5 de producción con 2 de 3×4 o 4×3 sobre hierba (dentro si cabe, si no junto a la villa) y 4 de
  vivienda de 3×3 (decisión del manager, 2026-11-07). En un segundo solar de taller cabe también una segunda taberna (O-V12).
- **Rústica**: las parcelas rústicas se ven en el modo, pero todavía no hay edificios que levantar en ellas (granjas,
  minas, aserraderos: 4.22).

**Límite de edificios por título:**

| Título | Edificios propios |
|---|---|
| Común | 1 |
| Ciudadano | 2 |
| Patricio | 4 |
| Barón | 6 |
| Nobleza | Sin límite |

### 4.10 Familia y dinastía

#### 4.10.1 Cortejo (MVP: por afinidad)

- **Afinidad** 0-100 con cada NPC soltero (distinta de la *relación* general -100..+100; ver 4.11.4).
- Acciones: conversar (+3-5, con enfriamiento por NPC y día), regalar (+5-15 según valor), trabajar cerca (+1/día).
- Multiplicador por Carisma: `× (1 + (carisma - 5) × 0,1)`. Misma clase social: ×1,15.
- Estados emocionales: positivos (agradecido, halagado) dan bonus; negativos (ofendido, cabreado) **bloquean** el cortejo.
- Con afinidad ≥ 80 aparece **"Proponer matrimonio"**. Requisitos: ambos ≥ 16 años, ambos solteros, afinidad ≥ 80.
- Al casarse, la pareja se muda a la residencia y pasa a la familia.
- [POST-MVP] Eventos sociales (bailes, ferias), dote, cortejo avanzado (Retórica + reputación).

#### 4.10.2 Pareja

Personaje completo (stats, inventario, edad). **No ocupa** hueco de los 3 controlables: actúa siempre con IA. Directiva por defecto: Trabajar en el edificio asignado. Puede morir; el jugador puede volver a casarse.

#### 4.10.3 Hijos

- Primer hijo posible **1 estación** (2 días) después de la boda; desde entonces, probabilidad diaria 10 %. Tras un nacimiento, **1 año** (8 días) sin nuevo hijo. Máximo 3 por pareja. [balance] Con estas cifras el primer hijo llega de media ~1,5 años después de la boda (≈ 1 h real).
- Herencia de atributos: `stat_hijo = (stat_padre + stat_madre) / 2 + aleatorio(-1, +1)`, límite 1-10, +1 si ambos padres tienen ≥ 7.
- Crecimiento: ver tabla de 4.2.5. A los 16 se une al grupo controlable.
- [POST-MVP] Hijos con IA autónoma completa: se casan solos (notificación), emigran si la relación con la familia es mala.

#### 4.10.4 Herencia y sucesión

- El jugador **designa heredero** en cualquier momento (árbol genealógico). Por defecto: el hijo mayor ≥ 16.
- Al morir el personaje principal, el heredero recibe: edificios (con mejoras y empleados), oro, inventario, título social. **Los cargos públicos no se heredan** (quedan vacantes). Los hermanos conservan lo suyo.
- Si el heredero tiene < 16 años, la pareja superviviente gestiona hasta su mayoría de edad.
- **Sin heredero válido → Game Over** con la crónica resumida y la **puntuación de dinastía** (4.17).
- [POST-MVP] **Hermanos no herederos como rivales internos:** al heredar, cada hermano adulto del nuevo cabeza de familia con relación muy mala con él (umbral en datos) puede **fundar una rama propia**: sale de la familia con su oro y los edificios que tenga asignados y pasa a ser una familia IA (4.21) que empieza con relación hostil. Hace que elegir heredero y cuidar las relaciones dentro de la familia importe. Detallar umbrales y probabilidades antes de implementarlo.
- [POST-MVP] Adopción: si no hay hijos, adoptar un NPC < 25 años y soltero a cambio de oro + reputación.

#### 4.10.5 Grupo controlable

- Hasta **3 personajes controlables**: el principal + hijos ≥ 16 (+ adoptados).
- Cambiar con **teclas 1-2-3** o clic en el retrato del HUD; doble clic centra la cámara. El activo tiene borde dorado.
- Cada uno tiene inventario, posición y estado propios. HUD e inventario se actualizan al cambiar.
- Los no seleccionados siguen su **rutina** (4.10.8) y, en las franjas libres, su **directiva IA**.

#### 4.10.6 Directivas IA de familiares

| Directiva | Comportamiento | MVP |
|---|---|---|
| Trabajar | Va al edificio asignado y produce en el puesto que le toque | ✅ |
| Sociabilizar | Habla con NPC, sube relaciones, busca pareja | POST-MVP |
| Divertirse | Taberna, paseo, descanso (recupera necesidades) | POST-MVP |
| Aprender | Sube atributos de su oficio lentamente | POST-MVP |
| Comerciar | Compra materias primas y vende productos | POST-MVP |

El jugador ordena las directivas por prioridad; la IA las equilibra con las necesidades. **Los familiares IA usan las mismas órdenes que el jugador** (ver arquitectura, 5.5).

#### 4.10.7 Árbol genealógico (tecla F)

Panel superpuesto (no pausa). Fundador arriba, descendientes abajo; scroll y zoom. Cada nodo: retrato, nombre, edad (o edad de muerte), clase. Indicadores: controlable (borde dorado), no controlable (gris), muerto (opaco + cruz), heredero (corona), activo (resaltado). Cónyuges unidos con línea horizontal y anillo; hijos colgando de la pareja. Clic → ficha lateral con atributos, actitudes y acciones: **Designar heredero**, **Asignar edificio**, **Cambiar a este personaje**.

#### 4.10.8 Rutina programable de los personajes controlados

Para no microgestionar a 3 personajes a la vez, cada personaje controlado tiene un **horario por franjas** del día (Amanecer, Día, Atardecer, Noche).

| Acción de la franja | Qué hace | MVP |
|---|---|---|
| **Trabajar** | Va al edificio y puesto indicados y trabaja la receta y el modo elegidos (4.4.5), con auto-repetición | ✅ |
| **Descansar** | Va a casa y se queda | ✅ |
| **Libre** | Sigue su directiva IA (4.10.6) | ✅ |

- Se edita en la ficha del personaje (retrato del HUD → *Rutina*). Por defecto: Día = Trabajar en su edificio asignado; el resto, Libre.
- La rutina se traduce en **las mismas órdenes** que daría el jugador (`MoveTo`, `EnterBuilding`, `WorkAt`); el sim la guarda en el personaje (`schedule`) y se serializa.
- **Una orden manual manda sobre la rutina:** el personaje cumple su cola de órdenes (4.1, pausa activa) y, al vaciarla, vuelve a la franja que toque.
- De noche los familiares pueden tener Trabajar (como el jugador, 4.4.3); los empleados no. Trabajar de noche cuesta descanso (×1,5, 4.2.6); con Trabajar en la franja de Noche, la Rutina no los acuesta.

#### 4.10.9 Identidad visual de la familia

Hay que reconocer a los tuyos (y a cada familia rival) de un vistazo, sin capas de ropa (sprites monolíticos en el MVP).

- **Variación por paleta:** cada sprite de personaje se genera con unos **colores clave reservados** para pelo, piel, ropa principal y ropa secundaria. Un shader de intercambio de paleta los sustituye al dibujar: 6 tonos de pelo, 4 de piel [balance] y **la ropa principal en el color de la familia** (la ficha de familia guarda `colors: {primary, secondary}`, elegidos al crear la partida para la tuya y fijados en datos para las rivales).
- **Rasgos heredables:** pelo y piel se heredan de uno de los padres al azar (semilla del sim), con una probabilidad baja de tono nuevo [balance]. Los hijos se parecen a sus padres y la familia se reconoce en el árbol genealógico.
- El mismo intercambio se aplica a los **retratos** (HUD, árbol, contratación) y al color del borde del retrato.
- Rasgos de forma (barba, peinado, complementos) necesitan capas: quedan para la customización por capas [POST-MVP].
- Coste de arte: ninguna generación extra; lo que exige es que los sprites respeten los colores clave (8.4, 9.6).
- **Retrato base** (población, 2026-11-03): cada persona tiene un retrato base de su tipo social (artesano, vecino humilde, mercader, noble, clérigo, guardia, erudito, granjero, pícaro), su sexo y su franja de edad (niño ≤11, joven 12-17, adulto 18-44, maduro 45-59, anciano 60+), con las zonas de pelo (barba incluida), piel y ropa en los colores clave; el retrato cambia de franja al envejecer, como el sprite, y el pelo encanece con la edad. Lo reparte el generador de población (4.11.1, `docs/contratos/poblacion.md`).

### 4.11 Ciudad viva: NPC

> Ampliada en [04f_vida_y_fiestas.md](04f_vida_y_fiestas.md) (4.24-4.27, 2026-11-04): agenda de actividades con necesidades, puntos de reunión y rumores, más población y forasteros, guardia, sucesos, fiestas, juegos y la Taberna-Posada.

#### 4.11.1 Población

- MVP: 15-20 NPC con rutina. EA: 30-40 NPC y 5 familias rivales.
- Todo NPC es un **personaje completo** (mismo modelo de datos que la familia del jugador): clase, profesión, atributos, edad, casa, trabajo, dinero.
- Las casas de NPC no tienen interior: el NPC desaparece en la puerta y reaparece al salir.
- **Reparto generado** (población, 2026-11-03): cada partida nueva reparte con su semilla los nombres, los apellidos de casa, las edades (dentro de un rango por papel), el aspecto y la personalidad de los vecinos, el rival, los competidores y la propuesta del protagonista (`data/cast.json`). Lo que pesa en el balance (atributos de los personajes clave, oro, deuda, edificios, oficios, rangos, el orden de edad de los vecinos) sale de los datos y no cambia. El reparto de los datos («reparto fijo») queda para pruebas, escenarios y dianas. Cada ciudad saca su propia gente. Contrato: `docs/contratos/poblacion.md`.

#### 4.11.2 Rutina diaria

| Fase | Comportamiento |
|---|---|
| Amanecer | Sale de casa (con retraso aleatorio por NPC) y camina al trabajo. |
| Día | En su trabajo. Cada hora, 15-20 % de probabilidad de un descanso social de 1,5-2,5 h de juego (20-30 s). A media mañana algunos van al mercado. |
| Atardecer | Tiempo libre: encadena actividades sociales hasta la noche. |
| Noche | **Todos** vuelven a casa al empezar la noche (se interrumpe lo que estén haciendo). Guardias patrullan [POST-MVP]. |

Estados: `EN_CASA`, `CAMINANDO`, `TRABAJANDO`, `EN_MERCADO`, `PASEANDO`, `SOCIALIZANDO(actividad)`.

#### 4.11.3 Actividades sociales (cosméticas en el MVP)

| Actividad | Duración (h de juego; real a ×1) | Capacidad del punto | Burbuja | Cómo empieza |
|---|---|---|---|---|
| Sentarse en banco | 2,5-5 h (30-60 s) | 2 por banco | reposo | Va a un banco libre |
| Charlar | 1,25-2,5 h (15-30 s) | 3 por punto | bocadillo | 2+ NPC cerca de un punto de charla |
| Pasear el mercado | 50-70 min por puesto (10-15 s), 2-4 puestos | ilimitada | carrito | Recorre puestos |
| Saludar | 15-25 min (3-5 s) | — | mano | Dos NPC se cruzan |
| Observar edificio | 1,5-3 h (20-40 s) | ilimitada | pensativo | Se para delante de un edificio |
| Jugar a los dados | 3-5,5 h (40-70 s) | 2-3 por punto | dados | Punto de dados en la plaza |

- Las duraciones están en tiempo de juego (el sim cuenta minutos); a ×1 un minuto de juego son ~0,2 s, por eso una charla de 2 h dura unos 25 s en pantalla.
- **Personalidad:** Carisma ≥ 7 → más charla y saludos; Empatía ≥ 7 → más bancos y observar; Destreza ≥ 7 → más dados. 12 % de excepciones aleatorias.
- Puntos sociales colocados como marcadores en el mapa (banco, charla, dados) o generados (delante de edificios, puestos del mercado).
- Al acercarse el jugador (< 100 px), el NPC muestra una frase de un banco de frases por actividad, profesión y momento del día (`social_phrases.json`, 10-15 por tipo).
- [POST-MVP] Las interacciones sociales entre NPC modifican relaciones.

#### 4.11.4 Relaciones

- **Relación** general entre dos personajes: -100 (enemigo) a +100 (amigo). Permanente; cambia con acciones (ayudar, sobornar, atacar, comerciar justo).
- **Afinidad** romántica 0-100 (solo cortejo).
- Las relaciones se heredan parcialmente (×0,5) a los hijos.
- [POST-MVP] Favores debidos y pedidos.

#### 4.11.5 Estados emocionales temporales

Reacciones de corta duración, separadas de la relación permanente. Intensidad inicial 100; decae con el tiempo y desaparece a 0. Máximo 2 estados activos por NPC hacia una fuente.

| Estado | Disparador | Duración base [balance] | Precio compra / venta | Efecto social | MVP |
|---|---|---|---|---|---|
| Agradecido | Regalo valioso (> 50 oro), favor | 1,5-2,5 días | -10 % / +10 % | Acepta peticiones, +10 afinidad temporal; empleado +10 % | ✅ |
| Ofendido | Insulto, regalo barato a noble, negociar agresivo | 1-2 días | +15 % / -15 % | Rechaza conversación | ✅ |
| Cabreado | Robo detectado, fraude | 2-3 días | +25 % / -25 % | Denuncia; empleado -20 %; > 80 de intensidad se niega a comerciar | ✅ |
| Asustado | Amenaza con éxito (Arte Marcial) | 1-1,5 días | -20 % / +15 % | Obedece; relación -5 | ✅ |
| Halagado | Cumplido con éxito (Carisma vs Empatía) | 12-24 h | -5 % / +5 % | +5 afinidad temporal | POST |
| Humillado | Derrota pública, insulto ante > 3 NPC | 2,5-3,5 días | Rechaza comerciar | Evita al jugador, venganza | POST |
| Endeudado | Favor pendiente | hasta devolverlo | -15 % / +10 % | No decae | POST |
| Celoso | Cortejar a quien pretende | 1,5-2,5 días | — | Sabotea el cortejo | POST |
| Inspirado | Discurso brillante, fiesta | 1-1,5 días | — | +1 productividad | POST |
| En duelo | Muerte de familiar/amigo | 3-7 días (≈ medio año) | — | Solo acepta condolencias | POST |

- Las duraciones son la mitad que en el primer intento: con D1(b) un estado de 4-6 días habría durado 2-3 estaciones (más de medio año) y 20-30 min reales.
- **Incompatibles** (gana el más reciente): agradecido↔cabreado, halagado↔ofendido, asustado↔inspirado.
- Al activarse cambian la relación permanente (p. ej. insulto -10); al resolverse o expirar, cambio residual (disculpa aceptada +5; ofensa no disculpada -3).
- Se ven como emoji sobre la cabeza, con **prioridad** sobre la burbuja de actividad social, y en la ficha del NPC.
- Acciones del jugador sobre un NPC (panel del NPC): Conversar, Regalar, Halagar, Insultar, Amenazar.
- [POST-MVP] Duración modificada por Empatía/Diplomacia y por la relación; propagación social (humillar a alguien ofende a sus amigos).

### 4.12 Política, reputación y justicia

#### 4.12.1 Reputación

- Valor global por **familia** (0 a ∞) + modificador por clase social (`{artesano, patron, erudito, picaro} → int`).
- **Gana:** comercio justo y salarios pagados (+1/+2), donaciones, eventos grandes (+20/+50), **+1/día por cada negocio operativo con empleados** (talleres y la taberna), ocupar un cargo, fachadas, encargos cumplidos (+2).
- **Pierde:** estafas, salarios impagados (-2), actividad ilegal descubierta, condenas (multa -10, confiscación -30, pérdida de cargo -50), acusación falsa descubierta (-50), despedir a un leal (-2), rumores de empleados descontentos (-1), encargos incumplidos (-5), deuda inicial vencida (-10, ver 4.16).
- [POST-EA] Reputación por zona del mapa.

#### 4.12.2 Títulos sociales

| Título | Oro | Reputación | Requisito extra | Desbloquea |
|---|---|---|---|---|
| Común | — | — | Inicio | 1 edificio, mercado |
| Ciudadano | 100 | 50 | 1 negocio operativo | 2 edificios, votar, cargos menores |
| Patricio | 500 | 200 | ≥ 2 empleados | 4 edificios, cargos medios |
| Barón | 2.000 | 500 | ≥ 3 negocios | 6 edificios, cargos mayores |
| Nobleza | 10.000 | 1.000 | Evento especial completado | Sin límite, todos los cargos |

- **Ceremonia:** el jugador va al Ayuntamiento y solicita el ascenso. Se cobra el oro y se comprueban requisitos. Un NPC con cargo (Alcalde o Concejal) aprueba si su afinidad con el jugador ≥ 30; si el cargo está vacante, se aprueba solo.
- El título se **hereda**.
- Una condena grave baja el título un nivel.

#### 4.12.3 Cargos públicos (6 en EA)

| Cargo | Título mín. | Pasivos | Acciones activas | Salario/día | Mandato (1 año = 8 días) |
|---|---|---|---|---|---|
| Inspector de mercado | Ciudadano | +10 % reputación con artesanos | Regular precio de un objeto ±10 % (temporal), multar a un comerciante | 2 | 1 año |
| Recaudador | Ciudadano | +5 % de lo recaudado | Fijar impuesto 5-15 %, embargar edificio moroso | 3 | 1 año |
| Alguacil | Patricio | Ve denuncias de NPC | Arrestar (inicia juicio), investigar sospechoso | 4 | 2 años |
| Juez | Patricio | +20 % reputación con eruditos | Presidir juicio (elige veredicto), indultar | 5 | 2 años |
| Concejal (×2) | Barón | Vota ordenanzas | Proponer ordenanza, vetar | 6 | 3 años |
| Alcalde | Barón | +reputación global | Legislar, declarar eventos, nombrar títulos | 10 | 4 años |

- Mandatos en años de D1(b): 1 año = 40 min reales, 4 años = 2 h 40. Se mantienen las cifras del diseño original porque ya estaban en años; lo que cambia es su duración real [balance].
- Máximo **1 cargo por personaje**. Los cargos no se heredan.
- **Gobierno procedural al inicio:** se reparten los cargos entre NPC de las familias de la ciudad según título (Barón/Nobleza para Alcalde, Patricio para Juez…). Se dejan 1-2 cargos menores libres para que el jugador entre pronto.
- **Vacantes:** muerte del titular → libre. Fin de mandato → elección al cambiar de año; la campaña ocupa la **última estación** del mandato (invierno). Cargo libre sin más candidatos → el jugador lo gana directamente.
- Los NPC con cargo actúan **pasivamente** (cobran, aplican efectos). Solo compiten cuando el jugador se presenta.
- **Impuestos** (si hay Recaudador): porcentaje sobre las ventas del jugador [propuesta: se cobra al final de cada día sobre ingresos del día].

#### 4.12.4 Elecciones

1. Panel político (organigrama) → elegir cargo → **Presentarse** (requiere título mínimo).
2. **Campaña de 1 estación** (2 días; antes 7, casi un mandato entero con D1(b)). Para presentarse hay que hacerlo antes de que empiece esa estación. Nivel elegido al presentarse: Básica (gratis, +5 %), Media (50 oro, +15 %), Alta (200 oro, +30 %).
3. Acciones durante la campaña:
   - Visitar familia influyente: +afinidad con sus miembros; el personaje queda ocupado 4 h de juego [balance].
   - Sobornar NPC clave (20 oro base): voto asegurado; riesgo de escándalo (check de Sigilo; si falla, -reputación).
   - Discurso público: check de Retórica; éxito = +votos de los NPC presentes.
   - Difamar rival: baja sus votos; riesgo alto.
4. **Votación:** cada NPC con título ≥ Ciudadano vota. Puntuación por candidato: `afinidad × 0,3 + reputación_normalizada × 0,3 + mod_clase × 0,2 + bonus_campaña × 0,2`. Gana la suma mayor; empate → más reputación. Estados emocionales: humillado/cabreado vota en contra, agradecido/asustado a favor.

**Organigrama** (tecla de política / botón HUD): Alcalde arriba, Concejales, Juez, Alguacil, Recaudador, Inspector. Cada nodo: retrato del titular o "VACANTE", nombre y familia, mandato restante, botón Presentarse. Clic → detalle (poderes, salario, historial).

#### 4.12.5 Tribunal

**Quién acusa:** cualquier ciudadano (título ≥ Ciudadano). Los NPC acusan al jugador si descubren ilegalidad (inspección de Secretos, robo visto). El jugador puede acusar con pruebas reales o fabricadas (fabricar: check de Sigilo/Destreza con riesgo).

**Fases:**
1. **Acusación:** cargos formales ante el Juez. Se eligen 3-5 testigos entre NPC relevantes (vecinos, empleados, rivales). Disposición inicial a favor / en contra / neutral según afinidad con acusado y acusador y su honestidad.
2. **Preparación (1 estación, 2 días)** [balance]: el acusado trabaja a los testigos:
   - Convencer (Retórica, check) → pasa a favor.
   - Sobornar (oro según codicia) → a favor seguro, pero riesgo de denuncia (cargo extra).
   - Amenazar (Arte Marcial, check) → éxito: a favor por miedo; fallo: en contra + posible denuncia.
3. **Vista oral:**
   ```
   defensa   = retórica_acusado × 2 + testigos_a_favor × 15 + reputación × 0,1
   acusación = retórica_acusador × 2 + testigos_en_contra × 15 + pruebas × 20
   ```
   Defensa > acusación → inocente (el acusador pierde reputación si era falsa). Si no → culpable.
   Si el jugador es Juez puede manipular el veredicto: -20 Honestidad y riesgo de escándalo.

**Condenas:**

| Gravedad | Condena | Ejemplos |
|---|---|---|
| Leve | Multa 10-50 oro | Fraude menor, pelea |
| Media | Confiscación de edificio o mercancía | Contrabando, evasión fiscal |
| Grave | Pérdida de cargo + título -1 | Corrupción, soborno descubierto |
| Máxima | Destierro 1 año (8 días; el condenado no puede actuar en la ciudad, el resto de la familia sí) [balance] | Crimen violento, traición |

La vista oral debe ser **interactiva** para el jugador (en el primer intento se autorresolvía). **Decisión del owner
(2026-11-02, `docs/decisiones.json`):**
- El acusado puede **interrogar una vez a cada testigo en contra**: SkillCheck de Retórica contra la Empatía del testigo.
  Si sale bien, su testimonio no cuenta; si sale mal, cuenta doble (`data/justice.json` → `cross.ok_weight 0` /
  `fail_weight 2`) [provisional, balance]. Después concluye la defensa (o la vista acaba sola a las 2 h de juego).
- Las **pruebas del acusador se ven como «?»** hasta la vista; la balanza enseña el resto de sumandos.
- La **vista oral pausa el juego** (solo la vista; el sim no cambia: se puede seguir interrogando en pausa).

#### 4.12.5.1 Faltas de las familias IA (Equilibrio 6, 2026-11-06)

Sin ellas, en una partida normal no aparecía nunca un hecho público contra otra familia (jugador completo, 3 años ×
4 semillas: 0) y el jugador que no inventa pruebas no podía acusar jamás. Las familias IA con negocio cometen
**faltas pequeñas**, más cuanto menos honradas son, y a veces alguien las ve:

| Falta | Cargo (H11) | Quién |
|---|---|---|
| Pesos falsos en el mercado | Fraude menor (leve) | Cualquiera |
| Dejar a deber a un proveedor | Fraude menor (leve) | Cualquiera |
| Contrabando | Contrabando (media) | Solo con honestidad ≤ 10 (los perfiles agresivos de Bellcaire) |

- **Cuándo:** al alba, una tirada por familia IA con un negocio (un edificio que no es casa) y el cabeza en la ciudad.
  Probabilidad del día = base × (1 + (pivote − honestidad) / escala), entre 0 y el máximo [balance, provisional]:
  0,06 con honestidad 20 (Ferrer y los artesanos de Vilarrasa), 0,09 con 0.
- **Visto:** con 0,6 la falta se hace **hecho público** contra la familia (su cabeza); si no la ve nadie, no queda nada.
  Al jugador le llega un aviso («A los Ferrer los han visto: pesos falsos en el mercado»), y la ficha de la familia
  lo enseña entre sus hechos. Desde Ciudadano puede acusar con él (4.12.5); si gana, la condena es la del cargo.
- **Lo que no cambia:** la falta no mueve oro (lo que ganó ya está en sus ventas; la multa llega con el juicio), ni la
  honestidad, ni `state.rng` (tiradas con clave, `Kin.roll`): el resto de la partida juega igual y las dianas de los
  bots que no acusan no se mueven. La IA rival solo acusa a familias humanas, así que estos hechos son del jugador.
- Cifras en `data/justice.json` `misdeeds`; código en `sim/ai/misdeeds.gd`.

#### 4.12.6 Intrigas [POST-MVP / EA]

Las intrigas son la base del Pícaro y de los ataques de las familias rivales: el esbozo de combate, robo y guardias está en 4.22 y el uso por la IA rival en 4.21.

Espionaje (observar NPC, descubrir secretos), sabotaje de negocios, chantaje, falsificar pruebas, envenenar, incendiar, sicarios. Acciones nocturnas del Pícaro: robar edificio, espiar rival, contrabando, emboscada, sobornar guardia. Peligros nocturnos: ladrones NPC asaltan si caminas solo de noche fuera de zona segura; ser visto en la zona criminal baja la reputación con la nobleza; guardias patrullan.

### 4.13 Eventos y estaciones [EA]

> El calendario de fiestas, los eventos de la ciudad (visita del marqués, bodas, torneos…) y los sucesos (altercados, bandidos, secuestros) están en [04f_vida_y_fiestas.md](04f_vida_y_fiestas.md) §4.24.5 y §4.25.

| Evento | Efecto | Duración [balance] (1 estación = 2 días) |
|---|---|---|
| Hambruna | Producción agrícola -50 %, alimentos ×2,5, posibles muertes | 2 estaciones |
| Epidemia | Mortalidad +30 %, medicina ×3, negocios cierran, NPC débiles asustados | 1-2 estaciones |
| Guerra regional | Rutas cortadas, armas ×1,5 (era ×2), alimentos ×1,5, lujo baja | 1 año |
| Buena cosecha | Alimentos bajan | 1 estación |
| Fiesta popular | Taberna/posada más demanda, NPC inspirados | 1 día |
| Festividad religiosa | Cambia rutinas y demanda | 1 día |
| Visita de dignatario | Más extranjeros, más ventas | 1-2 días |
| Revuelta | NPC dañan edificios; solución política | variable |
| Crisis política | Caída de gobierno, elecciones extraordinarias | inmediato |
| Descubrimiento | Nueva técnica, un producto queda obsoleto | permanente |

Los eventos son **datos** (disparador, probabilidad por estación, efectos declarativos, duración, texto). El Alcalde puede declarar algunos. Con D1(b) una estación son 2 días: un evento local (fiesta, visita) no puede durar más que la estación en la que cae.

**Implementado en H13 (parte 1)** [provisional, balance]: `data/seasons.json` (grupos de objetos: alimentos, agricultura, textiles, madera, construcción, medicina, armas, lujo; los `mod_estación` de 4.5.3; la producción por estación vale 1 en todas) y `data/events.json` (los 10 eventos). Reglas: una tirada al empezar cada estación para los eventos de estación y una cada día para los locales; como mucho un evento nuevo por tirada, 3 a la vez y 1 local; el azar sale de la semilla por clave. Activos: hambruna, epidemia, guerra, buena cosecha, fiesta, festividad religiosa y visita de dignatario, con los efectos que ya existen (precio, demanda, producción, clientes del mostrador, horas de recado, mortalidad de la tirada anual). Desactivados con su motivo: revuelta (no hay daño de edificios), crisis política (no hay elecciones extraordinarias) y descubrimiento (no hay técnicas ni objetos obsoletos). El Alcalde declara la fiesta y la festividad (poder `declare_event`, enfriamiento 1 año). Las cifras sin número en esta tabla (probabilidades, «alimentos bajan» ×0,7, clientes ×0,7-1,5, demanda ×0,8-1,3, mortalidad ×1,2 en la hambruna) las aceptó el owner el 2026-11-03 tal cual, salvo la guerra (armas ×1,5 en vez de ×2). La producción por estación sigue a 1 hasta que haya cifras.

Los **microeventos** (cliente que regatea, empleado enfermo, ladrón nocturno) son eventos pequeños de un edificio o personaje que llegan antes, en H7: ver 4.20.

### 4.14 Narrativa con IA [POST-EA]

Diálogos de NPC con memoria de interacciones (Claude API), misiones procedurales según la situación de la dinastía, **cronista** que escribe el libro de la partida, eventos contextuales únicos. Voces con ElevenLabs por clase social. La arquitectura debe registrar un **diario de hechos** (`chronicle`) desde el primer día: nacimientos, bodas, muertes, títulos, juicios, elecciones, compras. Ese diario será la entrada del cronista. Desde H8 también es la base de la **puntuación de dinastía** (4.17).

### 4.15 Día y noche (visual)

- Tinte global por fase con transición gradual: amanecer `#FFD4A0`, día `#FFFFFF`, atardecer `#FF9060`, noche `#1A1A40`.
- Antorchas de calle (radio ~80 px) se encienden al empezar el atardecer y se apagan al acabar el amanecer. Ventanas (~48 px) con parpadeo cálido en edificios habitados. Faroles de taberna siempre si está abierta.
- Sombras de edificios estáticas por fase (cortas de día, largas al atardecer, ninguna de noche).
- Estrellas de noche; luciérnagas en hierba al atardecer/noche de verano.
- Reloj del HUD con sol/luna, barra de progreso de la fase y tooltip con hora y estación.

> La sección 4 sigue en [04b_partida_y_rivales.md](04b_partida_y_rivales.md): 4.16 inicio de partida, 4.17 objetivos y final, 4.18 libro de cuentas, 4.19 fuentes y sumideros de oro, 4.20 microeventos, 4.21 IA de familias rivales, 4.22 sistemas de las otras clases, 4.23 dificultad.

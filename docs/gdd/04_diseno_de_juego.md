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
| Recuperación de la demanda | +0,1 por día | — | 4.5.3 |
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

**Capacidad de carga:** `30 kg + (constitucion - 5) × 3 kg` [propuesta; el actual es 30 kg "modificado por Constitución" sin fórmula cerrada].

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

#### 4.2.6 Necesidades [POST-MVP]

Hambre, descanso, social y diversión (0-100). Si se descuidan bajan la **moral** → baja la productividad → riesgo de enfermedad. La IA de familiares las equilibra con su directiva. No entra en el MVP, pero el modelo de datos del personaje debe admitirlas.

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
| Personaje (≥16 años) | Peso | 30 kg (ver 4.2.2) |
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
| `forja_lingote` | horno | hierro ×2 | lingote_hierro ×1 | 1 h | 1 |
| `forja_martillo` | yunque | lingote ×1 + carbón ×1 | martillo ×1 | 2 h | 2 |
| `forja_espada` | yunque | lingote ×2 + carbón ×1 | espada ×1 | 3 h | 4 |
| `forja_armadura` | yunque | lingote ×3 + carbón ×1 | armadura ×1 | 5 h | 6 |
| `forja_acero` | horno | lingote ×2 + carbón ×2 | acero ×1 | 3 h | 6 (**crear**: la desbloquea "Forja de maestro") |

> Las duraciones actuales eran 3-7 segundos reales. Se pasan a horas de juego para que un empleado haga varias piezas por jornada (≈12 h de día) y no cientos. Ajustar en balance.

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
- **Restricción nocturna:** los empleados no trabajan de noche. El jugador sí puede trabajar a mano de noche en Forja/Horno.
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
   - baja 0,1 [balance] por unidad que vende en el mercado cualquier actor (jugador, herrero rival, familias IA), unidad a unidad: vender n de golpe cobra lo mismo que vender n veces 1 (era 0,05; ajustado en H3 con artisan_novice)
   - se recupera +0,1 por día hacia 1,0
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
mod_evento: hambruna alimentos ×2,5 · epidemia medicina ×3,0 · guerra armas ×2,0 y alimentos ×1,5
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
- Los encargos de inicio están guionizados en el escenario de partida nueva (4.16); después salen de una tabla de datos por profesión (`data/contracts/`).
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
- **Mantenimiento diario** por edificio (`upkeep` en la ficha; 2 oro la Forja [balance]) **entra en el MVP** (D12), desde H3: se cobra cada amanecer junto con los salarios, sale en el libro de cuentas y da sentido a no acumular edificios vacíos. Qué pasa si no se puede pagar está pendiente (D15).

#### 4.6.4 Interiores

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
| Aprendiz | 1 oro | 50 % | ×0,5 | Abundante | → Oficial tras **1 año** (8 días) trabajado si lealtad > 50 [balance] |
| Oficial | 3 oro | 100 % | ×1,0 | Media | → Maestro tras **2 años** más (16 días) si lealtad > 70 [balance] |
| Maestro | 6 oro | 150 % | ×1,5 | Escasa (requiere mejora "Taller de maestro") | — |

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
- **Solo una obra a la vez** por edificio; durante la obra el edificio **no produce**.
- Las mejoras son permanentes. Un evento (incendio, sabotaje, revuelta) puede destruir **la última mejora** de una rama; hay que pagarla de nuevo. Seguridad reduce la probabilidad.
- Cada mejora tiene efectos declarativos (`production_speed`, `extra_storage`, `new_zone`, `max_employees`, `quality_bonus`, `price_multiplier`, `customer_bonus`, `loyalty_bonus`, `reputation`, `protection`, `inspection_risk`, `illegal_profit`…) y visuales (nodo interior / overlay exterior que aparece).

**Árbol de la Forja (implementado en el primer intento, conservar):**

| Rama | Nivel 1 | Nivel 2 | Nivel 3 |
|---|---|---|---|
| Producción | Fuelle mejorado — 3 oro, 2 madera, 0,5 d → velocidad ×1,2 | Temple avanzado — 8 oro, 5 lingotes, 1 d → ×1,4 | Forja de maestro — 20 oro, Artesanía 6, 1 d → ×1,6 + receta acero |
| Capacidad | Segundo yunque — 10 oro, 5 lingotes, 3 madera, 1 d → puesto yunque 2 | Almacén ampliado — 8 oro, 8 madera, 1 d → +10 pilas | Tercer horno — 25 oro, 10 lingotes, Artesanía 5, 1,5 d → puesto horno 2 |
| Calidad | Acero templado — 5 oro, 3 carbón, 1 d → calidad +1 | Grabado fino — 12 oro, Artesanía 5, 1 d → +2 | Sello de maestro — 30 oro, Artesanía 7, 1,5 d → +3 y precio ×1,5 |
| Comercio | Mostrador de venta — 6 oro, 4 madera, 1 d → ventas directas | Escaparate exterior — 15 oro, 3 lingotes, 1 d → clientes +30 % | Reputación comercial — 25 oro, requiere Fachada 1, 1 d → clientes +50 %, precio ×1,1 |
| Personal | Dormitorio aprendiz — 8 oro, 6 madera, 1 d → +1 empleado | Comedor — 12 oro, 5 madera, 1,5 d → lealtad +10 | Taller de maestro — 30 oro, requiere Capacidad 2, 1,5 d → +1 empleado, permite maestros |
| Fachada | Fachada de piedra — 15 oro, 10 piedra, 1,5 d → reputación +10 | Jardín y plantas — 20 oro, 5 madera, 1,5 d → +20 | Fachada noble — 40 oro, título Ciudadano, 2 d → +30 |
| Seguridad | Cerradura reforzada — 5 oro, 2 lingotes, 1 d → protección 20 % | Guardia contratado — 15 oro, 1 d → 40 % | Caja fuerte — 30 oro, 8 lingotes, 1 d → 60 % |
| Secretos | Doble contabilidad — 10 oro, 1 d → impuestos -10 %, riesgo inspección +5 % | Pasadizo oculto — 20 oro, 5 madera, Sigilo 3, requiere Seguridad 1, 1 d → escapar de una inspección | Contrabando — 35 oro, Sigilo 5, 1 d → beneficio ilegal ×2, riesgo +15 % |

> Días de obra [balance]: la mitad que en el primer intento, para que con D1(b) (año = 8 días) una obra de nivel 3 no pare la producción casi medio año.
>
> Los costes en oro son muy bajos comparados con los precios de venta (una espada vale 65). **Se rebalancean con bots en H5 (D14)**, previsiblemente ×5-×10, contra las dianas de oro neto por día (4.19).

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
- De noche los familiares pueden tener Trabajar (como el jugador, 4.4.3); los empleados no. Cuando entren las necesidades [POST-MVP], trabajar de noche costará descanso.

#### 4.10.9 Identidad visual de la familia

Hay que reconocer a los tuyos (y a cada familia rival) de un vistazo, sin capas de ropa (sprites monolíticos en el MVP).

- **Variación por paleta:** cada sprite de personaje se genera con unos **colores clave reservados** para pelo, piel, ropa principal y ropa secundaria. Un shader de intercambio de paleta los sustituye al dibujar: 6 tonos de pelo, 4 de piel [balance] y **la ropa principal en el color de la familia** (la ficha de familia guarda `colors: {primary, secondary}`, elegidos al crear la partida para la tuya y fijados en datos para las rivales).
- **Rasgos heredables:** pelo y piel se heredan de uno de los padres al azar (semilla del sim), con una probabilidad baja de tono nuevo [balance]. Los hijos se parecen a sus padres y la familia se reconoce en el árbol genealógico.
- El mismo intercambio se aplica a los **retratos** (HUD, árbol, contratación) y al color del borde del retrato.
- Rasgos de forma (barba, peinado, complementos) necesitan capas: quedan para la customización por capas [POST-MVP].
- Coste de arte: ninguna generación extra; lo que exige es que los sprites respeten los colores clave (8.4, 9.6).

### 4.11 Ciudad viva: NPC

#### 4.11.1 Población

- MVP: 15-20 NPC con rutina. EA: 30-40 NPC y 5 familias rivales.
- Todo NPC es un **personaje completo** (mismo modelo de datos que la familia del jugador): clase, profesión, atributos, edad, casa, trabajo, dinero.
- Las casas de NPC no tienen interior: el NPC desaparece en la puerta y reaparece al salir.

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
- **Gana:** comercio justo y salarios pagados (+1/+2), donaciones, eventos grandes (+20/+50), **+1/día por cada negocio operativo con empleados**, ocupar un cargo, fachadas, encargos cumplidos (+2).
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

La vista oral debe ser **interactiva** para el jugador (en el primer intento se autorresolvía).

#### 4.12.6 Intrigas [POST-MVP / EA]

Las intrigas son la base del Pícaro y de los ataques de las familias rivales: el esbozo de combate, robo y guardias está en 4.22 y el uso por la IA rival en 4.21.

Espionaje (observar NPC, descubrir secretos), sabotaje de negocios, chantaje, falsificar pruebas, envenenar, incendiar, sicarios. Acciones nocturnas del Pícaro: robar edificio, espiar rival, contrabando, emboscada, sobornar guardia. Peligros nocturnos: ladrones NPC asaltan si caminas solo de noche fuera de zona segura; ser visto en la zona criminal baja la reputación con la nobleza; guardias patrullan.

### 4.13 Eventos y estaciones [EA]

| Evento | Efecto | Duración [balance] (1 estación = 2 días) |
|---|---|---|
| Hambruna | Producción agrícola -50 %, alimentos ×2,5, posibles muertes | 2 estaciones |
| Epidemia | Mortalidad +30 %, medicina ×3, negocios cierran, NPC débiles asustados | 1-2 estaciones |
| Guerra regional | Rutas cortadas, armas ×2, alimentos ×1,5, lujo baja | 1 año |
| Buena cosecha | Alimentos bajan | 1 estación |
| Fiesta popular | Taberna/posada más demanda, NPC inspirados | 1 día |
| Festividad religiosa | Cambia rutinas y demanda | 1 día |
| Visita de dignatario | Más extranjeros, más ventas | 1-2 días |
| Revuelta | NPC dañan edificios; solución política | variable |
| Crisis política | Caída de gobierno, elecciones extraordinarias | inmediato |
| Descubrimiento | Nueva técnica, un producto queda obsoleto | permanente |

Los eventos son **datos** (disparador, probabilidad por estación, efectos declarativos, duración, texto). El Alcalde puede declarar algunos. Con D1(b) una estación son 2 días: un evento local (fiesta, visita) no puede durar más que la estación en la que cae.

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

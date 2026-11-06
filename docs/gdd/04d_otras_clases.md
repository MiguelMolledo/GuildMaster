## 4d. Sistemas propios de las otras clases: diseño detallado de 4.22 (Gate «Antes de H12»)

Desarrolla 4.22 ([04b_partida_y_rivales.md](04b_partida_y_rivales.md#422-sistemas-propios-de-las-otras-clases-ea-diseñar-en-detalle-antes-de-h12)).
**Estado: aprobado por el owner el 2026-11-05** con todas sus recomendaciones (O1–O15); borrador del 2026-11-03. Cuando lo apruebe, se apunta en `docs/decisiones.json` y se
marca el [Gate] en `docs/hitos.json`; sin eso no empieza H12 (10_hitos.md).

Las cifras marcadas **[balance]** son valores iniciales: se ajustan con bots contra `data/targets.json`. Donde este
documento cambia o precisa algo de 4.22 (o de otra sección) se dice explícitamente (resumen en 4.22.1). Lo que solo
puede decidir el owner está al final, en 4.22.11.

Dependencias: parte del código de hoy (guardado **v14**, que trae las estaciones y eventos de H13 y el reparto de población (la v15 es del duelo, la v16 de los viajes, la v17 de la ciudad viva, la v18 de las fiestas, la v19 de la posada y la v20 de los desbloqueos y la Forja viva, 2026-11-04), `Loan` de H3, ladrón nocturno de H7, tribunal de H11,
necesidades de H14). **No cambia 04c** (IA rival, esperando al owner) ni las parcelas y la construcción de H6: se diseña
para que encaje con ellas (4.22.6.10 y 4.22.4.1).

---

### 4.22.1 Resumen y qué precisa respecto a 4.22

Las tres clases nuevas añaden **5 piezas comunes** (servicios, clientes con necesidad, salud, vigilancia, forasteros) y
encima de ellas sus sistemas propios: campos, ganado y servicios de comida y cama (Patrón); servicios, banca y
documentos (Erudito); combate, robo, guardias, mercancía robada, rescates, espionaje y contratos de armas (Pícaro).

| # | Qué precisa o cambia | Por qué |
|---|---|---|
| P1 | **El estado del campo vive en el edificio** (`buildings[bld].fields`, por puesto), no en la parcela. Las parcelas rústicas vinculadas de H6 añaden puestos de campo. | H6 no está diseñado ni aprobado; así la Granja funciona con o sin él y no hay dos sitios para lo mismo. |
| P2 | **Tres tipos de receta:** `craft`, `service` (ya reservado) y **`field`** (arar, sembrar, cosechar). | El ciclo del campo no consume y produce en un ciclo: cambia el estado de un puesto. |
| P3 | **Peso de demanda por objeto** (`demand_weight`, por defecto 1). El trigo o el pan bajan la demanda mucho menos por unidad que una espada. | Con 0,04 por unidad, vender 100 de trigo hunde el mercado al mínimo. Los objetos del Artesano siguen en 1: sus dianas no se mueven. |
| P4 | **Los clientes de servicios pagan desde fuera** (como el mostrador de H7): el oro entra en la familia que sirve y no sale de ningún vecino. | Los hogares NPC tienen ~20 de oro y no ganan nada; si pagaran ellos, los servicios morirían en dos días. |
| P5 | **Hechos ocultos:** un delito visto crea un hecho `public: false` con `seen_by`. Es exactamente el `known` de 04c (4.21.4). | 4.22 pedía testigos; H11 solo tenía hechos públicos. |
| P6 | **Mercancía robada = variante de id** (`sword@stolen`), sin tocar la clave de pila de 5.9. | Lo que pedía decidir 4.22; ver O5. |
| P7 | **Sin muertes en combate en H12** (propuesta, O4). | 4.22 lo dejaba por decidir. |
| P8 | **`Loan` crece**: prestamista que puede ser una familia, interés, cuotas, garantía y contrato notarial. La deuda inicial y la multa con plazo siguen igual (interés 0, una cuota). | 5.3 ya reservaba esos campos; hoy no existen. |
| P9 | **Mercenario con edificio propio: Cuartel** (3×3, producción). Bandido en el Nido, Ladrón y Espía en la Guarida. | 4.6.1 solo tiene dos edificios criminales y el mercenario es legal (O9). |
| P10 | **Precio base de la harina 12 → 15** y precios nuevos (tabla de 4.22.8). | Con 12, moler trigo comprado pierde dinero. La harina no la usa hoy nadie. |

---

### 4.22.2 Principios

1. **Mismas órdenes para todos** (5.5): jugador, familiares, bots e IA rival. Validación en el sim con motivo legible.
2. **Contenido como dato.** Cultivos, animales, servicios, delitos, guardias, rutas de patrulla, contratos y préstamos
   viven en `data/`; el código no tiene enums de oficios.
3. **Determinista.** Todo azar sale de `state.rng`; las tiradas se hacen en momentos fijos (amanecer, hora en punto,
   al empezar un delito), nunca por fotograma.
4. **Coste acotado.** Nada nuevo corre cada minuto por cada personaje salvo el movimiento de los guardias; la
   vigilancia solo se calcula cuando ocurre un delito. Diana: `sim_bench` < 2 ms con la ciudad de H12.
5. **Nunca injusto:** todo riesgo se ve antes de correrlo (medidor de visibilidad, guardias dibujados de noche, plazos
   de cosecha, morosidad estimada) y todo castigo llega con aviso.
6. **El oro solo cambia por `Money.change`** con su categoría; la conservación de 4.19 se cumple con las categorías
   nuevas (`theft` como sumidero de quien sufre un robo de oro).

---

### 4.22.3 Piezas comunes

#### 4.22.3.1 Recetas de tres tipos

Todas viven en `data/recipes/<id>.json` y se trabajan con `work_at(actor, bld, zone, recipe, mode)`.

| Campo | `craft` (hoy) | `service` | `field` |
|---|---|---|---|
| `inputs` | sí | opcional (vendas, velas, cerveza) | `sow`: semilla |
| `output` | objeto | — | `harvest`: según cultivo |
| `effect` | — | lista declarativa (4.22.3.2) | — |
| `service_price` | — | precio de referencia | — |
| `duration_hours` | sí | por cliente | por puesto de campo |
| `stat` (nuevo, opcional) | atributo que manda (por defecto `craft`) | ídem | ídem |
| `min_stat` (nuevo; `min_craft` sigue valiendo) | mínimo | mínimo | — |
| `schedule_hours` (nuevo, opcional) | — | horas fijas a las que empieza (misas) | — |
| `action` | — | — | `plow` · `sow` · `harvest` |
| `illegal` (nuevo, opcional) | receta de Secretos: el resultado es un objeto ilegal | — | — |

- `stat` decide la velocidad (como la Artesanía hoy) y, en `craft`, la calidad con la tabla de 4.4.2. Un Alquimista usa
  Arcano; un Escriba, Retórica; un Panadero, Artesanía.
- **Servicio**: el puesto atiende al siguiente cliente que espera en esa zona; con auto-repetición sigue mientras haya
  cola. Sin cliente, el puesto espera (no consume nada). Con `schedule_hours`, la receta empieza solo a esas horas y
  atiende a la vez a todos los que estén dentro (misa).
- El validador acepta los tres tipos y comprueba que `field` va en un puesto de `kind: "field"` y `service` en uno de
  `kind: "service"`.

#### 4.22.3.2 Clientes con necesidad

La misma idea que el mostrador de H7 (`sim/town/counter.gd`), generalizada: los vecinos (y los forasteros, 4.22.3.6)
tienen necesidades de servicio y van a quien las da.

**Demanda** (`data/services.json`) [balance]:

| Servicio | Visitas por adulto y día | Cuándo se tira | Quién da el servicio |
|---|---|---|---|
| `doctor` (consulta) | 0,06 | amanecer | Consulta médica |
| `mass` (misa) | 0,35 por misa | 1 h antes de cada misa | Iglesia |
| `tavern` (comer o beber) | 0,25 | inicio del atardecer | Taberna, Posada |
| `inn` (cama) | solo forasteros | al llegar | Posada |
| `letter` (carta) | 0,04 | amanecer | Scriptorium |
| `loan` (crédito) | 0,7 solicitudes por banco y día | amanecer | Banco (4.22.5.6) |

Las epidemias (H13) multiplican `doctor` ×3 y las fiestas `tavern` ×2 (gancho `mod_evento`; en H12 vale 1). Cada
herido (4.22.3.3) añade una visita al médico; cada empleado enfermo del microevento de 4.20 con la opción (a) también.

**Elección de proveedor.** Cada visita elige entre los edificios que dan el servicio y están abiertos:

```
atractivo(b) = (precio_ref / precio(b)) ^ elasticidad × (1 + min(reputación_familia / 1000 ; 0,3)) × (1 + bonus_comercio(b))
P(b)         = atractivo(b) / (Σ atractivo + atractivo_no_ir)        # atractivo_no_ir = 0,5 [balance]
elasticidad  = 1,5 [balance]   precio(b) ∈ [0,5 ; 2,0] × precio_ref (lo fija el dueño)
```

- Un proveedor NPC (un hogar con taberna en el mapa) entra con precio de referencia y sin bonus.
- **Visita:** el vecino camina al edificio (como el cliente de mostrador), espera en la zona del servicio hasta
  `patience_minutes` 60 [balance], le atiende quien esté en el puesto (familia o empleado con rol `service`), paga y
  se aplica el efecto. Si nadie le atiende, se va: aviso «Clientes sin atender» (como el de H7).
- **Pago:** `Money.change(fam, +precio, "services")`; viene de fuera (P4).
- **Efectos declarativos** de la receta: `heal {severity}`, `need {id, amount}` (necesidades de H14 si el cliente es de
  una familia jugadora), `emotion {id}`, `reputation {amount}`, `class_reputation {class, amount}`, `donation {gold}`.
- Las familias jugadoras también son clientes: sus miembros con hambre o diversión baja (H14) pueden ir a la taberna;
  pagan de su bolsa (`services` como sumidero). Gancho para la directiva de H14, no obligatorio en H12.

#### 4.22.3.3 Salud: heridas y enfermedad

5.3 reservaba el sitio. Cada personaje guarda `health: {wounded_until, sick_until, severity}` (minutos; −1 = sano).

| Estado | Lo causa | Efecto | Dura [balance] | Se acorta con |
|---|---|---|---|---|
| **Herido** | Perder un combate (4.22.6.1) | No trabaja, no da órdenes salvo `move_to` a casa o a la Consulta; −20 en combate | 24 h | Médico: lo que quede ÷ 3. Poción: ÷ 2. |
| **Enfermo** | Microevento «Empleado enfermo» (4.20), epidemias (H13) | No trabaja | 1-2 días (el microevento ya lo decide) | Médico: sana al terminar la visita si pasa la tirada |

- El médico tira `SkillCheck(arcano, severidad)` con severidad 3 (enfermedad), 5 (herida), 7 (herida grave: perdió con
  0 de vida). Éxito: sana o divide. Fallo: −25 % del tiempo restante. El fallo crítico no mata (P7).
- Los vecinos heridos también se curan solos; si hay Consulta, van a ella (visita extra).

#### 4.22.3.4 Peso de demanda por objeto (P3)

`demand_weight` en la ficha del objeto, por defecto 1. La bajada por unidad vendida pasa a `drop_per_unit ×
demand_weight`. Los objetos del Artesano (espada, martillo, armadura, acero) no lo llevan: siguen igual.

| Objeto | `demand_weight` [balance] | Bajada por unidad |
|---|---|---|
| trigo, lana, hierbas | 0,1 | 0,004 |
| harina, carne | 0,2 | 0,008 |
| pan, salchicha, empanada, cerveza | 0,25 | 0,01 |
| cerdo, oveja, ungüento, vendas | 0,5 | 0,02 |
| poción, documento, contrato | 1 | 0,04 |

#### 4.22.3.5 Vigilancia: delitos, testigos y hechos ocultos

Una sola función, `Watch.observe(sim, crime)`, que usan robo, carterista, asalto, secuestro, espionaje y (en H13) el
sabotaje de 04c. Se llama **una vez por delito**, en el minuto en que ocurre.

```
candidatos = personajes despiertos a ≤ vista casillas del sitio (y los que duermen dentro del edificio robado)
vista [balance]  = día 8 · amanecer/atardecer 5 · noche 3 (+3 si el sitio está a ≤ 4 casillas de una antorcha) · guardia +2
cada candidato: SkillCheck(empatía_testigo + 2 si es guardia, sigilo_autor)
                + modificadores: −5 por casilla de distancia · noche sin luz −10 · multitud (≥ 4 vecinos a 3 casillas) +10 al autor
                · dormido −30 · herramienta de ganzúa no cuenta aquí
```

- Quien acierta **ve** el delito y reconoce al autor [provisional: siempre; las máscaras quedan para después].
- Se crea un **hecho** en `justice.facts` (el de H11 con campos nuevos, sin subir versión según su regla):
  `{kind, family (la del autor), actor, charge, day, public: false, seen_by: [chr], victim_family, value, tried}`.
- **Si lo ve un guardia:** grita y empieza la detención (4.22.6.3).
- **Si lo ve un vecino:** al amanecer lo denuncia con probabilidad según su relación con el autor: < 0 → 0,9 · < 30 →
  0,5 · ≥ 30 → 0,1 [balance]. Denunciado = `public: true`, aviso urgente a la familia del autor («Te han denunciado
  por robo») y el Alguacil (o la ciudad) puede detener (`use_office_power arrest {fact}` de H11).
- **Si lo ve un miembro o empleado de una familia:** el hecho le sirve a esa familia para acusar aunque no sea público
  (`accuse` con `fact` acepta hechos ocultos si la familia del acusador está en `seen_by` o es la víctima). Para la IA
  rival, estos hechos son su `known` de 04c (4.21.4: «delitos ajenos: solo si los vio un miembro o empleado suyo»).
- Evento `crime_detected {fact, culprit_family, victim_family, by}` (lo escucha la rivalidad de 04c: «B roba a A,
  detectado, +30»).
- Si nadie lo ve: solo queda un aviso a la víctima («Te han robado 3 espadas esta noche»), sin culpable.

#### 4.22.3.6 Forasteros

Viajeros que llegan por el camino. Son los clientes de la Posada y las víctimas del Bandido.

- `data/town.json` → `visitors`: 3 por día [balance], llegan a horas sorteadas de amanecer a atardecer por una de las
  puertas del mapa (`spawns`, hoy `gate_west` y `gate_east`), caminan a la plaza o a la Posada, se quedan 1-2 noches
  (si hay Posada libre; si no, se van al atardecer) y salen por otra puerta.
- Son personajes temporales de la familia `fam_visitors` (no juega, sin profesión): `{martial 2-6, constitution 3-6,
  empathy 3-6, purse 15-40, rich: 20 %, escort: 30 %}` [balance]. Los ricos llevan 60-120 y pueden ser rehenes.
- Los que llevan escolta van en pareja con un escolta NPC (Arte Marcial 6, espada).
- Un forastero robado en el camino llega a la ciudad igual y denuncia si vio al autor (4.22.3.5).
- Se borran al salir del mapa; `state.town.visitors` guarda solo los vivos (como mucho 12).

#### 4.22.3.7 Guardado (v21)

Una sola migración para todo H12 [la versión real será la siguiente libre cuando se implemente].

| Dónde | Campo nuevo | Migración desde v20 |
|---|---|---|
| Personaje | `health: {wounded_until: -1, sick_until: -1, severity: 0}` | sano |
| Edificio | `fields: {zone → field}` (4.22.4.1) | `{}` |
| Edificio | `pen: {fleece: {}, unfed_days: 0, breed: 0}` (4.22.4.2) | `{}` |
| Edificio | `services: {service_id → precio}` (precio fijado por el dueño) | `{}` |
| Edificio | `hostages: [chr]` (Nido) | `[]` |
| Familia | `underworld: 0` (fama en los bajos fondos, 4.22.6.4) · `intel: []` (lo que han visto sus espías) | 0 · `[]` |
| Préstamo | `lender_family`, `kind`, `interest`, `installments`, `collateral`, `notarized` (4.22.5.6) | `""`, `start` o `fine` según `lender`, 0, `[]`, `{kind: "building", id: building}`, `false` |
| Raíz `town` | `visitors: []`, `guards: {chr → {patrol, step, chasing}}`, `bank: {applications: []}`, `fence: {day, sold}` | vacíos |
| Raíz `justice.facts` | `public`, `seen_by`, `victim_family`, `value` (sin subir versión, regla de H11) | `public: true` (los de H11 ya lo eran), `[]`, `""`, 0 |
| Inventarios | ids `<item>@stolen` (4.22.6.4) | ninguno |

Prueba de ida y vuelta con un guardado v20 de `tests/data/saves/` y con un escenario de cada clase.

#### 4.22.3.8 Órdenes nuevas

Las tres reservadas en 5.5 (`Attack`, `Rob`, `GrantLoan`) más las que hacen falta. En el código, `type` en snake_case.

| Orden | Campos | Quién | Regla principal (motivo si falla) |
|---|---|---|---|
| `set_service_price` | owner, bld, service, price | gestión | Dueño; precio en [0,5; 2,0] × referencia (`not_owner`, `bad_price`) |
| `attack` | actor, target, intent: `fight` \| `rob` \| `hostage`, stance | en persona | Al alcance (2 casillas), ninguno herido ni en combate (`too_far`, `wounded`, `busy`) |
| `rob` | actor, target: bld \| chr | en persona | Edificio: de noche, en su puerta, no propio. Persona: de día o atardecer, al alcance (`not_night`, `own_building`, `too_far`, `robbed_recently`) |
| `spy` | actor, target_bld, hours (2) | en persona | A ≤ 2 casillas del edificio ajeno; ocupa al actor esas horas (`too_far`, `own_building`) |
| `arrest_response` | actor, choice: `surrender` \| `flee` \| `fight` \| `bribe` | en persona | Solo con una detención abierta sobre él (`no_arrest`) |
| `blackmail` | actor, family, fact | gestión | Hecho oculto, de esa familia, visto por la tuya, sin juzgar (`fact_not_usable`) |
| `answer_blackmail` | actor, blackmail, pay: bool | gestión | La familia chantajeada |
| `release_hostage` | actor, bld, hostage | en persona | En el Nido; suelta sin rescate |
| `grant_loan` | actor, application \| terms | gestión (en el Banco) | Banquero dueño del Banco; oro ≥ principal; interés ≤ el máximo de la solicitud (`not_enough_gold`, `too_expensive`) |
| `reject_application` | actor, application | gestión | — |
| `request_loan` | actor, lender, amount, term_days | gestión | Prestamista de la ciudad o un Banco; tope por patrimonio; sin préstamo en impago (`over_limit`, `in_default`) |
| `claim_collateral` | actor, loan | gestión | Préstamo propio en impago ≥ 1 día (`not_defaulted`) |
| `repay_loan` (H3) | actor, loan, amount | gestión | Igual; paga primero la cuota vencida |

Comprar animales, vender al perista y aceptar contratos de armas **no son órdenes nuevas**: son `buy`, `sell` (en el
puesto `livestock` o `fence`) y `accept_contract`/`deliver_contract` con contratos de `kind` nuevo (4.22.6.8).

#### 4.22.3.9 Ficheros de `data/` nuevos

| Fichero | Qué |
|---|---|
| `data/crops/<id>.json` | Cultivo: semilla, crecimiento por estación, rendimiento, días hasta pudrirse |
| `data/animals/<id>.json` | Animal: pienso por estación, producción diaria, cría |
| `data/services.json` | Demanda por servicio, elasticidad, paciencia |
| `data/crime.json` | Vista, modificadores, denuncia, combate, robo, perista, detención, chantaje, rehenes |
| `data/bank.json` | Solicitudes, riesgos, intereses máximos, impago, recuperación de garantías, prestamista de la ciudad |
| `data/town.json` → `visitors`, `guards` | Forasteros y guardias |
| `data/maps/<mapa>.json` → `patrols`, `torches`, `roads`, `npc_providers` | Rutas de patrulla, antorchas (luz), tramos de camino, servicios NPC |
| `data/buildings/`, `data/recipes/`, `data/items/`, `data/upgrades/<árbol>/`, `data/contracts/<oficio>.json`, `data/starts/<clase>_<oficio>.json`, `data/objectives/` | Contenido de cada oficio (4.22.4-4.22.6) |
| `data/justice.json` → `charges` | Cargos nuevos (4.22.6.9) |

---

### 4.22.4 Patrón: campos, ganado, pan, carne, comida y cama

| Profesión | Edificio | Parcela | Cadena | Fuente principal |
|---|---|---|---|---|
| Granjero | Granja | rústica | PAN, TEXTIL, CARNE | Cosecha (estacional), lana y cerdos (diario) |
| Molinero | Molino | producción | PAN | Harina |
| Panadero | Panadería | producción | PAN | Pan y empanadas, mostrador |
| Carnicero | Carnicería | producción | CARNE | Carne y salchichas, mostrador |
| Posadero | Taberna y Posada | producción | SERVICIOS | Comida, bebida y cama (también de noche) |

#### 4.22.4.1 Campos y cultivos

**Puesto de campo** (`kind: "field"`): un rectángulo de la huella de la Granja (o del Herbolario) que se trabaja por
fuera. La Granja base tiene **4 campos** (`field_a`…`field_d`) [balance]. Cada parcela rústica vinculada (H6) añade 2.

**Estado de un campo** (`buildings[bld].fields[zone]`):

```
{state: fallow | plowed | growing | ready | rotten, crop: "", growth: 0.0, ready_day: -1, yield_mult: 1.0}

fallow  --arar (plow)-->  plowed  --sembrar (sow, consume semilla)-->  growing
growing --(cada amanecer: growth += crecimiento[estación])-->  ready  (cuando growth ≥ grow)
ready   --cosechar (harvest: produce)-->  fallow
ready   --(pasan rot_days sin cosechar)-->  rotten  --arar-->  plowed   (arar un podrido lo limpia)
```

**Cultivos** (`data/crops/`) [balance]:

| Cultivo | Semilla | Se siembra en | Crecimiento por estación (prim / ver / oto / inv) | `grow` | Rinde | `rot_days` |
|---|---|---|---|---|---|---|
| `wheat` | trigo ×5 | primavera, verano | 1 / 1 / 1 / 0 | 4 | trigo ×30 | 2 |
| `herbs` (Herbolario) | hierbas ×2 | primavera, verano, otoño | 1 / 1 / 1 / 0 | 2 | hierbas ×12 | 2 |

Cuentas con D1(b): trigo sembrado el día 1 (primavera) está listo al amanecer del día 5 (otoño) y se pudre al del
día 7 (invierno). Sembrado el día 3 (verano) no crece en invierno y está listo el día 9: un trigo «de invierno». En la
práctica, **una cosecha de trigo por campo y año**; las hierbas, hasta tres.

**Trabajo** (recetas `field`, puesto de campo, con las reglas de 4.4.3: una persona, interrumpir devuelve la semilla):

| Receta | Acción | Duración [balance] | Requisito |
|---|---|---|---|
| `farm_plow` | arar | 2 h | campo `fallow` o `rotten`; azadón equipado: ×1,25 de velocidad (como la herramienta de 4.3.4) |
| `farm_sow_wheat` | sembrar | 1 h | campo `plowed`, estación de siembra, semilla en el almacén |
| `farm_harvest` | cosechar | 3 h | campo `ready`; si no cabe en el almacén, el puesto se bloquea y avisa |

- Velocidad: `duración / (1 + (constitución − 5) × 0,05)` del que trabaja (el campo cansa) [balance].
- **Rendimiento:** `rinde × yield_mult × mod_evento` (hambruna ×0,5, buena cosecha ×1,5; en H13), redondeado. Cosechar
  el segundo día de `ready` rinde −25 % [balance]. Los cultivos no tienen calidad (normal).
- De noche los empleados no trabajan el campo (4.4.3); la familia sí, a mano.
- **Avisos:** «El trigo de la Granja está listo: 2 días para cosecharlo» (urgente el último día); «Se acaba la
  primavera: 2 campos sin sembrar»; «Se ha podrido el trigo del campo C».

#### 4.22.4.2 Ganado

**Los animales son objetos en el almacén** de un edificio con puesto `pen` (corral). Nada de rebaños aparte: se
compran, se venden y se llevan como cualquier objeto (pesan, caben en pilas), y el corral cuenta los que hay.

| Animal | Precio base | Peso | Come (prim/ver/oto · inv) | Produce cada amanecer | Cría |
|---|---|---|---|---|---|
| `sheep` (oveja) | 40 | 25 | 0 (pasta) · trigo ×1 | lana ×1 | no |
| `pig` (cerdo) | 24 | 20 | 0 (pasta) · trigo ×1 | — | +1 por cada pareja cada 2 días, hasta llenar el corral |

[balance] Capacidad del corral: 8 animales; +4 por mejora de Capacidad.

- **Cada amanecer** (`Herds.step`, por edificio con `pen`, en orden de id): si toca comer y hay trigo en el almacén,
  lo come; si no, `unfed_days += 1` y ese día no produce ni cría. Con `unfed_days ≥ 2` muere un animal (el de menos
  valor) y aviso urgente. Comer pone `unfed_days = 0`.
- Lo producido entra en el almacén; si no cabe, se pierde y avisa.
- Se compran en el puesto exterior **`livestock`** (feria de ganado, en la plaza o junto a la puerta) con `buy` y
  `deliver_to` = la Granja (llegan andando: recado sin sobrecoste [balance]). Se venden en el mismo puesto.
- La Carnicería los recibe como entrada (`pig ×1`). Llevarlos a mano pesa (2-3 por viaje) o se usa el recado.

#### 4.22.4.3 Molino y Panadería (cadena PAN)

| Receta | Edificio · puesto | Entradas | Salida | Duración | Atributo mín. |
|---|---|---|---|---|---|
| `mill_flour` | Molino · muela | trigo ×2 | harina ×1 | 1,0 h | Artesanía 1 |
| `bakery_bread` | Panadería · horno | harina ×1 + madera ×1 | pan ×5 | 2,5 h | Artesanía 1 |
| `bakery_pie` | Panadería · horno | harina ×1 + carne ×2 | empanada ×3 | 3,0 h | Artesanía 4 |

- La Panadería tiene mostrador (`counter`): el pan se vende bien a vecinos de paso [la regla de D16 aplica igual].
- **Turno del alba** [balance]: en Panadería y Molino los empleados pueden empezar en el AMANECER (05-07) en vez del
  DÍA. Flag `dawn_shift: true` en la ficha del edificio.

#### 4.22.4.4 Carnicería (cadena CARNE)

| Receta | Puesto | Entradas | Salida | Duración | Atributo mín. |
|---|---|---|---|---|---|
| `butcher_cut` | tajo | cerdo ×1 | carne ×6 | 2,0 h | Artesanía 1 |
| `butcher_sausage` | ahumadero | carne ×3 + hierbas ×1 | salchicha ×2 | 3,0 h | Artesanía 3 |

#### 4.22.4.5 Taberna y Posada (servicios de comida y cama)

> **Adelantada** (2026-11-04) para cualquier familia y ampliada con ideas de Wartales en [04f_vida_y_fiestas.md](04f_vida_y_fiestas.md) §4.27. También se adelantan los forasteros (4.22.3.6, en 4.24.3), los guardias (4.22.6.2, en 4.24.4) y la demanda de servicios (4.22.3.2, lo que pide la taberna).

**Taberna** (4×4; la Taberna-Posada adelantada en 04f es un solo edificio de 3×4, como su arte): puestos `bar` (servicio), `kitchen` (craft), mesas (capacidad 8 clientes a la vez), almacén.
**Posada** (4×5): `reception` (servicio de cama), `bar`, `kitchen`, habitaciones (4 camas; +2 por mejora), almacén.
Las dos abren **del atardecer a las 02:00** (y la Posada recibe forasteros todo el día). Sus empleados **sí trabajan
de noche** (`night_production: "employees"`): son la excepción de 4.1.

| Receta | Tipo | Puesto | Entradas | Resultado | Duración | Precio ref. |
|---|---|---|---|---|---|---|
| `tavern_brew` | craft | cocina | trigo ×3 + madera ×1 | cerveza ×8 | 3,0 h | — |
| `tavern_drink` | service | barra | cerveza ×1 | `need fun +15` al cliente de familia | 10 min | 6 |
| `tavern_meal` | service | barra | pan ×1 + carne ×1 (o empanada ×1) | `need hunger +40` | 20 min | 18 |
| `inn_bed` | service | recepción | — | el forastero duerme (ocupa cama hasta el amanecer) | 10 min | 12 |

- Cada cliente de taberna pide bebida (60 %) o comida (40 %) [balance]; si falta lo que pide, se va sin pagar.
- La cama se cobra al llegar; un forastero sin cama libre se va de la ciudad (aviso «Posada llena»).
- La calidad de lo consumido sube el precio que acepta el cliente: buena ×1,15, excelente ×1,3 sobre el precio fijado.

#### 4.22.4.6 Inicio del Patrón: Granjero

Si se aprueba O2, el Patrón empieza como Granjero (`data/starts/patron_farmer.json`, Normal) [balance]:

| Elemento | Valor |
|---|---|
| Protagonista | 20 años, Común, reputación 0 |
| Oro | 30 |
| Edificio | Granja con vivienda, 4 campos **arados** (`plowed`), corral |
| Almacén | trigo ×40 (semilla para 4 campos + pienso de invierno), ovejas ×4, cerdos ×2 |
| Inventario | azadón equipado |
| Deuda | 200, 1 año, sin interés (la de 4.16, por dificultad) |
| Competencia | Ninguna granja rival en H12; el mercado tiene stock infinito de trigo (como hoy de hierro) |

Objetivos: (1) siembra los 4 campos antes de que acabe la primavera; (2) vende lana; (3) cumple el encargo del
molinero: trigo ×20 en 2 días; (4) compra dos ovejas; (5) cosecha antes de que se pudra; (6) devuelve la deuda.

#### 4.22.4.7 Un día normal

| Profesión | Amanecer | Día | Atardecer / noche |
|---|---|---|---|
| Granjero (primavera) | Lana al almacén | Arar y sembrar; llevar lana al mercado | Sembrar a mano lo que falte |
| Granjero (verano) | Lana; los cerdos crían | Vender cerdos, encargos de trigo; contratar para la cosecha | — |
| Granjero (otoño) | Aviso «listo» | **Cosechar** (12 h para 4 campos), vender o llevar al Molino | Cosechar a mano de noche si no llega |
| Granjero (invierno) | Los animales comen trigo | Vender lo guardado, comprar animales, mejoras | Planificar la siembra |
| Molinero | Empleado al alba | Comprar trigo (o recibirlo de la Granja), moler, vender harina o enviarla a la Panadería | — |
| Panadero | Turno del alba: hornear | Mostrador, vender pan, encargos | — |
| Carnicero | — | Comprar cerdos, despiezar, ahumar, mostrador | — |
| Posadero | Forasteros que se van; aprovisionar | Cerveza y comida en la cocina; recibir forasteros | **Barra llena**; empleados de noche |

#### 4.22.4.8 Interfaz

| Qué | Dónde | Estado |
|---|---|---|
| Interior y menú de puesto de cada edificio | [forja_interior.md](../ui/mecanicas/forja_interior.md) (vale para todos) | existe |
| Cola de producción | [produccion.md](../ui/mecanicas/produccion.md) | existe |
| Almacén, comprar y vender, recado | [almacen_y_personaje.md](../ui/mecanicas/almacen_y_personaje.md), [mercado_y_libro.md](../ui/mecanicas/mercado_y_libro.md) | existe; añadir el puesto `livestock` |
| **Campos en el mapa**: cada campo dibuja su estado (tierra, surcos, brotes, trigo maduro, podrido) con barra de crecimiento y días hasta listo / hasta pudrirse; clic derecho = Arar / Sembrar / Cosechar | `docs/ui/mecanicas/campos_y_ganado.md` | **falta** |
| **Calendario de siembra**: franja de 8 días con la estación, qué se puede sembrar y cuándo estará listo | el mismo | **falta** |
| **Corral**: animales, pienso que queda para el invierno (días), crías que vienen | el mismo | **falta** |
| **Servicios**: precio con − / +, cola de clientes, ingresos del día por servicio, camas ocupadas | `docs/ui/mecanicas/servicios.md` | **falta** |

#### 4.22.4.9 Bots y dianas

| Bot | Desde | Qué hace | Diana (Normal, 30 semillas) [balance] |
|---|---|---|---|
| `farmer` | partida nueva `patron_farmer` | Siembra en primavera, vende lana y cerdos, cosecha, guarda pienso de invierno, paga la deuda | Oro neto/día días 1-8 en [+25, +60]; deuda pagada antes del día 8 en ≥ 90 %; ningún animal muerto de hambre en ≥ 90 % |
| `miller` | escenario `mill_open` (Molino, 150 oro, sin deuda) | Compra trigo, muele, vende | Oro neto/día días 1-16 en [+20, +80] |
| `baker` | escenario `bakery_open` | Compra harina, hornea, mostrador | ídem |
| `butcher` | escenario `butchery_open` | Compra cerdos, despieza, ahúma, vende | ídem |
| `innkeeper` | escenario `tavern_open` (Taberna + Posada) | Elabora cerveza, compra pan y carne, ajusta precios, contrata para la noche | ídem; ocupación media de camas ≥ 50 % |
| `patron_chain` | escenario `bread_chain` (Granja + Molino + Panadería) | Cadena completa | Gana más que `farmer` + `miller` + `baker` por separado con las mismas semillas |

#### 4.22.4.10 Riesgos

| Riesgo | Qué pasa | Mitigación |
|---|---|---|
| La deuda vence antes de la primera cosecha en un año malo | Ruina del Granjero | Lana y cerdos dan caja diaria; campos arados al empezar; objetivo 1 avisa; la diana lo mide |
| El jugador no siembra en primavera | Un año sin trigo | Aviso de fin de primavera; siembra de verano posible (trigo de invierno) |
| Inundar el mercado de trigo | Precio hundido | `demand_weight` 0,1; encargos del molinero; vender en dos días |
| Los animales mueren en invierno sin aviso claro | Frustración | Días de pienso en el corral; aviso con 1 día de margen |
| Taberna abierta de noche + empleados de noche | Choca con 4.4.3 | Excepción explícita por flag del edificio |

---

### 4.22.5 Erudito: servicios, médico, sacerdote, alquimista, escriba y banquero

| Profesión | Edificio | Cadena | Fuente principal |
|---|---|---|---|
| Médico | Consulta médica (3×3) | SERVICIOS | Visitas; vendas |
| Sacerdote | Iglesia (4×6, comprable) | SERVICIOS | Donativos de las misas, sacramentos; reputación |
| Alquimista | Botica (3×3) [+ Herbolario] | ALQUIMIA | Ungüentos, pociones; venenos (ilegal) |
| Escriba | Scriptorium (3×4) | SERVICIOS | Encargos de copias, cartas, contratos notariales; documentos falsos (ilegal) |
| Banquero | Banco (4×5; título mínimo Ciudadano para tenerlo) | SERVICIOS | Intereses |

#### 4.22.5.1 Médico

| Receta | Tipo | Puesto | Entradas | Efecto / salida | Duración | Precio ref. | Atributo |
|---|---|---|---|---|---|---|---|
| `doctor_visit` | service | camilla | vendas ×1 | `heal` severidad 3-5 | 1,0 h | 20 | Arcano |
| `doctor_surgery` | service | camilla | vendas ×1 + ungüento ×1 | `heal` severidad 7 | 2,0 h | 35 | Arcano 4 |
| `doctor_bandages` | craft | mortero | tela ×1 | vendas ×3 | 1,0 h | — | Arcano 1 |

- Pacientes: la demanda `doctor` (≈ 1 al día en una ciudad de 18 adultos), los heridos de los combates y los empleados
  enfermos del microevento de 4.20, cuya opción (a) «Pagar al médico 10 oro» **paga a la Consulta** si existe (sin
  Consulta, como hoy).
- Tablón: `data/contracts/physician.json` (botiquín para la guardia: vendas ×6; ungüentos para la Posada).

**Inicio del Erudito: Médico** (si se aprueba O2; `data/starts/scholar_physician.json`, Normal) [balance]: 20 años,
Común, 30 de oro, Consulta médica con vivienda, almacén con vendas ×6 y tela ×4, deuda de 200 a 1 año (4.16).
Objetivos: (1) atiende a tu primer paciente; (2) haz vendas; (3) cambia el precio de la consulta y mira a cuántos
atiendes; (4) cumple un encargo del tablón; (5) cura a un herido grave (pide ungüento); (6) devuelve la deuda.

**Hecho en H12.2 (2026-11-06)** y lo que precisa del borrador (`docs/decisiones.json`):

- **Pacientes en dos capas** [balance]: `doctor` = 0,06 × adultos del pueblo **+ 1,25 al día de la comarca** × fama
  de la Consulta (la clientela de comarca de 4.6.5.7), × su parte de la elección de proveedor. Con solo el pueblo
  (≈ 1 al día) el médico no llega a la banda. Registros, no personajes (`sim/town/services.gd`); esperan en la sala
  de espera hasta 120 min.
- **Gravedad** 3 / 5 / 7 (55 / 37 / 8 %): la consulta trata hasta 5; un grave (7) solo con `doctor_surgery` (pide
  ungüento), que cobra 1,75 × la consulta. El ungüento se compra al **Boticario**, un puesto exterior nuevo en la plaza
  de `town_e` (4.5.1), que también compra las vendas.
- **Encargos de vendas** 2-5 con prima 0,25 (no 0,4: las vendas salen a 3 por tela).
- **`Loan` ampliado y prestamista** (O12 a): hecho, sin versión de guardado (campos leídos con valores por defecto).
  Una cuota sin pagar en su día = el impago de 4.16 (prórroga y luego embargo). El Banco queda para el siguiente bloque.
- Medido (30 semillas, Normal): **51,4 netos/día**, deuda 30/30; Fácil 55,5 > Normal 51,4 > Difícil 47,9.

#### 4.22.5.2 Sacerdote

| Receta | Tipo | Puesto | Entradas | Efecto | Horas | Atributo |
|---|---|---|---|---|---|---|
| `church_mass` | service, `schedule_hours` [7, 12, 19] | altar | vela ×2 | a cada asistente: donativo, `emotion inspired`; a la familia: reputación | 1,0 h | Retórica |
| `church_blessing` | service | altar | vela ×1 | a una familia jugadora que lo pide: `emotion inspired` a sus miembros presentes | 0,5 h | — |

- **Asistentes** por misa: vecinos libres × 0,35 × `(1 + (retórica − 5) × 0,1)` [balance], hasta los bancos (12;
  +6 por mejora). Donativo: 3 oro cada uno [balance] (`services`, viene de fuera, P4).
- **Reputación:** +1 a la familia por misa con ≥ 5 asistentes; +1 de reputación de clase con Eruditos [balance].
- **Sacramentos** [balance]: cada nacimiento, boda o muerte de la ciudad (crónica de H8) paga a la Iglesia 5 / 20 / 10.
  Si hay varias, a la de más reputación.
- **Inspirado** (4.11.5, hoy POST-MVP) se activa en H12 (ver O11): 1-1,5 días, `employee_mult` 1,1 (un empleado
  inspirado trabaja un 10 % mejor) y +1 a las tiradas de discurso.
- Si no hay sacerdote, la misa no se celebra (la Iglesia del mapa es un edificio sin dueño hasta que alguien la compre
  en H6).

#### 4.22.5.3 Alquimista (cadena ALQUIMIA)

Herbolario (campos de hierbas, 4.22.4.1) → Botica (alambique y mesa) → pociones, ungüentos y venenos.

| Receta | Puesto | Entradas | Salida | Duración | Arcano mín. |
|---|---|---|---|---|---|
| `apothecary_extract` | alambique | hierbas ×3 | extracto ×1 | 1,5 h | 1 |
| `apothecary_salve` | mesa | extracto ×1 | ungüento ×2 | 1,0 h | 2 |
| `apothecary_potion` | mesa | extracto ×2 + cerveza ×1 | poción ×1 | 3,0 h | 4 |
| `apothecary_poison` | mesa (Secretos 1) | extracto ×2 + hierbas ×2 | veneno ×1 (**ilegal**) | 3,0 h | 6 |

- **Poción:** al usarla (`equip` en el accesorio y se gasta, o al curarse) divide el tiempo de herida restante entre 2.
- **Veneno:** objeto ilegal; no se vende en el mercado (solo al perista, 4.22.6.4). Equipado como accesorio, el
  próximo combate da +15 al umbral y +1 de daño y se gasta. Llevarlo encima al ser detenido = cargo `poison` (media).
- La Botica tiene mostrador; la tienda pública del Boticario (4.5.1) ya compra hierbas, vendas y pociones.

#### 4.22.5.4 Escriba

| Receta | Tipo | Puesto | Entradas | Salida / efecto | Duración | Precio ref. | Atributo |
|---|---|---|---|---|---|---|---|
| `scribe_document` | craft | escritorio | pergamino ×1 | documento ×1 | 1,5 h | — | Retórica 1 |
| `scribe_contract` | craft | escritorio | pergamino ×2 | contrato ×1 | 2,0 h | — | Retórica 3 |
| `scribe_letter` | service | escritorio | pergamino ×1 | — | 0,5 h | 6 | — |
| `scribe_forgery` | craft (Secretos 2) | escritorio | pergamino ×1 + documento ×1 | documento falso ×1 (**ilegal**) | 3,0 h | — | Retórica 5 |

- **Encargos** (`data/contracts/scribe.json`): el Ayuntamiento, el Tribunal y las familias piden copias (documento
  ×3-6, 1-2 días). Con la prima +40 % de 4.5.6 es su fuente principal [balance].
- **Contrato notarial:** el Banco gasta un `contract` por préstamo notarial (4.22.5.6). Cadena Escriba → Banco.
- **Documento falso** (ver O10): al acusar con pruebas fabricadas (H11, `accuse` con `fabricate`), gastar uno suma
  +20 al umbral de la tirada de Sigilo. No toca la fórmula de la vista.

#### 4.22.5.5 Un día normal

| Profesión | Mañana | Tarde | Noche |
|---|---|---|---|
| Médico | Pacientes del alba; hacer vendas | Visitas; encargos del tablón; curar a los heridos | Curar a mano si hay herido grave |
| Sacerdote | Misa de las 7 | Misa de las 12; bendiciones; comprar velas | Misa de las 19; relaciones (votos) |
| Alquimista | Destilar extracto | Ungüentos y pociones; Boticario | Venenos a escondidas |
| Escriba | Copias de encargos | Cartas a vecinos, contratos para el Banco | Falsificaciones |
| Banquero | Mirar solicitudes del alba y aceptar o rechazar | Cobrar morosos; ejecutar garantías; prestar a familias | — |

#### 4.22.5.6 Banquero y préstamos

**`Loan` ampliado** (P8). La deuda inicial (4.16) y la multa con plazo (H11) siguen siendo un `Loan` con interés 0 y
una cuota: todas sus reglas de hoy (avisos, prórroga +25 %, embargo, ruina) no cambian.

```
Loan {
  id, family (deudor; se mantiene el nombre de hoy), lender ("moneylender" | "town" | id de familia), lender_family ("" o fam_id),
  kind: start | fine | bank | moneylender,
  principal, interest (tasa total del plazo, 0-1), outstanding (= principal × (1 + interest) al concederse),
  installments: [{due_minute, amount, paid}],   # [] = una sola al vencimiento, como en H3
  due_minute (la última), collateral: {kind: building | goods | none, id}, notarized: bool,
  state: active | extended | paid | seized | defaulted | written_off,
  building, overdue_reputation, extension_seasons, extension_surcharge, warned
}
```

**Solicitudes** (`state.town.bank.applications`, `data/bank.json`) [balance]:

- Cada amanecer, por cada Banco con dueño, 0,7 de probabilidad de una solicitud de un hogar NPC:
  `{id, borrower_family, borrower, amount: 50-300, term_days: 4-16, risk, max_interest, expires (2 días)}`.
- Riesgo y lo que acepta pagar (interés anual; se prorratea al plazo con año = 8 días):

| Riesgo | Frecuencia | Interés máximo anual | Impago por cuota | Se ve como |
|---|---|---|---|---|
| A | 50 % | 15 % | 2 % | «Buena solvencia» |
| B | 35 % | 25 % | 6 % | «Regular» |
| C | 15 % | 40 % | 15 % | «Mala» |

- `grant_loan` con un interés ≤ el máximo: el oro sale del Banquero (`loans`, −principal), la solicitud se convierte en
  `Loan` con cuotas iguales cada 2 días (una por estación) [balance]. Si el Banquero tiene un `contract` en el almacén
  del Banco, se gasta y el préstamo es **notarial**.
- **Cobro:** a cada vencimiento el deudor NPC paga la cuota (viene de fuera, `loans` +) salvo que salga la tirada de
  impago → `defaulted`, aviso «Los Soler no han pagado su cuota».
- **Impago de un NPC:** el Banquero puede `claim_collateral` tras 1 día: la ciudad le devuelve el 60 % de lo pendiente
  si era notarial y el 30 % si no [balance], en 1 día y sin juicio (procedimiento ejecutivo). O esperar: cada día sin
  reclamar, 20 % de que pague con un recargo del 10 % [balance].
- **Impago de una familia jugadora** (humana o IA): las reglas de 4.16 (prórroga de 1 estación con +25 %, embargo).
  Lo embargado va al Banquero (`lender_family`), no fuera. Si el deudor no quiere pagar un notarial, `claim_collateral`
  abre juicio de H11 con el cargo `debt_default` (leve), cuya condena es la garantía.
- **Prestamista de la ciudad** (`request_loan` con `lender: "moneylender"`, en el Ayuntamiento): cualquier familia
  puede pedir hasta el 50 % de su patrimonio estimado (oro + edificios), plazo 8 o 16 días, 25 % anual, garantía un
  edificio [balance] (ver O12). Con Banco de otra familia, la solicitud del jugador aparece en ese Banco y su dueño
  decide (la IA con una regla mínima: acepta si el patrimonio cubre el doble).
- Ledger: el interés cobrado es `loans`; el libro enseña aparte «Intereses» en la pestaña de deudas.

Cuenta de referencia: 800 de capital prestado a 25 % anual medio con 7 % de impago y 50 % de recuperación rinden
~19 %/año ≈ 19 oro/día. **La banca es tardía** (4.2.1): rinde con capital, no con trabajo.

#### 4.22.5.7 Interfaz

| Qué | Dónde | Estado |
|---|---|---|
| Interiores, cola, almacén, mostrador | los de 4.22.4.8 | existe |
| Pacientes esperando, misas y horario, precio de cada servicio, camas | `docs/ui/mecanicas/servicios.md` | **falta** |
| Estado de salud (herido / enfermo, hasta cuándo) en el retrato, la ficha y el árbol | [familia.md](../ui/mecanicas/familia.md), [ciudad_viva.md](../ui/mecanicas/ciudad_viva.md) | añadir |
| **Banco**: solicitudes (cantidad, plazo, riesgo, interés máximo), cartera (cuotas, pendiente, notarial), morosos con «Reclamar garantía» | `docs/ui/mecanicas/banco.md` | **falta** |
| **Pedir préstamo** (prestamista de la ciudad o un Banco) | `banco.md` y la pestaña de deudas de [mercado_y_libro.md](../ui/mecanicas/mercado_y_libro.md) | **falta** |
| Encargos del Escriba y del Médico | tablón de [ciudad_viva.md](../ui/mecanicas/ciudad_viva.md) | existe |

#### 4.22.5.8 Bots y dianas

| Bot | Desde | Qué hace | Diana (Normal, 30 semillas) [balance] |
|---|---|---|---|
| `physician` | partida nueva `scholar_physician` | Atiende, hace vendas, encargos, ajusta precio, paga la deuda | Oro neto/día días 1-8 en [+25, +60]; deuda pagada antes del día 8 en ≥ 90 % |
| `priest` | escenario `church_open` | Las tres misas, bendiciones, velas | Oro neto/día días 1-16 en [+20, +80]; reputación +20 en 16 días |
| `alchemist` | escenario `apothecary_open` (Botica + Herbolario) | Hierbas, extracto, ungüentos y pociones | Oro neto/día días 1-16 en [+20, +80] |
| `scribe` | escenario `scriptorium_open` | Encargos, cartas, contratos | ídem |
| `banker` | escenario `bank_open` (Banco, 800 oro) | Acepta A y B con margen, reclama morosos | Rendimiento del capital en 16 días ≥ +15 % anual; impagos perdidos < 20 % de lo prestado |

#### 4.22.5.9 Riesgos

| Riesgo | Qué pasa | Mitigación |
|---|---|---|
| Ciudad pequeña, pocos pacientes | El médico no gana | Vendas como oficio de reserva; encargos; heridos del Pícaro y microeventos |
| Banca como fuente sin riesgo | El banquero acumula sin límite | Impagos; capital limitado al oro propio; banco con título mínimo |
| El jugador Artesano pide al prestamista y se salta la deuda inicial | La deuda de 4.16 pierde tensión | El prestamista no presta con un préstamo en impago ni más del 50 % del patrimonio |
| Los servicios inyectan oro de fuera | Inflación de la familia | Igual que el mostrador; los bots vigilan las dianas de `goldflow` |

---

### 4.22.6 Pícaro: combate, vigilancia, robo, guardias, mercancía robada, rescates, espionaje y armas

| Profesión | Edificio | Cadena | Fuente principal |
|---|---|---|---|
| Ladrón | Guarida de ladrones (3×3, producción) | CRIMINAL | Carteras de día, almacenes de noche, perista |
| Espía | Guarida de ladrones | CRIMINAL | Encargos de espionaje, chantaje |
| Bandido | Nido de bandidos (4×4, rústica, junto a un camino) | CRIMINAL | Asaltos a forasteros, rescates |
| Mercenario | **Cuartel** (3×3, producción; P9, O9) | — | Contratos de escolta, guardia, cobro y recompensas |

#### 4.22.6.1 Combate como orden

> [!NOTE]
> [04e_combate.md](04e_combate.md) (borrador, 2026-11-04) propone resolver todo combate con el lance del duelo «a tres
> tiempos» en vez de estos asaltos (O-C2), con las variantes del Pícaro en 4e.7. Hasta que el owner decida, esta sección
> sigue como está.

`attack(actor, target, intent, stance)`. Se resuelve en el sim, por asaltos de **5 min de juego**; mientras dura,
los dos están ocupados (su cola espera).

```
vida_máx    = 5 + constitución                                   # 6-15 [balance]
cada asalto, los dos golpean a la vez:
  acierta   = SkillCheck(arte_marcial_A, arte_marcial_B) + mods_A
  daño      = 3 + arma_A − armadura_B, mínimo 1
mods (en puntos del umbral) [balance]:
  espada +10 (arma +2 de daño) · herramienta +5 (+1) · armadura del rival −10 (y −1 de daño recibido)
  herido −20 · emboscada (primer asalto, si el objetivo no le vio venir: SkillCheck sigilo vs empatía) +20
  aliados en el mismo combate +10 cada uno, máx +20 · veneno equipado +15 y +1 de daño (se gasta)
fin: vida ≤ 0 → derrotado · tras cada asalto, quien tenga ≤ 40 % de vida actúa según su postura · máx. 8 asaltos (tablas)
```

| Postura (`stance`) | Con ≤ 40 % de vida | Por defecto de |
|---|---|---|
| `to_the_end` | sigue | guardias, mercenarios en contrato |
| `flee` | huye: SkillCheck(destreza, destreza); si falla, sigue | vecinos, forasteros, jugador (por defecto) |
| `yield` | se rinde: entrega la bolsa o el botín, sin herida | — |

- **Derrotado:** herido 24 h (4.22.3.3). Con `intent: rob`, el vencedor se lleva la bolsa del forastero o del vecino
  (de fuera, `loot`) o, si es de una familia jugadora, `min(15 + 2 × destreza ; 10 % del oro de su familia)` (`loot` /
  `theft`). Con `intent: hostage`, se lo lleva al Nido (4.22.6.6).
- **Sin muertes en H12** (P7, O4).
- **Legalidad:** atacar a quien no te atacó es `brawl` (leve); con robo, `robbery` (media); a un guardia o con rehén,
  `violent_crime` (máxima). Defenderse no es delito. `Watch.observe` en el primer asalto.
- Cuenta de referencia: Pícaro (Arte Marcial 7, espada) contra un vecino (3, sin arma): acierta ~80 %, el vecino ~30 %;
  gana en 2-3 asaltos en ≥ 90 % de las semillas. Contra un guardia (6, espada, armadura) gana < 35 %.

#### 4.22.6.2 Guardias

- **Quiénes:** personajes de la familia `fam_watch` («Guardia de la ciudad», no juega), creados con la partida:
  2 de noche y 1 de día [balance] (`data/town.json` → `guards`: Arte Marcial 6, Empatía 5, Constitución 6, espada y
  armadura). Los paga la ciudad (no salen en ningún libro; ver O7). Si muere la población no cambian.
- **Rutina:** de noche recorren en bucle una ruta de patrulla del mapa (`patrols`: lista de casillas, una ruta por
  guardia); de día uno está en la plaza. Se mueven con el movimiento de 5.4 (por eso son lo único nuevo que cuesta
  cada minuto: 3 personajes más).
- **Grito:** un testigo que ve un delito grita; los guardias a ≤ 12 casillas van al sitio. Un guardia que **ve** al
  autor lo persigue: si llega a ≤ 1 casilla, abre la **detención**. Si el autor se mete en un edificio propio o en su
  Guarida, o se aleja más de su vista durante 30 min, lo pierde (pero el hecho queda visto y denunciado).
- **El Alguacil** (H10) ve los hechos denunciados (ya lo hace) y gana el poder activo `set_patrol` (elegir qué ruta
  hace cada guardia esta noche) [propuesta].
- **El ladrón nocturno de H7 usa este sistema:** después de la tirada de Seguridad de hoy (que no cambia), si no lo
  frustró, `Watch.observe` con el ladrón NPC (Sigilo 5); si lo ve un guardia, lo detiene sin botín y avisa («La guardia
  ha detenido a un ladrón en tu forja»). Mismas pruebas de H7 en verde; solo puede bajar los robos (revisar dianas).

#### 4.22.6.3 Detención

Cuando un guardia alcanza al autor, se abre una detención (`state.town.guards[g].chasing`) y el autor responde con
`arrest_response` (tarjeta no bloqueante; 30 min de juego; por defecto `surrender`):

| Respuesta | Regla [balance] | Resultado |
|---|---|---|
| `surrender` | — | Juicio de H11 con `source: arrest`, el guardia testigo en contra y +1 prueba (flagrante). El acusado no está preso: prepara la defensa como siempre. |
| `flee` | SkillCheck(destreza, destreza del guardia) | Éxito: escapa, el hecho queda público. Fallo: detenido + cargo extra `resisting` (leve). |
| `fight` | combate contra el guardia (y los que lleguen) | Gana: escapa, cargo extra `violent_crime`. Pierde: herido y detenido. |
| `bribe` | paga `20 + 5 × negociación del guardia`; SkillCheck(negociación, 5) | Éxito: le suelta y el hecho no se denuncia. Fallo: pierde el oro y cargo extra `bribery`. |

Lo que lleva encima con `@stolen` o veneno se requisa y suma cargos (`receiving`, `poison`). Lo robado vuelve a su
dueño si se sabe quién es.

#### 4.22.6.4 Robo, mercancía robada y perista

**Carterista** (`rob` a una persona, DÍA o ATARDECER, a ≤ 1 casilla, 10 min):

```
éxito  = SkillCheck(destreza, empatía_víctima) + 10 si hay multitud
botín  = vecino o forastero: 5-12 oro de fuera (loot) · familia jugadora: min(5 + destreza ; 5 % de su oro) (loot / theft)
fallo  = la víctima ve al autor (hecho con seen_by la víctima, relación −30, Cabreado) y grita
fallo crítico = además, cualquier guardia a la vista detiene
```

[balance] La misma víctima, una vez al día. Cada fallo en la plaza ese día da −10 al siguiente intento (la gente se
guarda la bolsa).

**Robo en un edificio** (`rob` a un edificio, NOCHE, en su puerta, edificio ajeno con almacén, 30 min):

```
cerradura = 2 + 2 × nivel de Seguridad (0-3)      → 2 / 4 / 6 / 8
éxito     = SkillCheck(sigilo, cerradura) + 10 con ganzúas equipadas
botín     = hasta 2 + destreza ÷ 2 unidades, de lo más valioso, sin pasar del peso que puede cargar → <item>@stolen
fallo     = ruido: Watch.observe con +20 para los testigos; los que duermen dentro se despiertan
```

- Un edificio robado no se puede volver a robar en 2 días y su cerradura cuenta +2 durante ese tiempo [balance].
- Los negocios NPC del mapa (un hogar con taller) tienen un **almacén de muestra** que se repone al amanecer
  (`npc_stock` en el mapa, p. ej. 6 panes): dan a quién robar sin simular su economía.
- Cada robo detectado o no queda en el registro de la víctima con el valor estimado (4.19: no mueve oro).

**Mercancía robada** (P6, O5): el objeto robado entra como `<item>@stolen` (p. ej. `sword@stolen`). `Catalog.item()`
quita el sufijo para peso, pila y precio; `Inventory` no cambia (la pila es `(id, calidad)` y el id ya es distinto).

- No se puede vender en el mercado, el mostrador ni entregar en encargos (`reason.stolen_goods`), ni usar como entrada
  de una receta.
- **Perista** (`sell` en el puesto `fence`: uno NPC en la Taberna de NOCHE, o junto a la puerta oeste si no
  hay Taberna, y el puesto `fence` de cada Guarida): paga el 50 % del precio de venta del mercado (+10 % con `underworld ≥ 50`) [balance], **hasta 150 oro por día**
  entre todos [balance] (`state.town.fence`). No toca la demanda del mercado.
- **Blanquear** (`den_launder`, receta craft de la Guarida, banco de trabajo): quita la marca a 1 unidad cada 0,5 h;
  Destreza 5. Lo blanqueado se vende normal (y sí baja la demanda).
- **Fama en los bajos fondos** (`families[].underworld`, 0-100): +2 por robo con éxito, −5 por condena. Sube lo que
  paga el perista y abre los contratos de espionaje [balance].

#### 4.22.6.5 Espía

- **`spy(actor, bld, 2 h)`** a ≤ 2 casillas de un edificio ajeno. Cada hora, `Watch.observe` como «merodear» (+10 al
  espía; si le ven de noche junto a una puerta, hecho `trespass`, leve). Al terminar, SkillCheck(sigilo, 5 + nivel de
  Seguridad):
  - Éxito: informe en `families[].intel` (`{about_family, building, day, data}`): oro de la familia (±5 %), contenido
    del almacén, mejoras de Secretos. **Cada mejora de Secretos descubierta crea un hecho oculto** (`tax_evasion` o
    `smuggling`, como la inspección de H11) con `seen_by` = el espía: sirve para acusar o chantajear.
  - Fallo: nada.
- **Secretos de los vecinos:** al crear la ciudad, el 25 % de los hogares NPC tiene un secreto (`tax_evasion`,
  `smuggling` o `adultery`, este último sin juicio) [balance]: es lo que se descubre espiando su casa.
- **Encargos de espionaje** (`data/contracts/spy.json`, `kind: "intel"`): «Averigua si los Ferrer tienen contrabando»;
  se entregan con un informe de esa familia de después de aceptar. Pago 40-80 [balance]. Requieren `underworld ≥ 10`.
- **Chantaje** (`blackmail`): exige `max(20 ; 10 % del patrimonio estimado)` por estación. La víctima responde con
  `answer_blackmail` (tarjeta de 2 h; por defecto no pagar). Un hogar NPC paga si el cargo es medio o más (70 %)
  [balance]; una familia IA, con la regla mínima: paga si su honestidad < 0 y el cargo es medio o más. Si no paga, el
  espía puede hacer público el hecho. El chantaje crea un hecho `extortion` (media) visto por la víctima.

#### 4.22.6.6 Bandido y rescates (cadena CRIMINAL)

- El Nido tiene un puesto exterior **`road`** enlazado a un tramo de camino del mapa (`roads`). Quien hace
  `work_at(road, bandit_ambush)` (receta `service` sin precio) espera: cada forastero que pasa a ≤ 3 casillas es
  atacado (`attack` con `intent: rob` y emboscada). Los empleados con rol `ambush` también (de DÍA y ATARDECER).
- **Botín:** la bolsa del forastero (15-40; ricos 60-120) y 0-2 objetos de muestra `@stolen` [balance].
- **Rehén** (`intent: hostage`, solo forasteros ricos; ver O6): queda en la jaula del Nido (1 sitio; +1 por mejora).
  Cada amanecer, 50 % de que su familia (de fuera) pague el **rescate** de 80-200 [balance] (`loot`); cada día que
  sigue, 20 % de que la ciudad descubra el Nido: hecho `kidnapping` público contra su dueño. Soltarle sin rescate
  (`release_hostage`) no borra el hecho si ya era público.
- Cadena: Nido → (botín `@stolen`) → Guarida (blanquear o perista). La Guarida y el Nido de la misma familia comparten
  el perista sin tope extra.

#### 4.22.6.7 Mercenario

Contratos del tablón (`data/contracts/mercenary.json`) y del tablón del Cuartel, con `kind` nuevo [balance]:

| `kind` | Qué hay que hacer | Se cumple cuando | Pago |
|---|---|---|---|
| `escort` | Esperar a un forastero en la puerta a la hora dada y acompañarle hasta la Posada o la plaza | El forastero llega sin ser robado | 25-40 |
| `night_guard` | Guardar la puerta de un edificio de 21 a 05 | Nadie lo roba esa noche; el mercenario cuenta como guardia ahí | 30 |
| `collect_debt` | Cobrar a un moroso del Banco (de otra familia): SkillCheck Arte Marcial vs Arte Marcial o combate | Paga | 20 % de lo cobrado |
| `bounty` | Vencer a un bandido NPC que ronda un camino | Derrotado | 60-100 |

- Los empleados del Cuartel con rol `escort` o `guard` cogen y cumplen contratos solos.
- Las armas y armaduras del Mercenario salen de la Forja: es demanda nueva para el Artesano.
- Un Mercenario en `night_guard` en un edificio cuenta en `Watch.observe` como guardia y en la detención.

#### 4.22.6.8 Contratos con condición

`accept_contract` y `deliver_contract` (H3) aceptan `kind` además de los de objetos: la plantilla dice qué se
comprueba (`condition: {kind: escort | night_guard | collect_debt | bounty | intel, target, window}`) y el sim marca el
contrato como cumplido cuando ocurre; `deliver_contract` cobra. Incumplir, como hoy (−5 de reputación, −15 de relación).

#### 4.22.6.9 Encaje con el tribunal (H11)

- **Cargos nuevos** en `data/justice.json` → `charges` [balance]:

| Cargo | Gravedad | De qué |
|---|---|---|
| `petty_theft` | leve | carterista |
| `trespass` | leve | merodear de noche, espiar visto |
| `resisting` | leve | huir de la guardia y fallar |
| `receiving` | leve | llevar mercancía robada |
| `debt_default` | leve, condena = la garantía | impago de un préstamo notarial |
| `theft` | media | robo en edificio |
| `robbery` | media | robo con violencia |
| `extortion` | media | chantaje |
| `poison` | media | llevar veneno |
| `kidnapping` | máxima | rehén |

- `brawl`, `bribery` y `violent_crime` ya existen.
- **Testigos:** al abrir un juicio por un hecho con `seen_by`, esos testigos entran primero y **en contra**; cada uno
  vale como hoy (15) y además el hecho suma `proofs.fact` (1). La disposición del resto sigue la regla de H11.
- **Condena media por robo:** la confiscación de H11 (los productos del negocio implicado) más devolver lo robado.
- **Destierro de un Pícaro** (máxima, 1 año): su Guarida sigue con empleados; él no puede actuar (regla de H11).

#### 4.22.6.10 Encaje con la IA rival (04c, sin cambiarla)

| 04c espera | Lo da este diseño |
|---|---|
| `known`: delitos vistos por un miembro o empleado (4.21.4) | Hechos con `seen_by` (4.22.3.5) |
| Rivalidad +30 si B roba a A, detectado (4.21.8.1) | Evento `crime_detected` con `culprit_family` y `victim_family` |
| Juicio con motivo real (4.21.9.1) | `accuse` acepta el hecho oculto si lo vio su familia |
| Sabotaje (H13): de noche, la Seguridad lo reduce, detectado por Seguridad, testigos o guardias | Las mismas piezas: puerta de noche, `cerradura`, `Watch.observe`, guardias. La orden `sabotage` la define 04c en H13. |
| Simetría (4.21.9.2) | El jugador puede robar, espiar y chantajear a las familias IA con las mismas órdenes |

- **La IA rival no roba ni chantajea en H12**: no está en la lista cerrada de ataques de 04c. Si el owner lo quiere,
  se añade a 04c cuando lo revise (no aquí).
- Las familias IA de otras clases (granja, banco, guarida) llegan con los perfiles de H13; en H12 compiten con el
  jugador los proveedores NPC (`npc_providers`) y Ferrer.

#### 4.22.6.11 Inicio del Pícaro: Ladrón

Si se aprueba O2 (`data/starts/rogue_thief.json`, Normal) [balance]:

| Elemento | Valor |
|---|---|
| Protagonista | 20 años, Común, reputación 0, `underworld` 0, honestidad −10 |
| Oro | 30 |
| Edificio | Guarida con vivienda: perista propio, banco de trabajo |
| Inventario | ganzúas equipadas (herramienta nueva, +10 al robo de edificios), capa de viaje |
| Deuda | 200, 1 año (4.16) |

Objetivos: (1) roba una bolsa en el mercado sin que te vean; (2) véndele algo al perista; (3) entra de noche en un
almacén; (4) blanquea una pieza y véndela en el mercado; (5) pasa una noche entera sin que te vea la guardia;
(6) devuelve la deuda.

> [!NOTE]
> **Construido (rama picaro, 2026-11-06): el Pícaro empieza como Ladrón** (`sim/rogue/rogue.gd`, `data/rogue.json`).
> - **Inicio `rogue_thief`**: la Guarida de ladrones (3×3 con vivienda, `data/buildings/den.json`) en el solar de la
>   Consulta (sitio `player_clinic`: el inicio dice qué edificio levanta en él, sin sitio nuevo en el mapa), ganzúas equipadas, una capa de viaje en la
>   Guarida, 30 de oro y la deuda de inicio de siempre (sin tocar). Objetivos: robar una bolsa, venderle al perista,
>   entrar en un almacén, blanquear una pieza, hacerse un nombre (5 golpes) y pagar la deuda.
> - **Carterista** (`pickpocket`, ficha de la persona: «Robar la bolsa» con la probabilidad en el tooltip): de día o
>   al atardecer, a 1 casilla, Destreza contra Empatía (+10 con multitud, −10 por cada fallo del día; la palanca de
>   dificultad). Botín: 5-12 de fuera, o min(5 + Destreza; 5 % del oro) de una familia que juega.
> - **Robo en un almacén** (`burgle`, panel del edificio ajeno de noche: «Robar el almacén» con su cerradura y la
>   probabilidad): cerradura 2 + 2 × Seguridad (+2 dos días tras un robo), Sigilo contra ella, +10 con ganzúas y la rama
>   Calidad de la Guarida (`lock_bonus`). Botín: hasta 2 + Destreza ÷ 2 piezas de lo más valioso, marcadas.
> - **Lo robado** es `<item>@stolen`: el catálogo lo lee como la pieza (peso, pila, precio), pero ningún puesto,
>   receta ni encargo lo acepta. **El perista** (la mesa de la Guarida a cualquier hora, o la Taberna de noche) paga la
>   mitad del precio de mercado (+10 % con bajos fondos ≥ 50, +la rama Comercio `fence_bonus`, × la dificultad), hasta
>   150 de oro al día entre todos. **El banco** de la Guarida quita la marca a una pieza cada 30 min (Destreza 5; más
>   rápido con la rama Producción). La fama en los bajos fondos (`families[].underworld`) sube +2 por golpe.
> - **Testigos y guardia** (4.22.3.5, simplificado): un guardia de servicio a 8 casillas de día o 5 de noche ve el delito
>   y detiene; si no, la víctima te ve al fallar (relación −30) y el hecho queda **oculto** con ella de testigo. Al
>   amanecer lo **denuncia** con la probabilidad de su relación (< 0: 0,9; < 30: 0,5; si no, 0,1) y la villa lleva a
>   juicio un robo denunciado de cada familia con un 3 % al día. **La detención** (4.22.6.3) llega como carta a quien
>   juega: rendirse (juicio con el guardia de testigo y requisa de lo robado), huir, luchar (un duelo contra el guardia)
>   o sobornar, cada una con su probabilidad; sin respuesta en media hora, se rinde. La IA y los bots se rinden.
> - **Encargos del ladrón** (`data/contracts/thief.json`): un comprador discreto pide piezas de valor (candelabros,
>   espadas, ropa fina); solo valen limpias (`obtained: stolen`: el validador no pide que la Guarida las fabrique).
> - **Árbol de 24 mejoras** de la Guarida, **interior por datos** con piezas que ya existían (mesa del perista, banco
>   del falsario, alijo del contrabandista) y fachada en bloque gris oscuro hasta su arte (`bld_den`, falta).
> - **Bot `rogue_novice`** (paso `rogue` de run_all): bolsas de día a quien no le ve venir y fuera de la vista de la
>   guardia, un almacén de noche cuya puerta no ve nadie, el perista y el banco, la deuda. 48,7 netos/día en Normal
>   (10 semillas, 30,0-61,6), Fácil 58,6 > Normal 48,7 > Difícil 40,4 (`data/difficulty.json` `rogue`: el modificador de las tiradas
>   y lo que paga el perista), deuda saldada 5/5.
> - **Guardado:** sin versión nueva (lo nuevo se lee con valores por defecto). Espía, Bandido, Mercenario, la
>   vigilancia de vecinos con su tirada (`Watch.observe`), el combate como orden y el Nido quedan para los bloques
>   siguientes del Pícaro.

#### 4.22.6.12 Un día normal

| Profesión | Día | Atardecer | Noche |
|---|---|---|---|
| Ladrón | Carteras en la plaza; mirar qué almacenes tienen género (espiar) | Perista en la Taberna | Robar un almacén evitando la patrulla; blanquear |
| Espía | Encargos de espionaje; vigilar un taller | Cobrar chantajes; vender informes | Espiar casas con secretos |
| Bandido | Emboscada en el camino con su banda | Llevar el botín a la Guarida | Guardar al rehén, cobrar rescates |
| Mercenario | Escoltas desde la puerta; recompensas | Cobros para el Banco | Guardia nocturna de un taller |

#### 4.22.6.13 Interfaz

| Qué | Dónde | Estado |
|---|---|---|
| **Acciones de intriga** en el menú contextual del mapa: Robar, Robar la bolsa, Espiar, Atacar, Asaltar, Chantajear (con el motivo si no se puede) | `docs/ui/mecanicas/noche_y_crimen.md` | **falta** |
| **Medidor de visibilidad** sobre el personaje («ojo»: oculto / a la vista / visto), luz de las antorchas y **círculos de vista de los guardias** dibujados de noche | el mismo | **falta** |
| **Tarjeta de detención** (Rendirse / Huir / Luchar / Sobornar, con la probabilidad en el tooltip) | el mismo | **falta** |
| **Perista** (tope del día, precio, «robado» marcado en rojo en los iconos) | el mismo y [almacen_y_personaje.md](../ui/mecanicas/almacen_y_personaje.md) | **falta** |
| **Expedientes**: lo que han visto tus espías, hechos que puedes usar (Acusar / Chantajear) | el mismo | **falta** |
| **Combate**: el duelo «a tres tiempos» (lances, gesto, aliento, toques) y su resultado; 04e propone que sustituya a los asaltos de 4.22.6.1 (O-C2) | [combate.md](../ui/mecanicas/combate.md) | borrador (prototipo aparte) |
| Rehenes del Nido y rescates | `noche_y_crimen.md` | **falta** |
| Juicio y acusar | [tribunal.md](../ui/mecanicas/tribunal.md) | existe; añadir «testigo presencial» |
| Contratos de armas en el tablón | [ciudad_viva.md](../ui/mecanicas/ciudad_viva.md) | existe; añadir el `kind` |

#### 4.22.6.14 Bots y dianas

| Bot | Desde | Qué hace | Diana (Normal, 30 semillas) [balance] |
|---|---|---|---|
| `thief` | partida nueva `rogue_thief` | Carteras de día; de noche roba el almacén más rentable fuera de la patrulla; perista; blanquea; se rinde si le detienen | Oro neto/día días 1-8 en [+25, +60]; deuda pagada en ≥ 80 %; **≥ 1 juicio en 40 días en 40-80 % de las semillas** (el crimen compensa con riesgo) |
| `spy` | escenario `den_open` (Guarida, `underworld` 20) | Encargos de espionaje, espía casas, chantajea NPC | Oro neto/día días 1-16 en [+20, +80]; ≥ 1 juicio en 40 días en ≤ 60 % |
| `bandit` | escenario `nest_open` (Nido + 1 empleado) | Emboscadas de día, rehenes, rescates | Oro neto/día días 1-16 en [+20, +80]; condena máxima en ≤ 30 % |
| `mercenary` | escenario `barracks_open` (Cuartel, espada y armadura) | Escoltas, guardias nocturnas, recompensas | Oro neto/día días 1-16 en [+20, +80]; ningún juicio |
| `idle` + guardias | partida nueva Artesano | — | Las dianas de H3 y H5 del Artesano siguen en verde (regresión) |

#### 4.22.6.15 Riesgos

| Riesgo | Qué pasa | Mitigación |
|---|---|---|
| El robo es más rentable que cualquier oficio | Todos roban | Tope del perista, cerraduras, guardias, juicios; diana que exige juicios |
| La guardia hace imposible jugar de Pícaro | Frustración | Rutas visibles y fijas por noche, luz visible, medidor «ojo», sobornar |
| Combate injusto (muerte por mala suerte) | Pérdida del heredero | Sin muertes en H12 (P7); huida por defecto |
| Coste del sim con guardias moviéndose | > 2 ms por paso | Solo 3 guardias; `Watch.observe` solo al ocurrir un delito; `sim_bench` |
| Mercancía robada con sufijo rompe algo que compara ids | Errores en mercado o recetas | Validador y pruebas: ninguna receta, puesto ni encargo acepta `@stolen` |
| El ladrón NPC de H7 roba menos con guardias | Las dianas de H7 se mueven | Se aplica después de la tirada de Seguridad; se mide y se explica si cambia |

---

### 4.22.7 Mejoras de los edificios nuevos

Cada edificio tiene su árbol de **8 ramas × 3 niveles** (4.8). Para que H12 sea abordable:

- **Ramas comunes** (Capacidad-almacén, Personal, Fachada, Seguridad, Secretos, Comercio): los mismos efectos y nombres
  que la Forja, con coste en oro `coste_forja × build_cost / 100` redondeado a 5 y los mismos materiales (madera,
  piedra, lingotes) [balance]. Visuales genéricos (4.6.4).
- **Producción y Calidad**, propias de cada oficio:

| Edificio | Producción 1 / 2 / 3 | Calidad 1 / 2 / 3 |
|---|---|---|
| Granja | Arado de hierro (campos ×1,25) / +2 campos / corral +4 | Abono (+15 % de cosecha) / rotación (+30 %) / semilla selecta (+50 %) |
| Molino | Muela de piedra ×1,2 / segunda muela / ×1,6 | — (la harina no tiene calidad): Almacén seco (+10 pilas) en su lugar |
| Panadería | Horno grande ×1,2 / segundo horno / ×1,6 + `bakery_pie` | Masa madre +1 / +2 / +3 |
| Carnicería | Tajo doble / ahumadero 2 / ×1,6 | Especias +1 / +2 / +3 |
| Taberna / Posada | Barril grande (cerveza ×1,5) / +4 mesas o +2 camas / segunda barra | Cocinero (+1) / bodega (+2) / fama (+3, clientes +30 %) |
| Iglesia | +6 bancos / campanario (asistencia ×1,2) / vidrieras (×1,4) | Coro (donativo +1) / reliquia (+2) / órgano (+3 y reputación +1 por misa) |
| Consulta | Segunda camilla / instrumental (visitas ×1,3) / quirófano (`doctor_surgery` sin ungüento) | +1 / +2 / +3 a la tirada de curar |
| Botica | Alambique doble / mesa 2 / ×1,6 | +1 / +2 / +3 |
| Scriptorium | Segundo escritorio / prensa (documentos ×2) / biblioteca (encargos +50 %) | +1 / +2 / +3 |
| Banco | Contable (solicitudes ×1,5) / sucursal (+1 solicitud) / casa de cambio | Informe de solvencia (ve el riesgo exacto) / avales (recuperación +15 %) / fianzas (impago −30 %) |
| Guarida | Contactos (perista +10 %) / segundo banco de blanqueo / red (tope del perista +100) | Ganzúas finas (+10) / disfraces (−10 a la vista de testigos) / túnel (escapar a la Guarida desde 6 casillas) |
| Nido | Vigía (emboscada +10) / jaula 2 / segunda emboscada | Armas (+5) / mejor botín (+25 %) / escondite (descubrir el Nido −50 %) |
| Cuartel | Literas (+1 empleado) / sala de armas / patio | Instructor (+5 en combate) / +10 / +15 |

---

### 4.22.8 Objetos nuevos y cuentas de referencia

**Objetos** (`data/items/`) [balance]. Precio base; venta = × 0,7 (4.5.3).

| Id | Categoría | Peso | Precio | Puesto | `demand_weight` | Notas |
|---|---|---|---|---|---|---|
| `flour` | material | 2,0 | **15** (era 12) | materiales | 0,2 | P10 |
| `sheep` | materia prima | 25 | 40 | `livestock` | 0,5 | animal |
| `pig` | materia prima | 20 | 24 | `livestock` | 0,5 | animal |
| `meat` | material | 1,0 | 7 | alimentos | 0,2 | |
| `sausage` | producto | 1,0 | 22 | alimentos | 0,25 | |
| `meat_pie` | producto | 1,0 | 18 | alimentos | 0,25 | |
| `ale` | consumible | 1,0 | 4 | alimentos | 0,25 | |
| `candle` | consumible | 0,1 | 2 | boticario | 0,25 | |
| `parchment` | materia prima | 0,1 | 4 | materiales | 0,25 | |
| `extract` | material | 0,5 | 14 | boticario | 0,5 | |
| `salve` | consumible | 0,5 | 12 | boticario | 0,5 | |
| `potion` | producto | 0,5 | 55 | boticario | 1 | |
| `poison` | especial | 0,1 | 60 | — (perista) | — | ilegal |
| `forged_document` | especial | 0,05 | 30 | — (perista) | — | ilegal |
| `lockpick` | herramienta | 0,3 | 25 | armería | 1 | herramienta del Ladrón |

Ya existen y se usan: `wheat`, `wool`, `herbs`, `bread`, `bandages`, `cloth`, `wood`, `document`, `contract`, `hoe`.

**Margen por hora de trabajo** con todo comprado al mercado (Normal, calidad normal, demanda 1) [balance]. Referencia:
la espada de la Forja desde el hierro da ~3,5 oro/h; el martillo, ~2,9.

| Oficio | Receta (o cadena) | Margen por hora |
|---|---|---|
| Molinero | `mill_flour` | 2,5 |
| Panadero | `bakery_bread` (harina comprada) / desde trigo (molino + horno) | 2,8 / 4,0 |
| Carnicero | `butcher_cut` / cerdo → salchichas | 2,7 / 4,0 |
| Alquimista | hierbas → ungüento / hierbas → poción | 3,1 / 2,8 |
| Médico | `doctor_visit` / `doctor_bandages` | 12 por paciente / 2,8 |
| Granjero | trigo (por campo y año: 70 oro en 6 h) / oveja (2,8 al día sin trabajo) | 11,7 (estacional) / pasivo |

Cuenta de cada inicio [balance]: Granjero ~39 oro netos/día de media en el año 1 (cosecha 35 + lana 11 + cerdos 8 −
mantenimiento 15); Médico ~35 (pacientes 18 + vendas 28 − mantenimiento 12); Ladrón muy variable, con techo en el
perista (150/día). Las tres dentro de la banda [+25, +60] de 4.19 si las semillas acompañan: lo confirman los bots.

---

### 4.22.9 Arte y audio

Todo con greybox primero (regla del proyecto); la lista de la compra es para el ciclo de PixelLab del **15-nov**, con
`palette` = tokens de la biblia y revisión contra `docs/style/biblia.md`. Las cifras de generaciones son estimaciones
de las descripciones de cada herramienta (9.3, `docs/ui/03_produccion_sin_creditos.md`): **comprobar el coste con
`get_balance` y una prueba antes de lanzar cada bloque**.

**Lista de la compra PixelLab (15-nov)**, por prioridad:

| # | Qué | Herramienta | Cuánto | Generaciones (estim.) | Por qué |
|---|---|---|---|---|---|
| 1 | **Exteriores de los 15 edificios** (Granja, Molino, Panadería, Carnicería, Taberna, Posada, Iglesia, Consulta, Botica, Scriptorium, Banco, Herbolario, Guarida, Nido, Cuartel = 15), estado normal | `create_map_object`, `background_image` de la Forja | 15 + 5 de repesca | 20-25 | Lo que el jugador reconoce en el mapa |
| 2 | **Estados de campo** (tierra, surcos, brotes, trigo verde, trigo maduro, podrido, hierbas) | `create_isometric_tile` / `create_tiles_pro` 64×32 | 1 hoja de 8-16 | 10-20 | Sin esto no se lee el ciclo de cultivo |
| 3 | **Personajes nuevos** (8 direcciones + andar): guardia, pícaro m/f, bandido, mercenario, sacerdote, erudito m/f, granjero m/f, forastero | `create_character` + `animate_character` | 11 | 110-180 | Guardias y pícaros son la lectura de la noche; respetar los colores clave (4.10.9) |
| 4 | **Animales** (oveja, cerdo: 4 direcciones, quieto y andar) | `create_character` (cuadrúpedo) | 2 | 20-30 | El corral vivo |
| 5 | **Puestos de oficio** (muela, horno de pan, artesa, tajo, ahumadero, barra, barril, camas, altar, bancos, camilla, mortero, alambique, mesa de alquimia, escritorio, mostrador del banco, cámara, mesa de perista, banco de blanqueo, jaula, fogata, armero) | `create_map_object` (o gratis con `pixelart_workbench`) | ~22 | 22-30 | Los interiores; el kit genérico ya cubre lo demás |
| 6 | **Iconos** (15 objetos nuevos + combate, ojo, guardia, detención, rehén, préstamo, interés, sembrar, cosechar, misa, curar, marca «robado») | `create_1_direction_object` `size` 32, hoja de 64 | 1 hoja + repesca | 10-20 | 64 iconos por ~10 |
| 7 | Estados obras y dañado de los 15 exteriores | `create_object_state` | 30 | 30 | Puede esperar: el greybox de obra vale |
| 8 | Reserva | — | — | 20-30 | |
| | **Total** | | | **~240-365** de 2.000 | Junto a la lista de UI (~200), cabe en un ciclo |

**Gratis** (sin créditos): humo de chimeneas, aspas del molino, chispas del horno, antorcha de los guardias y su
círculo de luz, golpe de combate (`vfx_workbench`); marca roja de «robado» sobre el icono y barras de crecimiento
(dibujo por código, 5.10).

**Audio** (`data/audio.json` por id; no se genera nada en este encargo; ElevenLabs con su tope cuando se pida):

| Tipo | Ids propuestos |
|---|---|
| Efectos | `combat_hit`, `combat_miss`, `combat_flee`, `lockpick`, `guard_shout` («¡Al ladrón!»), `guard_whistle`, `coin_drop` (donativo), `church_bell`, `sheep_bleat`, `pig_grunt`, `mill_creak`, `oven_crackle`, `quill_scratch`, `bank_ledger`, `cage_rattle` |
| Ambiente | `amb_tavern_crowd`, `amb_mass_chant`, `amb_farm_day`, `amb_night_streets` |
| Música (Suno, owner) | tema de noche e intriga (paleta otoñal de 9.6) |

---

### 4.22.10 Plan de H12 por bloques

H12 empieza con el resto del Artesano (fuera de este documento) y sigue con estos bloques; cada uno cierra con sus
pruebas, su bot y su escenario de test (`tools/scenarios/`).

| Bloque | Entra | Pruebas (GUT, `tests/test_*.gd`) |
|---|---|---|
| **H12.0 Base común** | v21 y migración; recetas `field`/`service` y `stat`; `demand_weight`; `Services` (demanda, elección, visita, efectos); `health`; `Watch.observe`; forasteros; `Loan` ampliado | Ida y vuelta v14 → v15; elección de proveedor con semilla (más barato = más clientes); conservación con las categorías nuevas; `demand_weight` no cambia la espada |
| **H12.1 Patrón** | Granja (campos, corral), Molino, Panadería, Carnicería, Taberna, Posada; `livestock`; inicio `patron_farmer`; bots | Ciclo del trigo (siembra día 1 → listo día 5, invierno 0, podrido a los 2 días, interrumpir devuelve la semilla); ganado (pienso de invierno, muerte a los 2 días, cría); taberna de noche con empleados |
| **H12.2 Erudito** | Consulta, Iglesia, Botica, Herbolario, Scriptorium, Banco; solicitudes, cuotas, impago, garantía, prestamista; inicio `scholar_physician`; bots | Curar (tirada y tiempos); misa a horas fijas con donativos; préstamo: cuotas, impago, reclamar (60 / 30 %), embargo a familia jugadora para el banquero; la deuda inicial de H3 sigue igual |
| **H12.3 Pícaro** | Combate, guardias y patrullas, detención, carterista, robo, `@stolen`, perista, blanquear, espía, chantaje, Nido y rehenes, Cuartel y contratos; cargos; inicio `rogue_thief`; bots | Combate (200 semillas: 7 vs 3 gana ≥ 90 %, vs guardia < 35 %); vista de noche < de día; detención y sus 4 respuestas; `@stolen` rechazado en mercado y recetas; tope del perista; ladrón de H7 con guardias |
| **H12.4 Integración visual** | Exteriores, campos, corral, interiores, UI de 4.22.4.8, 4.22.5.7 y 4.22.6.13 con greybox o arte del 15-nov; `--smoke-script` por clase | Capturas de cada clase en `docs/novedades/` |

Criterios de H12 (10_hitos.md) que cubre: «cada profesión tiene un bot que gana dinero con ella» (4.22.4.9, 4.22.5.8,
4.22.6.14) y «tests de reglas de combate, robo, servicio, préstamo y ciclo de cultivo» (tabla de arriba).

---

### 4.22.11 Decisiones que necesitan al owner

| # | Decisión | Opciones | Recomendación |
|---|---|---|---|
| **O1** | Dónde vive el estado del campo | (a) En el edificio, por puesto (P1). (b) En la parcela de H6, como decía 4.22. | **(a)**: funciona sin H6 y las parcelas vinculadas solo añaden puestos. |
| **O2** | Con qué profesiones se puede empezar partida nueva | (a) Una por clase: Herrero, Granjero, Médico, Ladrón. (b) Todas las que tienen edificio inicial. (c) Solo el Herrero; las demás clases por herencia o cambio de oficio. | **(a)**: cuatro inicios con deuda y objetivos son abarcables y probables con bots; el resto de oficios llegan con el segundo edificio (H6). |
| **O3** | Diana de oro de las profesiones nuevas | (a) La misma banda que el Artesano en su fase ([+25, +60] al inicio). (b) Solo «gana dinero» (> 0). (c) Banda propia por profesión. | **(a)** para los inicios y [+20, +80] para el resto desde su escenario; la banca, rendimiento del capital. Ninguna clase debe ser la fácil. |
| **O4** | Muerte en combate | (a) Ninguna en H12. (b) Solo en ataques declarados a muerte (cargo máximo). (c) También en duelos. | **(a)**: perder al heredero por una tirada es injusto; la muerte llega con los sicarios de 04c en H13 si se quiere. |
| **O5** | Cómo se marca lo robado | (a) Variante de id `sword@stolen`. (b) Campo `stolen` en la pila (cambia la clave de 5.9 y todas las llamadas). (c) Un objeto genérico «mercancía robada». | **(a)**: no toca `Inventory`, conserva qué es y su calidad, y el validador lo controla. |
| **O6** | Quién puede ser rehén | (a) Solo forasteros ricos. (b) También miembros de familias IA. (c) También la familia del jugador. | **(a)** en H12: (b) y (c) necesitan rescates negociados y reacción de la IA (04c). |
| **O7** | Quién paga a los guardias | (a) La ciudad, fuera del libro. (b) Un presupuesto que sale de los impuestos (H10). | **(a)**: no hay arcas municipales en el MVP (4.19); se revisa si llegan. |
| **O8** | Peso de demanda por objeto (P3) | (a) Campo `demand_weight` por objeto. (b) Bajada proporcional al valor vendido (cambiaría el martillo). (c) Dejarlo como está. | **(a)**: el Artesano no cambia y el trigo deja de hundir el mercado. |
| **O9** | Edificio del Mercenario | (a) Cuartel nuevo (3×3, producción). (b) Comparte el Nido con el Bandido. (c) Sin edificio: profesión por equipo. | **(a)**: el mercenario es legal; meterlo en un nido criminal le haría inspeccionable y juzgable por error. Cuesta un edificio de arte más. |
| **O10** | El documento falso del Escriba y el tribunal | (a) Solo ayuda a fabricar pruebas (+20 a la tirada). (b) También da prueba a la defensa (cambia la fórmula de la vista). (c) No en H12. | **(a)**: une Escriba y Pícaro sin tocar la vista de H11. |
| **O11** | Activar el estado Inspirado (POST-MVP en 4.11.5) | (a) Sí, con la misa y la bendición. (b) No: la misa solo da reputación y donativos. | **(a)**: es la razón de ir a misa para un jugador; +10 % a empleados es pequeño y medible. |
| **O12** | Préstamos para el jugador | (a) Cualquier familia puede pedir al prestamista de la ciudad desde H12 (25 % anual, tope 50 % del patrimonio). (b) Solo si hay un Banco de otra familia. (c) El jugador no pide préstamos. | **(a)**: da sentido al libro y al Banquero; los bots del Artesano no lo usan, así que sus dianas no se mueven. |
| **O13** | Edificios de otra clase | (a) Cualquier familia puede tener cualquiera (límite por título). (b) Sí, pero sus miembros trabajan como no profesionales (×0,75, sin toque de maestro); los empleados, normal. (c) No. | **(b)**: la cadena PAN o ALQUIMIA cruza clases sin borrar la identidad de cada una. |
| **O14** | Peligros nocturnos para el jugador (asaltos de NPC en la calle, 4.12.6) | (a) Solo en zonas del mapa marcadas como inseguras (ninguna en `town_e`). (b) En toda la ciudad de noche. (c) Nunca. | **(a)**: llega con el mapa EA (H13) sin mover las dianas del Artesano. |
| **O15** | Precio de la harina 12 → 15 y los precios nuevos de 4.22.8 | (a) Aceptar como punto de partida de los bots. (b) Mantener 12 y cambiar las proporciones de las recetas. | **(a)**: la harina no la usa nadie hoy y con 12 el Molino pierde dinero. |

# Empleados: plantilla, contratar, salarios y rangos

Id: `empleados` · Panel de hoy: `game/ui/staff_panel.tscn` · GDD 4.7.1-4.7.4 · Datos: `data/employees.json` ·
Convenciones: [_comun.md](_comun.md)

## 1. Para qué sirve

Contratar es la primera gran decisión de dinero tras la deuda: un oficial cuesta 20 ⦿ al día, pagados cada alba
aunque no haya trabajo. Preguntas que responde:

- **«¿A quién contrato y qué podrá hacer?»** Rango, atributos que importan y, sobre todo, **qué recetas puede
  hacer** con su Artesanía.
- **«¿Rinde lo que pago?»** Salario frente a velocidad y eficiencia de su rango, y qué hace ahora mismo.
- **«¿Está contento? ¿Se me va a ir o me va a robar?»** Lealtad con sus umbrales y lo que pasa en cada tramo.
- **«¿Cuándo asciende y qué me cuesta?»** El progreso hacia el ascenso y el salario nuevo.

## 2. Cómo se abre y se cierra

- Botón *Empleados* de la barra del interior o ficha `☺ 1/1` de la placa del edificio.
- Clic en un aviso de empleado del libro (ascenso, lealtad, abandono): abre el interior en gestión con este panel y
  el empleado resaltado.
- Clic en un empleado dentro del interior: abre el panel en *Plantilla* con su tarjeta.
- Se cierra con X, con Esc u otro panel lateral. No pausa.

## 3. Jerarquía de información

Dos pestañas, como hoy: **Plantilla** (por defecto si hay alguien) · **Contratar** (por defecto si la plantilla está
vacía).

1. Cabecera común: huecos `1/2`, salarios del día `27 ⦿/día` y oro de la familia.
2. *Plantilla*: una tarjeta por empleado con qué hace ahora, la barra de lealtad con sus umbrales y el progreso de
   ascenso. Un ascenso pendiente va primero, con filete dorado.
3. *Contratar*: la tabla de rangos (qué da cada uno y cuánto cuesta) y los candidatos con sus recetas posibles.
4. A demanda (tooltip): los tramos de lealtad con su efecto, la fórmula de eficiencia y los días que faltan para el
   ascenso.

## 4. Acciones y sus estados

### 4.1 Contratar

```
 ┌ EMPLEADOS · Forja ────────────────────────────────── [x] ┐
 │ [Plantilla] [■ Contratar]      Huecos 0/1 · 65 ⦿           │
 │ ┌ RANGOS ──────────────────────────────────────────────┐ │
 │ │ Aprendiz  7 ⦿/día  ×1 velocidad  50 %  · abundantes   │ │  tabla de data/employees.json
 │ │ Oficial  20 ⦿/día  ×2 velocidad 100 %  · algunos      │ │
 │ │ Maestro  40 ⦿/día  ×3 velocidad 150 %  🔒 Taller de maestro │
 │ └──────────────────────────────────────────────────────┘ │
 │ [ret] Margarida  OFICIAL   20 ⦿/día       [ Contratar ]   │
 │       Artesanía ▮▮▮▮▯▯▯▯▯▯ 4  Carisma 5  Const. 5         │
 │       Puede: ▣ lingote ⚒ martillo ⚔ espada  🔒 armadura   │  recetas según Artesanía
 │ [ret] Guillem    OFICIAL   20 ⦿/día       [ Contratar ]   │
 │       Artesanía ▮▮▮▮▮▮▯▯▯▯ 6  Carisma 4  Const. 6         │
 │       Puede: ▣ ⚒ ⚔ ▤ (todas)                              │
 │ [ret] Agnès      APRENDIZ   7 ⦿/día       [ Contratar ]   │
 │       ...                                                │
 ├──────────────────────────────────────────────────────────┤
 │ Empieza mañana al alba. El salario se cobra cada alba.   │  ayuda fija
 └──────────────────────────────────────────────────────────┘
```

| Elemento | Normal | Deshabilitado (motivo visible) | Orden |
|---|---|---|---|
| *Contratar* | Primer clic: el botón pasa a «¿Contratar? 20 ⦿/día»; el segundo clic da la orden. Es una confirmación en línea: la cuota es diaria | `no_slot`: «Sin hueco (1/1) → *Dormitorio de aprendiz* +1» · `not_enough_gold`: «Necesitas 20 ⦿ (1 día de salario)» · `banned`: «Te robó: no vuelve hasta el día 17» · `needs_upgrade`: «Maestro: necesita *Taller de maestro*» | `hire {building, candidate}` |
| «Puede:» | Icono de cada receta del edificio; las que tienen `min_craft` mayor que su Artesanía, con candado | — | — |
| Retrato | 32×32 con el color de su familia | — | — |

Los candidatos se ordenan como hoy: primero los contratables y, dentro, por rango y por id. Se enseñan todos con
scroll; hoy la lista se corta por abajo sin señal de que haya más.

### 4.2 Plantilla

```
 ┌ EMPLEADOS · Forja ────────────────────────────────── [x] ┐
 │ [■ Plantilla] [Contratar]   Huecos 2/2 · 27 ⦿/día · 65 ⦿   │
 │ ┏ [ret] Joan   APRENDIZ → OFICIAL ━━━━━━━━━━━━━━━━━━━━━┓ │  ascenso pendiente, primero
 │ ┃ Puede ascender: salario 7 → 20, velocidad ×1 → ×2      ┃ │
 │ ┃ [ Aceptar · +15 lealtad ]  [ Rechazar · −10 lealtad ]  ┃ │
 │ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │
 │ [ret] Margarida  OFICIAL   20 ⦿/día                       │
 │       ⚒ Yunque · Forjar espada 40 %                       │  qué hace ahora
 │       Lealtad 62 ▕██████▒▒▒▒│▒▒▒│▒▒▒▒▒▒▒│░░░░▏ descontenta │  marcas en 20 / 40 / 70
 │       −20 % de eficiencia y rumores (−1 rep.)             │  efecto del tramo
 │       Ascenso a maestro: 3/16 días · lealtad > 70 ✗       │
 │       Puesto: (Horno)(■Yunque)(Mostrador)(Cualquiera)      │  rol
 │       [ Gratificar 5 ⦿ · +5 lealtad ]      [ Despedir ]    │
 ├──────────────────────────────────────────────────────────┤
 │ Salarios de mañana: 27 ⦿ · tienes 65 ⦿                    │
 └──────────────────────────────────────────────────────────┘
```

| Elemento | Normal | Deshabilitado / especial | Orden |
|---|---|---|---|
| Rol (4 botones con icono) | El activo con filete dorado; tooltip «Solo trabaja en el yunque» o «Va donde haga falta» (BUG-023) | Puestos que el edificio no tiene, ocultos | `set_role {employee, role}` |
| *Gratificar* | +5 lealtad por 5 ⦿ | `not_enough_gold` | `bonus {employee}` |
| *Despedir* | Confirmación: «Margarida se va hoy al final del día. Ya cobró hoy.» Si su lealtad > 70, añade en rojo: «Era leal: reputación −2» | Con contratación que aún no empezó: «Se cancela ya» | `fire {employee}` |
| *Aceptar / Rechazar* ascenso | Con las cifras escritas en el botón | — | `promote {employee, accept}` |

La barra de lealtad lleva los cortes de `data/employees.json` → `bands` (20, 40, 70) como marcas. La palabra del
tramo y su efecto van siempre escritos. Hoy solo dice «Lealtad 50 (descontento)».

**«Qué hace ahora»** sale de `routine` y `task`: «⚒ Yunque · Forjar espada 40 %» · «Llega mañana (día 3) al alba» ·
«Se va hoy al final del día» · «En casa (noche)» · «De camino» · «Ocioso: falta hierro» (motivo de la cola, ver
[produccion.md](produccion.md)) · «Enfermo hasta mañana» (microevento, H7).

## 5. Estados especiales

| Estado | Qué se ve |
|---|---|
| **Sin empleados** | Se abre en *Contratar*. *Plantilla* dice: «Aún no tienes empleados. Trabajan la cola de producción de alba a atardecer» |
| **Sin huecos** | *Contratar* enseña la franja «Sin hueco: *Dormitorio de aprendiz* (+1) o *Taller de maestro* (+1) → Mejoras» y los botones deshabilitados |
| **Sin candidatos** | «Nadie busca trabajo ahora. Mañana puede haber más» |
| **Salario impagado** | Tarjeta con franja roja: «Sin cobrar 1 día: gracia hasta mañana; después −5 lealtad cada día y reputación −2». Aviso en el libro (hoy ya) |
| **Lealtad < 40** | Barra en rojo y la línea «Puede irse sin avisar (5 %/día)». Por debajo de 20: «Puede robar y huir (3 %/día)», con «Seguridad lo divide entre 2» si no hay Seguridad |
| **Abandono o robo** | La tarjeta queda 1 día en gris: «Se fue el día 9» o «Robó 2 espadas y huyó el día 9». Después desaparece |
| **Noche** | Las tarjetas dicen «En casa». Arriba: «Los empleados vuelven al alba (05:00)» |
| **Primera vez** | Primer *Contratar*: globo sobre la tabla de rangos: «Un oficial cuesta 20 al día y trabaja el doble de rápido que un aprendiz» |

## 6. Maqueta

- Hoy: [empleados_hoy_contratar.png](../maquetas/empleados_hoy_contratar.png) (lista cortada, sin qué puede hacer
  cada uno) y [empleados_hoy_plantilla.png](../maquetas/empleados_hoy_plantilla.png) (lealtad en texto, rol en
  desplegable).
- Propuesta: PNG en `docs/ui/maquetas/empleados.png` (*Contratar*) y `empleados_plantilla.png` (*Plantilla* con un
  ascenso pendiente), con `tools/ui/maqueta.py`.

**Piezas de kit pendientes:**
- insignia de rango (A / O / M en 3 colores);
- barra de lealtad con marcas de tramo;
- tarjeta con filete dorado (ascenso pendiente);
- selector de 4 con iconos de puesto: horno y yunque del interior reducidos a 16×16 en el workbench; mostrador;
  `icon_controllable` para *Cualquiera*;
- barra de atributo de 10 pasos (la misma que la ficha del árbol, del worker social).

## 7. Datos

| Lee | De dónde |
|---|---|
| Candidatos | `SimQuery.candidates(sim, actor, bld)` → `[{character, name, female, rank, stats {craft, charisma, constitution}, wage, status}]` |
| Empleados | `SimQuery.employees(sim, bld)` → `[{character, name, rank, role, loyalty, band, wage, days_worked, rank_days, unpaid_days, promotion_offered, active, start_day, end_day, routine, task}]` |
| Huecos | `SimQuery.slots` / `SimQuery.free_slots` |
| Rangos y tramos | `catalog.employees` → `ranks` (wage, speed, efficiency, promote_after_days, promote_min_loyalty), `bands`, `roles` |
| «Puede» | `min_craft` de cada receta de `SimQuery.building_recipes` frente a `stats.craft` del candidato |
| Rango permitido | `Upgrades` `allow_rank` (Taller de maestro) |
| Salarios de mañana | Suma de `wage` de los activos mañana; mejor con la consulta `Upkeep.due_next_dawn` de [mercado_y_libro.md](mercado_y_libro.md) |
| Retrato y color | Visual del personaje (`visual`) + colores de su familia |

Nada nuevo en el sim: todo lo que pide este panel ya está en las dos consultas de hoy.

**Órdenes que emite:** `hire`, `fire`, `promote`, `bonus`, `set_role`.

## 8. Sonido y feedback

| Evento | Sonido | Visual |
|---|---|---|
| `employee_hired` | `sfx_hire` | Tarjeta nueva en *Plantilla* con «Llega mañana» |
| `employee_started` | — | En el mapa, el empleado camina a la forja (hoy ya) |
| `promotion_offered` | **falta**: `sfx_promotion`, campanilla | Insignia con número en el botón *Empleados* y la tarjeta arriba |
| `employee_promoted` | `sfx_objective_done` (o el de ascenso si se hace) | La insignia de rango cambia con destello |
| `wage_unpaid` | `sfx_debt` | Franja roja en la tarjeta |
| `employee_left` / `employee_stole` | `sfx_thief_alarm` (robo) · **falta** `sfx_door_slam` (abandono) | Tarjeta gris 1 día |
| `employee_bonus` | `sfx_coins` | Barra de lealtad sube con «+5» |
| `role_changed` | `sfx_ui_click` | — |

## 9. Diferencias con hoy y tareas

| Hoy | Propuesta |
|---|---|
| Candidatos con 3 atributos en texto | Barra de Artesanía, recetas que puede hacer y rango con su coste |
| Sin comparar rangos | Tabla de rangos arriba de *Contratar* |
| Lista cortada sin scroll visible | Scroll con indicador de «hay más» |
| Contratar con un clic sin aviso del coste diario | Confirmación en línea «¿Contratar? 20 ⦿/día» |
| «Lealtad 50 (descontento)» | Barra con tramos, palabra y efecto |
| Rol en desplegable «CUALQUIERA» | 4 botones con icono |
| «Bonus 5» | «Gratificar 5 ⦿ · +5 lealtad» |
| Despedir sin confirmación | Confirmación con la pérdida de reputación si era leal |
| Sin progreso de ascenso | «3/16 días · lealtad > 70 ✗» |

Tareas:
1. Cabecera común con huecos, salarios y oro.
2. *Contratar*: tabla de rangos, fila doble de candidato con «Puede», confirmación en línea, scroll.
3. *Plantilla*: tarjeta de empleado (qué hace, lealtad con tramos, ascenso, rol con iconos, gratificar, despedir
   con confirmación).
4. Tarjeta de ascenso pendiente arriba con filete dorado e insignia en la barra del interior.
5. Pieza de insignia de rango y barra de lealtad en el kit.
6. `sfx_promotion` y `sfx_door_slam` en `data/audio.json`.

## 10. Criterios de aceptación

- [ ] Un candidato con Artesanía 5 se ve con la armadura (mínimo 6) con candado en «Puede».
- [ ] La tabla de rangos sale de `data/employees.json`: cambiar el salario del oficial allí cambia la tabla.
- [ ] Contratar pide un segundo clic que dice el salario diario.
- [ ] Sin hueco, el motivo nombra la mejora que lo abre.
- [ ] La barra de lealtad tiene marcas en 20, 40 y 70, y el efecto del tramo se lee sin tooltip.
- [ ] Un ascenso pendiente se ve sin abrir el panel (insignia) y, dentro, arriba del todo.
- [ ] Despedir a un empleado con lealtad 75 avisa «reputación −2» antes de confirmar.
- [ ] Con 6 candidatos, la lista hace scroll y nada se corta a 960×540.

## 6. Modelo de datos (fichas de `data/`)

Cada ficha es un JSON con `id` en inglés y `snake_case`. Las plantillas viven en `data/_templates/` (el juego no carga los ficheros que empiezan por `_`). `tools/new_content.py <tipo> --id <id>` crea una ficha desde su plantilla y `tools/validate_content.py` la valida (0 errores para dar algo por hecho).

**Objeto** (`data/items/iron.json`)
```json
{ "id": "iron", "name_key": "item.iron", "category": "raw", "weight": 2.0, "max_stack": 99,
  "base_price": 5, "market_stall": "resources" }
```
Sin ruta al icono: es `assets/art/icons/iron.png` por convención (nombre = id).

**Receta** (`data/recipes/forge_ingot.json`)
```json
{ "id": "forge_ingot", "building": "forge", "zone": "furnace",
  "inputs": [{ "item": "iron", "qty": 2 }], "output": { "item": "iron_ingot", "qty": 1 },
  "kind": "craft", "duration_hours": 1.0, "min_craft": 1 }
```
`kind`: `"craft"` (produce `output`) o `"service"` [EA, reservado: en vez de `output` lleva `effect` y `service_price`, ver 4.22].

**Edificio** (`data/buildings/forge.json`)
```json
{ "id": "forge", "category": "workshop", "parcel_type": "production", "footprint": [3, 4],
  "build_cost": 100, "build_days": 2, "upkeep": 2, "storage_stacks": 10, "base_employees": 1,
  "zones": [ { "id": "furnace", "kind": "craft" }, { "id": "anvil", "kind": "craft" },
             { "id": "counter", "kind": "sales" }, { "id": "storage", "kind": "storage" } ],
  "upgrade_tree": "forge", "night_production": "manual_only", "includes_housing": true }
```
**Nada de rutas en `data/`** (decisión de estructura, 2026-11-01): la ficha no lleva `sprite`, `interior_scene` ni
`interior`. Cómo se ve por fuera es `game/visuals/buildings/forge.tscn` (sprite o greybox, `Marker2D` `Feet` en el
centro de la huella y `Top` en lo alto); su interior, `game/visuals/interiors/forge.tscn` (nodo `Kit` con tamaño y
puerta de la sala, un `Marker2D` por puesto en `Stations/<puesto>` y los visuales de las mejoras en `Upgrades/`). Las
escenas se encuentran por el id (`game/visuals/visual_paths.gd`); el validador rechaza rutas dentro de `data/`.

**Mejora** (`data/upgrades/forge/forge_production_1.json`)
```json
{ "id": "forge_production_1", "name_key": "upgrade.forge_production_1", "tree": "forge", "branch": "production", "level": 1,
  "cost": { "gold": 3, "items": [{ "item": "wood", "qty": 2 }] },
  "requires": { "upgrades": [], "stat": null, "title": null }, "build_days": 0.5,
  "effects": [{ "kind": "production_speed", "mult": 1.2 }],
  "visual": { "interior_node": "forge_bellows", "exterior_overlay": null } }
```
`requires.stat` es `null` o `{ "id": "craft", "min": 6 }` (del actor que la compra); `requires.title`, un id de la
escalera de `data/upgrade_rules.json`. Los tipos de efecto (`kind`), cómo se acumulan y quién los lee viven en
`data/upgrade_rules.json`; los visuales son **ids** de `game/visuals/`, no rutas. Desde H5 (guardado v6) cada edificio
guarda `upgrades` (terminadas), `upgrade_work` (obra en curso) e `inspection`: ver `docs/contratos/h5_mejoras.md`.

**Personaje** (en el guardado, no en `data/`)
```json
{ "id": "chr_0001", "name": "Hugo", "family": "fam_0001", "female": false, "class": "artisan",
  "profession": "blacksmith", "birth_day": -200, "alive": true,
  "stats": { "charisma": 4, "empathy": 3, "negotiation": 6, "arcane": 1, "dexterity": 4,
             "craft": 7, "martial": 3, "constitution": 5, "rhetoric": 3, "stealth": 2 },
  "attitudes": { "honesty": 0, "generosity": 0, "diplomacy": 0 },
  "inventory": { "...": "..." }, "equipment": { "tool": null, "clothes": null, "accessory": null },
  "home": "bld_0002", "rank": "apprentice", "job": { "building": "bld_0001", "role": "any",
  "loyalty": 50, "hired_day": 3, "start_day": 4, "end_day": -1, "days_worked": 0, "rank_days": 0, "unpaid_days": 0,
  "promotion_offered": false }, "hire_bans": {}, "routine": {}, "spouse": null, "parents": [], "children": [],
  "controlled_by": "ai", "directives": ["work"], "schedule": null, "order_queue": [], "position": [12, 30],
  "visual": { "base": "artisan_m", "hair": 3, "skin": 1 } }
```
`birth_day` cuenta en días desde el día 1 del año 1: con D1(b) (8 días por año), −200 son 25 años. `visual.hair` y `visual.skin` son índices de la paleta de intercambio; la ropa toma los colores de la familia (4.10.9). Desde v14 `visual.portrait = {type, variant}` es el retrato base (tipo social y variante; la franja de edad la pone la vista) y la raíz guarda `cast = {mode, seed, map}`, cómo se repartió la población (`docs/contratos/poblacion.md`). `schedule` solo lo usan los personajes controlados (4.10.8).

`rank` es el rango de oficio de la persona (`""` si no es trabajador de oficio): vive en el personaje y no en `job`
porque un candidato sin empleo lo enseña y un despedido lo conserva. `job` es `null` sin empleo; su forma y sus reglas,
en `docs/contratos/h4_empleados.md` (desde H4, guardado v5). `hire_bans` = `{familia: hasta_día}` (ladrón huido);
`routine` = memoria libre de la rutina diaria.

> Los empleados **no** tienen una ficha aparte: son personajes con `job`. Se acaba la duplicación `WorkerData` / `CharacterData` y los stats inventados (Fuerza, Inteligencia).

**Familia**: `{ id, name, crest, colors: {primary, secondary}, gold, reputation, class_reputation: {…}, title, heir, members: [], controlled_by: "human"|"ai", ai_profile, ai_state, objectives, goals_done }`. Desde H3 el oro es **de la familia** (una bolsa, `gold`), no de cada personaje; solo lo cambia `Money.change`, que apunta el asiento en el libro (4.18).

**Parcela** (en `data/maps/<mapa>.json`): `{ id, type, origin: [col,row], footprint: [w,h], linked_to: null }`.

**Cargo** (`data/offices/mayor.json`): `{ id, min_title, salary, term_years, seats, passive: [...], powers: [...] }`.

**Evento** (`data/events/famine.json`): `{ id, trigger: { season, chance }, duration_days, effects: [...], text_key }`. `duration_days` en días (1 estación = 2 días).

**Microevento** (`data/microevents/haggling_customer.json`): `{ id, scope, trigger: { phase, conditions, chance_per_day }, cooldown_days, choices: [{ id, text_key, effects: [...] }], default_choice, timeout_hours, text_key }` (4.20).

**Plantilla de encargo** (`data/contracts/blacksmith.json`): `{ profession, items: [{ item, qty: [1, 5], min_quality_chance }], deadline_days: [1, 3], premium: 0.4, reward_reputation, fail_reputation, fail_relation }` (4.5.6).

**Perfil de IA** (`data/ai_profiles/rival_smith.json`): `{ id, weights: { gold, title, office }, aggression, risk_aversion, rivalry_threshold, preferred_professions, sell_min_demand, gold_reserve }` (4.5.5, 4.21).

**Inicio de partida** (`data/starts/artisan_blacksmith.json`): edad, oro, edificio inicial, inventarios, préstamo inicial por dificultad, encargos guionizados y cadena de objetivos (4.16). **Objetivos, metas y puntuación**: `data/objectives/`, `data/goals.json`, `data/score.json` (4.16, 4.17). **Dificultad**: `data/difficulty.json` con las palancas de 4.23.

**Mapa** (`data/maps/town_ea.json`): tamaño, capas de suelo (o referencia a un `.tscn` de tiles), parcelas, edificios iniciales con dueño, casas de NPC, puntos sociales, puestos del mercado, spawns y población inicial (o reglas para generarla).

**Validador** (`tools/validate_content.py` + `tools/validate_structure.py`): todos los `item`, `recipe`, `upgrade`, `building` y `zone` referenciados existen; ninguna ruta a fichero en `data/`; cada edificio con su escena visual y cada puesto con su `Marker2D`; arte en estado `sprite` o más con su fichero; uid en cada `.tscn`/`.tres`; huellas caben en sus parcelas; sin ciclos en prerrequisitos; precios > 0; claves de texto presentes en `i18n/strings.csv`. El juego en debug también valida al arrancar y se detiene ante un error (corrige L9).

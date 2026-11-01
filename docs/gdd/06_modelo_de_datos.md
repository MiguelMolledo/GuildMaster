## 6. Modelo de datos (fichas de `data/`)

Cada ficha es un JSON con `id` en inglés y `snake_case`. Las plantillas viven en `data/_templates/` (el juego no carga los ficheros que empiezan por `_`). `tools/new_content.py <tipo> --id <id>` crea una ficha desde su plantilla y `tools/validate_content.py` la valida (0 errores para dar algo por hecho).

**Objeto** (`data/items/iron.json`)
```json
{ "id": "iron", "name_key": "item.iron", "category": "raw", "weight": 2.0, "max_stack": 99,
  "base_price": 5, "market_stall": "resources", "icon": "assets/art/icons/iron.png" }
```

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
  "upgrade_tree": "forge", "interior_scene": "res://game/interior/forge_interior.tscn",
  "sprite": { "texture": "assets/art/buildings/forge.png", "scale": 1.6, "feet": [96, 170] },
  "night_production": "manual_only", "includes_housing": true }
```

**Mejora** (`data/upgrades/forge/forge_production_1.json`)
```json
{ "id": "forge_production_1", "tree": "forge", "branch": "production", "level": 1,
  "cost": { "gold": 3, "items": [{ "item": "wood", "qty": 2 }] },
  "requires": { "upgrades": [], "stat": null, "title": null }, "build_days": 0.5,
  "effects": [{ "kind": "production_speed", "mult": 1.2 }],
  "visual": { "interior_node": "Bellows", "exterior_overlay": null } }
```

**Personaje** (en el guardado, no en `data/`)
```json
{ "id": "chr_0001", "name": "Hugo", "family": "fam_0001", "female": false, "class": "artisan",
  "profession": "blacksmith", "birth_day": -200, "alive": true,
  "stats": { "charisma": 4, "empathy": 3, "negotiation": 6, "arcane": 1, "dexterity": 4,
             "craft": 7, "martial": 3, "constitution": 5, "rhetoric": 3, "stealth": 2 },
  "attitudes": { "honesty": 0, "generosity": 0, "diplomacy": 0 },
  "gold": 50, "inventory": { "...": "..." }, "equipment": { "tool": null, "clothes": null, "accessory": null },
  "home": "bld_0002", "job": { "building": "bld_0001", "rank": "apprentice", "role": "any",
  "loyalty": 50, "days_worked": 0 }, "spouse": null, "parents": [], "children": [],
  "controlled_by": "ai", "directives": ["work"], "schedule": null, "order_queue": [], "position": [12, 30],
  "visual": { "base": "artisan_m", "hair": 3, "skin": 1 } }
```
`birth_day` cuenta en días desde el día 1 del año 1: con D1(b) (8 días por año), −200 son 25 años. `visual.hair` y `visual.skin` son índices de la paleta de intercambio; la ropa toma los colores de la familia (4.10.9). `schedule` solo lo usan los personajes controlados (4.10.8).

> Los empleados **no** tienen una ficha aparte: son personajes con `job`. Se acaba la duplicación `WorkerData` / `CharacterData` y los stats inventados (Fuerza, Inteligencia).

**Familia**: `{ id, name, crest, colors: {primary, secondary}, reputation, class_reputation: {…}, title, heir, members: [], controlled_by: "human"|"ai", ai_profile, objectives, goals_done }`.

**Parcela** (en `data/maps/<mapa>.json`): `{ id, type, origin: [col,row], footprint: [w,h], linked_to: null }`.

**Cargo** (`data/offices/mayor.json`): `{ id, min_title, salary, term_years, seats, passive: [...], powers: [...] }`.

**Evento** (`data/events/famine.json`): `{ id, trigger: { season, chance }, duration_days, effects: [...], text_key }`. `duration_days` en días (1 estación = 2 días).

**Microevento** (`data/microevents/haggling_customer.json`): `{ id, scope, trigger: { phase, conditions, chance_per_day }, cooldown_days, choices: [{ id, text_key, effects: [...] }], default_choice, timeout_hours, text_key }` (4.20).

**Plantilla de encargo** (`data/contracts/blacksmith.json`): `{ profession, items: [{ item, qty: [1, 5], min_quality_chance }], deadline_days: [1, 3], premium: 0.4, reward_reputation, fail_reputation, fail_relation }` (4.5.6).

**Perfil de IA** (`data/ai_profiles/rival_smith.json`): `{ id, weights: { gold, title, office }, aggression, risk_aversion, rivalry_threshold, preferred_professions, sell_min_demand, gold_reserve }` (4.5.5, 4.21).

**Inicio de partida** (`data/starts/artisan_blacksmith.json`): edad, oro, edificio inicial, inventarios, préstamo inicial por dificultad, encargos guionizados y cadena de objetivos (4.16). **Objetivos, metas y puntuación**: `data/objectives/`, `data/goals.json`, `data/score.json` (4.16, 4.17). **Dificultad**: `data/difficulty.json` con las palancas de 4.23.

**Mapa** (`data/maps/town_ea.json`): tamaño, capas de suelo (o referencia a un `.tscn` de tiles), parcelas, edificios iniciales con dueño, casas de NPC, puntos sociales, puestos del mercado, spawns y población inicial (o reglas para generarla).

**Validador** (`tools/validate_content.py`): todos los `item`, `recipe`, `upgrade`, `building`, `zone`, `icon` y `texture` referenciados existen; huellas caben en sus parcelas; sin ciclos en prerrequisitos; precios > 0; claves de texto presentes en `i18n/strings.csv`. El juego en debug también valida al arrancar y se detiene ante un error (corrige L9).

## 2. Lecciones del primer intento

El primer intento (abril de 2026, ~3 semanas de desarrollo intensivo con IA) produjo muchos sistemas, pero no un juego jugable de punta a punta. Esta sección es la razón de ser de la reconstrucción. Cada lección tiene una regla asociada que la arquitectura nueva aplica.

### 2.1 Qué funcionó y hay que conservar

- **Diseño de juego**: el GDD y las specs son buenos y están bastante cerrados. La sección 4 los consolida.
- **Pipeline de arte**: PixelLab para sprites (8 direcciones, animaciones) y fal.ai Nano Banana para concepto. Hay ~2.000 PNG reutilizables (personajes de las 4 clases en ambos géneros, NPC, edificios, tiles, iconos, UI).
- **Datos en JSON** (`items.json`, `recipes.json`, `social_phrases.json`) y árboles de mejora como Resource `.tres`.
- **GUT para tests** headless, logs DEBUG con prefijo por sistema, `DevConfig` para acelerar el tiempo en desarrollo.
- **Specs por sistema** con "capacidades del jugador", "restricciones" y "estado de implementación".
- **Mecánicas probadas y que gustan**: cola de producción con dependencias, menú radial, cámara libre WASD, interiores con WorkZones, rutinas NPC por fase del día, burbujas emoji, iluminación día/noche.

### 2.2 Qué falló y por qué

| # | Problema | Evidencia en el proyecto actual | Regla para la reconstrucción |
|---|---|---|---|
| L1 | **La simulación vivía dentro de las escenas visuales.** | BUG-024: los empleados solo producían si el jugador estaba dentro del edificio. La producción estaba duplicada en `WorkerManager._tick_background_production()` y en `BuildingInterior._tick_worker_production()`, que se pisaban. BUG-020, 021 y 023 vienen del mismo origen. | **La simulación no conoce las escenas.** Todo el estado vive en objetos de datos que avanzan con un tick propio. Las escenas solo *dibujan* ese estado y *envían órdenes*. Un interior es una vista de un edificio, no el lugar donde ocurre la producción. |
| L2 | **No existía sistema de guardado.** | Ningún script guarda ni carga partida. Con referencias a nodos y estado repartido por 27 autoloads, añadirlo después es casi imposible. | **Guardar/cargar desde el hito 0.** Todo el estado de partida es serializable a JSON. Un test de ida y vuelta (guardar → cargar → comparar) corre en cada hito. |
| L3 | **Identidades frágiles.** | Los edificios se buscaban por `building_name` (texto). Referencias a `Node` y `NodePath` dentro de los datos (`ParcelData.building_node_ref`). Mezcla de `is_player_owned` y `owner_id`. | **IDs estables y tipados** para toda entidad (`chr_0001`, `bld_0003`). Los datos solo se referencian por ID. Nunca guardar nodos dentro de datos. |
| L4 | **27 autoloads acoplados entre sí.** | Cada sistema guardaba referencias a otros (`_family_manager_ref`, `_reputation_system_ref`…). El orden de carga importaba y los tests necesitaban mocks y `fake_player`. | **Pocos autoloads (4-5).** Los sistemas son clases normales que ejecuta un *runner* en orden fijo. Se comunican mediante el estado compartido y un bus de eventos, no guardando referencias unos a otros. |
| L5 | **Inventario con Gloot y la calidad como propiedad.** | BUG-001, 002, 003 y 025: la calidad se perdía al transferir, se vendía más de lo que había, confusión `protoset`/`ProtoTree`. Muchas funciones duplicadas `*_with_quality`. | **Inventario propio y sencillo**, con pilas indexadas por `(item_id, calidad)`. Sin addons para el núcleo de la simulación. |
| L6 | **Amplitud antes que profundidad.** | Tribunal, elecciones, poderes de cargo y gobierno procedural implementados, mientras seguía abierto lo básico: salarios no se cobraban de verdad (`can_pay` siempre `true`), sin Game Over, sin UI de contratación, vender duplicaba objetos (BUG-025). | **Rebanada vertical primero.** No se empieza un sistema de capa superior hasta que el bucle inferior se puede jugar de punta a punta *en la escena principal*. |
| L7 | **Escenas de test en lugar de un juego.** | 13 escenas `world_test_*` con scripts de montaje de 600-1.350 líneas cada uno. La escena principal (`world_main.gd`) tiene 150 líneas. Cada sistema funcionaba en su escena, pero no juntos. | **Una sola partida real** que crece hito a hito. Los escenarios de prueba son *partidas guardadas* (JSON) que se cargan en la escena principal, no escenas aparte con su propia lógica de montaje. |
| L8 | **Constantes de tiempo incoherentes.** | `DAYS_PER_YEAR = 120` en GovernmentSystem; `days_per_year = 30` en FamilyManager/DevConfig; 4 estaciones × 7 días = 28 días por "año" de calendario. Las recetas duraban segundos reales (lingote = 3 s). | **Un único reloj y una única configuración de tiempo** (`TimeConfig`). Todas las duraciones de diseño se expresan en unidades de juego (horas, días, estaciones, años), nunca en segundos reales. |
| L9 | **Los datos referenciaban cosas que no existían.** | La mejora `forja_fachada_1` pide `piedra` (no existe en `items.json`); `forja_produccion_3` desbloquea la receta `acero` (no existe). Los workers usaban stats "Fuerza" e "Inteligencia" que no son atributos del juego. | **Validación de datos al arrancar**: toda referencia entre catálogos se comprueba y un error de datos detiene el juego en modo debug. Un test de validación de datos corre siempre. |
| L10 | **Specs desincronizadas.** | `politica.md` dice "mayoría no implementado" mientras el pipeline dice 95 %. | **Las specs se actualizan en el mismo commit que el código.** El estado de implementación vive en un solo sitio (el plan de hitos), no repetido en cada spec. |
| L11 | **Enums de contenido en el código.** | Tipos de edificio, profesiones y footprints como `enum`/`const` en GDScript. Añadir una profesión obligaba a tocar varios scripts. | **El contenido es dato.** Edificios, profesiones, recetas, mejoras, cargos y eventos se definen en catálogos. El código solo conoce *categorías de comportamiento*. Una categoría nueva (servicio, combate, cultivo) sí es código: se reserva en la arquitectura desde el principio (5.3, 5.5) y se diseña antes de usarla (4.22). |
| L12 | **UI enorme construida por código.** | Paneles de 600-900 líneas, problemas de ESC y paneles superpuestos (BUG-004, 012), rutas `@onready` que no casaban con el `.tscn`. | **UI en escenas `.tscn` con `%UniqueName`**, un tema común y un gestor de paneles con pila (ESC cierra el de arriba). La UI no contiene reglas de juego: lee el estado y envía órdenes. |
| L13 | **Lo que hacían los tests no ocurría en el juego real.** | Montaje manual en tests que el flujo real no hacía (race conditions con `call_deferred`, BUG-010). | Los tests de integración arrancan la **misma** inicialización que el juego (cargar partida → correr N días), no un montaje paralelo. |

### 2.3 Feedback del owner que sigue vigente

- Gestión de negocios **desde el interior**, con vista isométrica y NPC que entran visiblemente.
- MVP con **un solo rol** (Artesano / Herrero) para todos los sistemas core.
- Sprites de edificio PixelLab de 192 px: filtro `Nearest` y escala `1.6`.
- Scripts de escenas 2D extienden `Node2D`, no `Node`.
- Usar siempre `%UniqueNode` en vez de rutas `$A/B/C`.
- Antes de cerrar un plan: comprobar qué otras specs se ven afectadas e implementar todos los efectos cruzados; no dejar specs con promesas sin código.
- Mantener una guía *HOW TO* para montar mapas (`docs/howto-level-design.md`).

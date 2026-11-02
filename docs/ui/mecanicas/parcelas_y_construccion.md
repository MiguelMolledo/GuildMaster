# Parcelas y construcción: modo construcción, comprar, construir y demoler

Id: `parcelas_y_construccion` · Hito: **H6 (sin hacer)** · Panel de hoy: no existe · GDD 4.9, 4.6.1-4.6.3, 4.12.2
(límite por título), 4.17 (puntos por edificio), 4.19 (`property`); 04c §4.21.6.2-4.21.6.3 solo por lo que el jugador
ve (cartel «Se vende», parcelas ocupadas) · Modelo: 06 (`Parcela`) · Convenciones: [_comun.md](_comun.md)

> [!WARNING]
> Este documento diseña **solo la interfaz del jugador**: modo construcción, parcela, construir, comprar un edificio,
> demoler. **No** diseña la IA rival (puerta pendiente del owner). Donde la IA deja algo visible, como una parcela
> comprada o un cartel de «Se vende», se dice cómo se ve y nada más. Los presagios de ataque («los Ferrer han
> preguntado por la parcela…») los diseña el worker social en `rivales.md`.

## 1. Para qué sirve

Abrir el segundo negocio es el salto de la rebanada al MVP (criterio de H6: «el jugador abre un segundo negocio»).
Preguntas que responde:

- **«¿Dónde puedo construir y qué?»** Parcelas por tipo (rústica, producción, vivienda), libres u ocupadas.
- **«¿Cuánto cuesta y cuándo estará?»** Coste, días de obra y mantenimiento diario que empieza a correr.
- **«¿Puedo tener otro edificio?»** El límite por título (Plebeyo 1, Ciudadano 2, Patricio 4…) y qué me falta.
- **«¿Me sale mejor comprar uno hecho?»** El precio de un edificio ajeno, con su desglose y la actitud del dueño.
- **«¿Quién se está quedando las parcelas?»** Qué está ocupado y por quién, y que siempre quedan 2 libres por tipo
  (la válvula).

## 2. Cómo se abre y se cierra

| Qué | Abrir | Cerrar | Pausa |
|---|---|---|---|
| Modo construcción | Botón del HUD con `icon_build_mode`, o tecla **B** (libre hoy) | B, Esc o el botón otra vez | **No pausa**, como los paneles (GDD 4.1). Las parcelas pueden cambiar mientras miras: la vista se refresca |
| Panel de parcela | Clic en una parcela en modo construcción | X, Esc (vuelve al modo), clic en otra parcela | No |
| Comprar un edificio | Clic en un edificio ajeno en el mapa → su ficha → *Comprar…* (también en modo construcción) | X, Esc | No |
| Demoler | Ficha de un edificio propio (mapa) → menú `⋯` → *Demoler…* | Confirmación | No |

El modo construcción es del mapa: no se entra desde un interior. Al pulsar B dentro de un interior, se sale al mapa
y se entra en el modo.

## 3. Jerarquía de información

**En modo construcción, sin pasar el ratón:**
1. Las **parcelas pintadas por tipo** sobre el mapa (GDD 4.9): verde rústica, naranja producción, azul vivienda y
   gris ocupada. Son los diamantes de `parcels/parcel_<tipo>` de Guild Renew. Las ocupadas llevan el **banderín de
   la familia** dueña; las que están en venta, el cartel.
2. La **franja del modo**, arriba bajo el HUD: edificios propios contra el límite del título, parcelas libres por
   tipo y la leyenda.
3. El resto del mapa, oscurecido un 25 %.

**Al pasar el ratón por una parcela:** filete dorado y tooltip con tipo, tamaño, estado y qué admite.

**Al hacer clic:** panel lateral con la parcela, los edificios que admite y su coste, y *Construir*.

```
 franja del modo (y=52, todo el ancho)
 ┌──────────────────────────────────────────────────────────────────────────────────┐
 │ ⚒ CONSTRUIR  Edificios 1/2 (Ciudadano) · Libres: ■ producción 3 ■ vivienda 4 ■ rústica 2 │
 │            ■ rústica ■ producción ■ vivienda ■ ocupada ⚑ familia  ⌂ se vende      [Salir B] │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

## 4. Acciones y sus estados

### 4.1 Panel de parcela

```
 ┌ PARCELA · Calle del Río ─────────────────────────────── [x] ┐
 │ [◇◇◇]  Producción · 3×4 casillas · libre                      │  miniatura de la huella
 │ [◇◇◇]  A 8 casillas del mercado · a 12 de tu Forja            │  (distancia en línea recta)
 │ [◇◇◇]                                                         │
 │──────────────────────────────────────────────────────────────│
 │ QUÉ PUEDES CONSTRUIR                                          │
 │ [img] Forja          100 ⦿ · obra 2 d · mantenimiento 20/día  │
 │       Fabrica hierro, lingotes, espadas…   [ Construir… ]     │
 │ [img] Carpintería    —  llega con el contenido EA (H12)       │  bloqueado por contenido
 │──────────────────────────────────────────────────────────────│
 │ Tienes 1/1 edificios (Plebeyo).                              │  motivo del título, si aplica
 │ Ciudadano permite 2 → requisitos                             │  enlace a Reputación
 └──────────────────────────────────────────────────────────────┘
```

| Elemento | Normal | Deshabilitado (motivo visible) | Orden |
|---|---|---|---|
| Fila de edificio | Miniatura (el sprite del edificio reducido), nombre, coste, días de obra, mantenimiento y una línea de qué hace | Tipo de parcela incompatible: no sale en la lista (zonificación estricta) | — |
| *Construir…* | Abre la confirmación | `title_too_low` / límite: «Tienes 1/1 edificios (Plebeyo)» · `not_enough_gold`: «Te faltan 35 ⦿» · parcela ya tomada: «Los Ferrer la compraron hace un momento» | `build` (nombre provisional, ver 7) |
| Parcela ocupada (propia) | El panel enseña el edificio y *Gestionar* | — | — |
| Parcela ocupada (ajena) | «De los Ferrer: Forja». Si está en venta, el precio y *Comprar…* | — | — |

**Confirmación de construir** (caja centrada, siempre: es cara y no se cancela):

```
 ┌ CONSTRUIR FORJA ───────────────────────────────────────┐
 │ Parcela de la Calle del Río (producción, 3×4)           │
 │ Pagas ahora:          100 ⦿   (te quedan 85)            │
 │ Obra:                 2 días · lista el día 12 a las 06:00│
 │ Mantenimiento:        20 ⦿ cada alba desde que esté lista │
 │ Edificios:            2/2 (Ciudadano) tras esta obra     │
 │ La obra no se puede cancelar.                           │
 │                         [ Construir ]   [ Cancelar ]     │
 └─────────────────────────────────────────────────────────┘
```

### 4.2 Comprar un edificio hecho

Desde la ficha de un edificio ajeno. El precio sale de GDD 4.9; con el cartel de «Se vende» (quiebra), del precio
fijo de 04c 4.21.6.3.

```
 ┌ COMPRAR · Forja de los Ferrer ──────────────────────── [x] ┐
 │ Coste de construcción               100 ⦿                   │
 │ + mejoras (Fuelle, Mostrador)        45 ⦿                   │
 │ × relación con Bernat Ferrer   Fría  × 1,2                  │  0,8 muy buena … 1,5 mala
 │ ─────────────────────────────────────────                   │
 │ Precio                              174 ⦿   (tienes 210)    │
 │ Tras venderla, Bernat montará negocio en otra parcela.      │  consecuencia según la relación
 │ Te quedas las mejoras; no a sus empleados.                  │
 │ Edificios: 2/2 (Ciudadano) tras la compra                   │
 │                                   [ Comprar… ]              │
 └─────────────────────────────────────────────────────────────┘
```

| Estado | Qué se ve |
|---|---|
| Relación por debajo del umbral | `refuses`: «Bernat no te la vende: relación Hostil». Botón apagado. La relación se mejora con las acciones del worker social (ficha de vecino) |
| Cartel «Se vende» | Precio fijo «coste + mejoras × 0,8», sin la fila de relación; línea «En venta hasta el día 30 (quiebra de los Ferrer)» |
| Límite de título | Igual que construir |
| Edificio público (Armería, Ayuntamiento) | Sin *Comprar*: «Es de la ciudad» |

Que los empleados del vendedor no pasen al comprador es una lectura de 4.9 («relación buena/neutra → [el vendedor]
acepta trabajar para ti»). Ver la **decisión P4**.

### 4.3 Demoler

Ficha del edificio propio → `⋯` → *Demoler…*. Confirmación doble: es lo más destructivo de la economía.

```
 ┌ DEMOLER FORJA ─────────────────────────────────────────┐
 │ Recuperas 40 ⦿ (40 % de 100). Las mejoras se pierden.  │
 │ El almacén pasa a tu casa: 3 pilas.                     │  si hay residencia; si no, motivo
 │ Vecinos con buena relación: −5 (Marta, Joan).           │
 │ Escribe DEMOLER para confirmar: [__________]            │
 │                         [ Demoler ]   [ Cancelar ]      │
 └─────────────────────────────────────────────────────────┘
```

| Motivo para no poder | Texto |
|---|---|
| Tiene empleados (GDD 4.7.3) | «Despide antes a tus 2 empleados» → *Empleados* |
| Obra en curso | «Espera a que acabe la obra» |
| Es la única vivienda de la familia | «Es tu única casa» (**decisión P3**) |

## 5. Estados especiales

| Estado | Qué se ve |
|---|---|
| **Primera vez en modo construcción** | Globo sobre la franja: «Cada color es un tipo de parcela. Clic en una libre para ver qué puedes construir». La primera vez que se cumple el límite, el globo apunta al enlace de requisitos |
| **Límite de edificios alcanzado** | Las parcelas libres se siguen viendo (enseñan el camino), pero el filete al pasar el ratón es gris y la franja dice «1/1 · sube a Ciudadano para tener 2» |
| **Edificio en obra** | En el mapa: andamio (la misma pieza que las mejoras, `Works`) + barra + placa «Forja · lista en 1 d 6 h». En el modo: la parcela con `icon_in_progress`. Al clicar, panel con la obra |
| **Obra terminada** | Aviso «Tu nueva Forja está lista» + crónica (+15 puntos, 4.17). La primera vez, globo: «Contrata a alguien o pon a un familiar a trabajar aquí (árbol, F)» |
| **Una familia IA compra o construye** | La parcela pasa a gris con su banderín y su andamio. Aviso informativo en el libro: «Los Ferrer compran una parcela en la Calle del Río». Es información pública (04c §4.21.4) |
| **Quedan 2 libres de un tipo (válvula)** | En la franja, el número de ese tipo en ámbar con tooltip «Siempre quedan al menos 2 libres de cada tipo» |
| **Parcela que te quitan mientras miras** | El panel se refresca: «Los Ferrer la compraron hace un momento» y *Construir* se apaga |
| **Nada que construir en ese tipo** (rústica en el MVP) | «Aquí van granjas, minas y aserraderos. Llegan con el contenido EA» |
| **Mansión** (2 parcelas de vivienda, 4.6.1) | Al elegirla, se piden 2 parcelas adyacentes: la segunda se marca al pasar el ratón; con una sola libre, motivo «Necesita 2 parcelas de vivienda juntas». Es EA; se deja dicho |

## 6. Maqueta

- Hoy: no hay pantalla. [parcelas_y_construccion_hoy.png](../maquetas/parcelas_y_construccion_hoy.png) es el mapa
  del día 4. Las manzanas libres (`#` en `data/maps/town_e.json`) se rellenan de casas de atrezo y no se distinguen
  de las parcelas.
- Propuesta: PNG en `docs/ui/maquetas/parcelas_y_construccion.png` (modo construcción con franja, parcelas por tipo,
  una ocupada con banderín y el panel de una libre) y `parcelas_y_construccion_confirmar.png` (confirmación de
  construir), con `tools/ui/maqueta.py`.

**Piezas de kit pendientes:**
- diamante de parcela de 64×32 en 4 tintes (de `parcels/parcel_*` de Guild Renew; falta el gris);
- filete dorado de parcela (contorno del rombo de la huella);
- banderín de familia de 8×12 (dos colores de la familia);
- cartel «Se vende» de 16×16: se dibuja en el workbench; no lleva texto en el sprite;
- franja del modo (barra a todo el ancho con la leyenda);
- miniatura de huella (rombos de 8×4);
- caja de confirmación con campo de texto (demoler).

## 7. Datos

H6 no está hecho: los nombres de órdenes y consultas de aquí son **propuestas** para el contrato de H6
(`docs/contratos/h6_*.md`). Manda lo que diga el contrato.

| Lee | De dónde (propuesto) |
|---|---|
| Parcelas | `state.parcels` (ya existe, vacío) con la forma de 06: `{id, type, origin, footprint, linked_to}` + estado: `owner` (familia o «»), `building` (id o null), `for_sale` (precio o null) |
| Parcelas del mapa | `data/maps/<mapa>.json` → `parcels` (hoy no hay: los `#` libres son atrezo) |
| Lo que admite | `catalog.buildings()` con `parcel_type` = tipo de la parcela y `footprint` que cabe |
| Coste, obra, mantenimiento | `build_cost`, `build_days`, `upkeep` de la ficha del edificio (la Forja ya los tiene: 100, 1, 20; el GDD dice 2 días de obra para la Forja, ver P5) |
| Límite por título | `data/titles/<id>.json` → `unlocks.max_buildings` (ya existe: 1 / 2 / 4 / 6 / sin límite) frente a los edificios de la familia |
| Consulta de la vista | `Parcels.view(sim, actor)` → `[{id, type, origin, footprint, owner, building, for_sale, status}]` y `Parcels.options(sim, actor, parcel)` → `[{building_type, cost, days, upkeep, status}]`, `status` = «ok» o el motivo |
| Precio de compra | `Buildings.sale_price(sim, actor, bld)` → `{base, upgrades, relation_mod, price, status}` |
| Devolución de demoler | `Buildings.demolish_refund(sim, bld)` |

**Órdenes propuestas:** `build {actor, parcel, building_type}` · `buy_building {actor, building}` (nombre ya usado en
04c) · `demolish {actor, building}`. Las tres de gestión (no caminan), como `buy_upgrade`.

## 8. Sonido y feedback

| Evento (propuesto) | Sonido | Visual |
|---|---|---|
| Entrar y salir del modo | **falta**: `sfx_build_mode`, un pergamino que se despliega | Velo del 25 % y parcelas que aparecen en 0,2 s |
| `building_started` | `sfx_build_start` (el mismo que pide [mejoras.md](mejoras.md)) | Andamio y barra |
| `building_done` | `sfx_upgrade_done` o **falta** `sfx_building_done`, campana | Andamio fuera, destello, aviso |
| `building_bought` | `sfx_coins` | Banderín de la familia cambia |
| `building_demolished` | **falta**: `sfx_demolish`, derrumbe | Polvo y parcela libre |
| Parcela comprada por otra familia | — (informativo) | Banderín nuevo con parpadeo si el modo está abierto |

## 9. Diferencias con hoy y tareas

Hoy no hay nada de esto en el juego. Tareas para el hito H6, en este orden:
1. Parcelas en `data/maps/town_e.json` (decidir qué manzanas `#` son parcelas y de qué tipo). Las casas de atrezo
   se quedan fuera de ellas.
2. Pieza de diamante de parcela (4 tintes), banderín y cartel en el kit.
3. Modo construcción: velo, capa de parcelas, franja con contadores y leyenda, tecla B.
4. Tooltip y filete al pasar el ratón.
5. Panel de parcela con la lista de lo que admite y los motivos.
6. Confirmación de construir; andamio y barra en el mapa (reutiliza la de mejoras).
7. Ficha de edificio ajeno con *Comprar…* y su desglose; cartel «Se vende».
8. *Demoler…* con confirmación escrita.
9. Selector de edificio propio para cuando haya dos (lo pide este documento al kit). Hoy la barra del interior y
   los paneles dan por hecho un solo edificio. Propuesta: flechas ◀ ▶ en la placa del edificio y la lista «Mis
   edificios» en el HUD.
10. Sonidos `sfx_build_mode`, `sfx_building_done`, `sfx_demolish` en `data/audio.json`.

## Decisiones del owner

| # | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| P1 | ¿La parcela tiene precio aparte del edificio? 4.9 no lo dice; 04c habla de «ahorrar para la parcela» | (a) El `build_cost` incluye el suelo: un solo número. (b) Precio de parcela por tipo (y zona en EA) + coste de obra | **(a)** en el MVP: un número, la confirmación se entiende sola. (b) cuando el mapa EA tenga zonas |
| P2 | ¿Cuánto devuelve demoler? 4.9 dice «30-50 %» | (a) 40 % fijo [balance]. (b) 50 % en estado Normal y 30 % si está Dañado | **(a)**: una cifra que se puede enseñar antes de confirmar |
| P3 | ¿Se puede demoler la única vivienda de la familia? No está en el GDD | (a) No, con el motivo «Es tu única casa». (b) Sí, y la familia queda sin casa | **(a)**: evita un estado sin reglas (¿dónde duermen?, ¿dónde va el inventario de un difunto?) |
| P4 | Al comprar un edificio, ¿qué pasa con los empleados del vendedor? | (a) Se van con el vendedor. (b) Pasan al comprador con su lealtad | **(a)**: es lo que se entiende de 4.9 y no mezcla plantillas |
| P5 | Días de obra de la Forja: el GDD dice 2 y `data/buildings/forge.json` dice 1 | (a) 2, como el GDD. (b) 1, como los datos | Lo que diga el balance de H6; la UI lee el dato. Se apunta solo para que no se pierda |
| P6 | ¿Se puede cancelar una obra de construcción? | (a) No, como las mejoras. (b) Sí, devolviendo una parte | **(a)**: misma regla que las mejoras; menos casos |

## 10. Criterios de aceptación

- [ ] Con B en el mapa se ven todas las parcelas con su color de tipo, y la franja dice edificios/límite y libres
      por tipo.
- [ ] Una parcela ocupada por los Ferrer se distingue de una libre en una captura en escala de grises (banderín, no
      solo color).
- [ ] Con 1/1 edificios como Plebeyo, *Construir* está apagado con «Tienes 1/1 edificios (Plebeyo)» y un enlace a
      los requisitos de Ciudadano.
- [ ] La confirmación de construir dice cuánto pagas, cuánto te queda, cuándo estará y cuánto cuesta al día.
- [ ] Si otra familia compra la parcela con el panel abierto, el panel lo dice y apaga *Construir*.
- [ ] Comprar un edificio ajeno enseña el desglose (coste + mejoras × relación) antes de pagar.
- [ ] Demoler exige escribir la palabra y dice cuánto se recupera.
- [ ] A 960×540 la franja del modo no tapa el reloj ni el retrato del HUD.

# Cortejo y boda

Mecánica de H8 (GDD 4.10.1-4.10.3). Piezas:

| Pieza | Escena hoy | Qué es |
|---|---|---|
| Panel de cortejo | `game/ui/courtship_panel.tscn` | Los solteros a los que la persona elegida puede cortejar, su afinidad y las acciones. |
| Cortejo desde la ficha de vecino | `game/ui/npc_panel.tscn` (no lo tiene hoy) | La afinidad de ese vecino y sus acciones de cortejo, donde ya está el jugador. |
| Boda | — (hoy solo `notice.wedding`) | El momento de la boda y lo que cambia. |

Captura de hoy: no hay guion de captura del cortejo (el escenario `courtship` existe; ver tarea 7). Se describe desde el
código: lista de filas «nombre · familia · edad», barra de afinidad de 70 px, número y botones Conversar / Regalar /
Proponer con el motivo en el tooltip.

---

## 1. Para qué sirve y qué pregunta responde

- «¿Quién está libre y me quiere?» · «¿Qué me falta para poder pedirle matrimonio?» · «¿Por qué no avanza?» (está
  ofendida, ya hablasteis hoy, estás lejos).
- «¿Con quién me conviene casarme?» (de qué familia es, qué título tiene, en qué destaca: los hijos heredan los atributos,
  4.10.3).
- En la boda: «¿Qué cambia ahora?» (se muda a casa, deja su trabajo, cuándo pueden llegar hijos).

## 2. Cómo se abre / cierra y la pausa

| Abrir | Cerrar | Pausa |
|---|---|---|
| Botón «Cortejar» de la ficha del personaje y del árbol (como hoy); y **desde la ficha de un vecino soltero**: sección «Cortejo» con su afinidad y las mismas acciones (nuevo). | X, ESC. | No pausa. |
| La boda: carta central al recibir `wedding` de tu familia. | Botón o 8 s. | No pausa (pero ver §5). |

## 3. Jerarquía de información

### Panel de cortejo

1. **Primero**: quién corteja (retrato 32 de la persona elegida y su Carisma, que multiplica todo) y **cuántos están a
   tiro de proponer** («1 lista para proponer»).
2. **Segundo**: la lista, con la afinidad como **barra con la marca de 80** (umbral de proponer) bien visible; las filas
   ordenadas por afinidad (como hoy). Cada fila: retrato 32 con el color de su familia, nombre, edad, familia y título.
3. **Tercero**: estado de la fila con icono: «bloqueado: ofendida» (rojo), «hoy ya hablasteis» (reloj), «lejos: está en
   la Forja de Ferrer» (pie), «mismo título ×1,15» (estrella pequeña).
4. **A demanda**: tooltip con lo que daría cada acción («Conversar: +3 a +5 (con tu Carisma, +3 a +5)»; «Regalar Espada
   buena: +12»), y una línea «Destaca en: Artesanía, Negociación» (ver decisión).

Filtros arriba (pestañas pequeñas): **Todos · Cerca · Listos (≥ 80)**. Con 20 vecinos la lista no cabe: 6 filas visibles
y desplazamiento.

### Carta de boda

Los dos retratos 64 con un anillo entre ellos, los colores de las dos familias en dos medias cintas, «Hugo y Agnès se
casan», y tres líneas de consecuencias: «Agnès vive ahora en tu casa · deja el Puesto de comida · el primer hijo puede
llegar desde el día 12».

## 4. Acciones y sus estados

Estados de `Courtship.status(sim, actor, target)` (= el campo `status` de `Courtship.candidates`):

| Acción | Orden | Deshabilitado (motivo visible en la fila) | Confirmación |
|---|---|---|---|
| Conversar | `court_talk` | `offended` «Está ofendida contigo» · `already_today` «Ya hablasteis hoy» | No |
| Regalar | `court_gift {item, quality}` | `not_enough` «No llevas nada que regalar» | Sí si vale ≥ 50 de oro (igual que en la ficha de vecino) |
| Proponer | `propose` | `low_affinity` «Afinidad 64 de 80» (con la barra) · `offended` | **Sí**: carta de propuesta (abajo) |
| (lejos) | `too_far` → camina primero (exit_building + move_to + acción en cola) | — | — |

La **propuesta** es irreversible: confirmación con las consecuencias antes de dar la orden:

```
¿Pedir la mano de Agnès Soler?
· Se casará con Hugo y pasará a la familia Herrero.
· Dejará su trabajo en el Puesto de comida.
· Vivirá en vuestra casa (la Forja).
[ PEDIR LA MANO ]  [ Ahora no ]
```

Si el actor no es soltero o es menor, la lista entera se sustituye por el motivo (como hoy) y un enlace a la ficha.

## 5. Estados especiales

| Estado | Qué se ve |
|---|---|
| Nadie disponible | «No hay solteros en la ciudad ahora mismo.» y, debajo, «Los vecinos que enviudan o cumplen 16 aparecen aquí». |
| Bloqueado por emoción | Fila con fondo rojizo, icono de la emoción y cuánto le queda («ofendida · 1 día»). |
| Casado | «Hugo ya está casado con Agnès» + retrato; si es viudo, la lista normal (GDD 4.10.2: puede volver a casarse). |
| Menor | «Pere tiene 14 años: podrá cortejar a los 16 (dentro de 2 años, 16 días)». |
| Primera vez | Globo sobre la marca de 80: «Con 80 de afinidad puedes pedir su mano. Conversar cada día y regalar la suben». |
| Boda con la familia del rival | Línea extra en la carta: «Rivalidad con los Ferrer: −40» **solo cuando** exista la regla de 04c (4.21.8.1, boda entre familias). Hoy no se muestra. |

> [!NOTE]
> **Decisión del owner · ¿cuánto se ve de un pretendiente?** Los hijos heredan la media de los atributos de los padres
> (4.10.3), así que elegir pareja es una decisión de dinastía, pero hoy la ficha de un vecino no enseña atributos.
> (a) Todos los atributos (como la ficha de un familiar). (b) **«Destaca en»: los 2 atributos más altos**, sin número.
> (c) Nada. **Recomendación: (b)**: da la decisión sin convertir el cortejo en una hoja de cálculo, y deja sitio a que
> una acción futura (Empatía, espiar) revele más.

## 6. Maqueta

Panel de cortejo (440 × 300, centrado):

```
+====================================================================+
| CORTEJO · [ret 32] Hugo (Carisma 4)            1 lista      [x]    |
| [Todos] [Cerca] [Listos]                                           |
|--------------------------------------------------------------------|
| [ret] Agnès · 23 · Soler (Ciudadanos) ★                            |
| [32 ] [==================|==]  84   [CONVERSAR][REGALAR][PROPONER] |
|       destaca en Artesanía, Negociación                            |
|--------------------------------------------------------------------|
| [ret] Marta · 19 · Puig                                            |
| [32 ] [==========-------|---]  52   [CONVERSAR][REGALAR][proponer] |
|       ⌚ ya hablasteis hoy                                          |
|--------------------------------------------------------------------|
| [ret] Elena · 25 · Ferrer                         (fondo rojizo)   |
| [32 ] [====--------------|---] 20   [conversar][regalar][proponer] |
|       >:( cabreada con tu familia · 2 días                         |
|--------------------------------------------------------------------|
|                                           ▼ 3 más                  |
+====================================================================+
           marca de 80 ^
```

Sección de cortejo dentro de la ficha de vecino (si el vecino es soltero, adulto y del sexo que admite la regla):

```
| Cortejo                         Afinidad 52   |
| [==========-------|---]                       |
| [CONVERSAR] [REGALAR] [proponer]              |
```

Carta de boda (380 × 200, centrada):

```
+======================================================+
| [cinta Herrero ////][cinta Soler \\\\]               |
|        [ret 64]     (o)     [ret 64]                 |
|          Hugo              Agnès                     |
|            ¡Hugo y Agnès se casan!                   |
|------------------------------------------------------|
| · Agnès vive ahora en vuestra casa                   |
| · Deja su trabajo en el Puesto de comida             |
| · El primer hijo puede llegar desde el día 12        |
|                    [ ¡QUE VIVAN LOS NOVIOS! ]        |
+======================================================+
```

**PNG**: `docs/ui/maquetas/cortejo_panel.png`, `cortejo_ficha_vecino.png`, `cortejo_propuesta.png`, `cortejo_boda.png`.

**Piezas de kit pendientes**: barra con marca de umbral (línea dorada de 1 px en el 80 %); fila con fondo de estado
(rojizo «bloqueado»); pestañas pequeñas de filtro; media cinta de familia (la misma pieza que el estandarte del árbol);
icono anillo 16 (base `icon_ring` de Guild Renew).

## 7. Datos

| Lee | De |
|---|---|
| Candidatos | `Courtship.candidates(sim, actor)` → `[{character, name, female, family, age, affinity, status}]` (ya ordenados) |
| Afinidad de uno | `Courtship.affinity(state, a, b)` |
| Bloqueo y su duración | `Courtship.blocked`; la emoción y su tiempo de `Emotions.list(sim, target)` |
| Distancia y dónde está | `Courtship.in_range`, `Courtship.spot`, `characters[target].location` |
| Ganancia prevista | `data/family.json` `courtship` (`talk`, `gift`, `charisma_step`, `same_title_mult`, `propose_min`) |
| Título de cada familia | `Titles.current(sim, fam)` |
| «Destaca en» | `characters[target].stats` (los 2 mayores), si el owner elige (b) |
| Boda | evento `wedding {family, character, spouse, from_family}`; trabajo que deja: `employee_left {reason: married}` o `characters[target].occupation` antes; primer hijo: `wedding_day` + `data/family.json` `children.first_child_days` |

| Emite |
|---|
| `court_talk {actor, target}`, `court_gift {actor, target, item, quality}`, `propose {actor, target}`; lejos: `exit_building`, `move_to {tile, queued}` y la acción con `queued: true` |

## 8. Sonido y feedback

| Momento | Evento | Estado |
|---|---|---|
| Abrir el panel | `ui.panels` no incluye `courtship_panel` | **Falta** |
| Conversar / regalar con éxito | — | **Falta** `court_affinity_up` (sugerencia: `voice_greeting` + corazón flotante) |
| Llegar a 80 | — | **Falta** `court_ready` (campanilla) |
| Boda | `wedding` | **Falta** `sfx_wedding_bells` (campanas; pedir con la próxima tanda de audio) |

Feedback: «+4» flotante en rosa sobre el pretendiente; la barra crece con animación; al cruzar 80 el botón Proponer se
enciende con un destello de 2 fotogramas.

## 9. Diferencias con hoy y tareas

| Hoy | Debería |
|---|---|
| Filas de texto sin retrato ni título de familia. | Retrato con color de familia, título. |
| Barra sin marca del umbral. | Marca de 80. |
| Motivo solo en tooltip. | Motivo en la fila con icono y duración. |
| Proponer sin confirmación ni consecuencias. | Carta de propuesta. |
| Todos los solteros del pueblo en una lista sin filtro. | Pestañas Todos/Cerca/Listos, 6 filas con desplazamiento. |
| No se puede cortejar desde la ficha del vecino. | Sección «Cortejo» en la ficha. |
| La boda es un aviso en el registro. | Carta de boda con consecuencias. |

Tareas:

1. Kit: barra con umbral, fila con fondo de estado, pestañas, media cinta (pendientes).
2. `courtship_panel`: cabecera con quién corteja y «N listas»; filas con retrato, título, motivo e icono.
3. `courtship_panel`: filtros y desplazamiento.
4. Confirmación de propuesta con consecuencias.
5. `npc_panel`: sección Cortejo (lee `Courtship.candidates` filtrado a ese vecino).
6. Nueva `wedding_card` (misma base que `title_card`).
7. Guion de captura `--smoke-script=cortejo` sobre el escenario `courtship` (panel, propuesta, carta).
8. Audio: `courtship_panel` en `ui.panels`; eventos `court_*` y `wedding`.

## 10. Criterios de aceptación

- [ ] En el escenario `courtship`, a 960×540, se ve sin pasar el ratón quién está lista para proponer y por qué otra fila
      está apagada.
- [ ] La marca de 80 está en la barra y coincide con `courtship.propose_min` (cambiar el dato la mueve).
- [ ] Proponer abre la confirmación con las tres consecuencias; cancelar no da ninguna orden.
- [ ] Desde la ficha de un vecino soltero se puede conversar con él como cortejo sin abrir el panel de cortejo.
- [ ] La boda muestra la carta con los dos retratos y los colores de las dos familias.
- [ ] Con 20 solteros la lista no se sale del panel a 960×540.

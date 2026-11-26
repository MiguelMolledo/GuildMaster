# Repaso en 3D · los oficios (rama `3d`)

> Encargo del owner (2026-11-26): repasar en 3D los oficios que se abren en sitio pero que ningún flujo probaba. Por
> cada oficio un flujo de `data/flows/oficio_<oficio>.json` con `"view": "3d"` que empieza una partida nueva de ese
> oficio (`"start": "<inicio de data/starts>"`), entra en su casa (abierta en sitio en el pueblo 3D), comprueba que
> todos sus puestos están colocados y que la persona se ve dentro, produce de punta a punta (o hace su ciclo propio) y
> vende o cobra, con ratón y teclado reales y la UI de hoy:
> `python3 tools/verifica/verifica.py --flows=oficio_carpinteria,... [--window]` (con ventana ya hace cola en
> `grimoire heavy`: no envolverlo en otro `grimoire heavy`, se bloquea a sí mismo).
> Estado: **verde** (funciona en 3D sin tocar nada), **arreglado** (fallaba en 3D y se arregló), **falla**.

## Tabla

| Oficio | Flujo | Estado en 3D | Qué se arregló / qué falta |
|---|---|---|---|
| Carpintería | `oficio_carpinteria` | **arreglado** | Tablones en el caballete, un barril en el banco, del almacén a la bolsa y vendido en el puesto de mercancías. El trazado 3D de los niveles 1 y 2 no tiene mostrador (la sim sí: zona `counter`): su marca no salía y no se podía pulsar. Ahora una zona sin puesto en el trazado lleva su marca donde `SituLive` pone a quien trabaja en ella (el sitio «shop», si no la entrada), baja, junto a la puerta |
| Cantería | `oficio_canteria` | **arreglado** | Sillares en el banco de corte, una piedra de afilar en el de tallar, vendida en mercancías. Mismo mostrador que faltaba (niveles 1, 2 y 3) |
| Sastrería | `oficio_sastreria` | **arreglado** | Paño en el telar, ropa de trabajo en la mesa de coser, vendida en el puesto de ropa. Mismo mostrador (niveles 1 y 2) |
| Armería (del pueblo) | `oficio_armeria` | **verde** | Entrar, el mostrador en su sitio, comprar un martillo y volver a venderlo. Se juega con el inicio del banquero (los artesanos empiezan con 30 de oro y el martillo cuesta más) |
| Granja | `oficio_granja` | **arreglado** | Sembrar trigo en el campo A, esperar a que crezca (unos días a ×4), cosecharlo, sacar el trigo y venderlo en recursos. Se abría con el **interior de la forja** (ver «El solar del jugador»). Los cuatro campos no tienen sitio en el trazado 3D de la granja: sus marcas van juntas junto a la puerta (se pulsan, pero no están en un campo). «Vender todo» de la cosecha sumaba pieza a pieza en el botón y sacaba el panel del mercado de la pantalla: con más de cuatro piezas solo dice el total |
| Consulta | `oficio_consulta` | **arreglado** | Vendas en el mortero, consulta en la camilla a los pacientes que esperan y cobrarla. Se abría con el interior de la forja |
| Banco | `oficio_banco` | **arreglado** | Las solicitudes del alba, conceder una desde el panel del banco y cobrar el primer plazo (dos días). Se abría con el interior de la forja |
| Guarida (ladrón) | `oficio_guarida` | **arreglado** | Robar la bolsa a un vecino en la calle (su ficha, «Robar la bolsa»), entrar en la guarida, el menú del perista y el del banco de blanquear. Se abría con el interior de la forja. Sin botín robado el perista no tiene qué comprar: el ciclo de robar en una casa de noche y vender al perista no está en el flujo |

### El solar del jugador
En `town_e` el solar del jugador (25, 20) lo comparten varios inicios: la forja, la consulta, la granja, el banco y la
guarida (y los rivales de carpintería, cantería y sastrería). El pueblo 3D levantaba la casa con el tipo de la primera
entrada del mapa (la forja), así que esos oficios abrían el interior de la forja y sus puestos caían a la entrada. Ahora
la casa de un solar es del tipo que la sim tiene allí (`pueblo.gd`, `_entries`).

### Otros arreglos del repaso
- **El nombre de la persona elegida dentro de la casa abierta**: antes solo salía su anillo; ahora lleva su nombre
  encima (`WorldView3D._update_ring`).
- **Ejecutor de flujos**: `"start": "<inicio>"` empieza una partida nueva de ese inicio con el reparto fijo; consultas
  3D `in_place3d`, `stations3d`, `zones`, `seen3d`, y de oficio `field`, `applications`, `victim`.

## Segundo bloque (2026-11-26): lo que dejó abierto el repaso

| Punto | Estado | Qué se hizo y cómo se comprobó |
|---|---|---|
| Mostrador con sitio propio | **hecho** | En la ventana de la fachada (frente de tienda, `shop` en `data/view3d/building_types.json`) en carpintería 1-2, cantería 1-3 y sastrería 1-2; en la carpintería 1 se movieron el jergón y el almacén, en la cantería 2-3 se quitó una pila de bloques de adorno. `rv_auditoria`: 0 fallos en carpintería, cantería, sastrería, armería, forja y granja 2-3 (la granja 1 ya fallaba antes: cama y hogar). Lo añadido a los datos de la prueba lleva `"gm": "GuildMaster-3d…"` y `traer_prueba.py` nunca lo pisa (lo lista para fundir) |
| Campos de la granja fuera | **hecho** | `FarmFields3D`: un bancal por campo en el terreno del solar que la casa no cubre, vestido por su estado (tierra, sembrado, creciendo, listo), y la marca de cada campo sobre su bancal. `oficio_granja` con y sin ventana |
| Rótulos que se pisan | **hecho** | Los nombres de los puestos juntos bajan una línea si taparían a otro (`InteriorView._unstack_labels`); los nombres de la gente dentro (la posada llena) solo del elegido y del que está bajo el ratón. Queda: el nombre de la persona (3D, sobre la cabeza) aún puede tocar el rótulo de un puesto (guarida) |
| Mancha blanca sobre los tejados | **hecho** | Era el humo de las chimeneas a la hora de comer (16 bocanadas por chimenea que crecían a 4 m, casi blancas, sin luz ni niebla: un disco brillante, más con lluvia). Ahora gris, más fino y apagado con nubes y lluvia; captura a las 12:45 junto a la armería sin mancha |
| Carta «Nuevo: tu mostrador» | **hecho** | El texto lleva `{building}`: «en tu banco», «en tu carpintería»… (captura de `oficio_banco`) |
| Mercado: nombre cortado y − / + apagados | **hecho** | La lista de vender ya no corta el nombre; un botón apagado tiene el fondo más oscuro (tema, también en 2D; el color del texto sigue siendo el del token `texto_apagado`) y los − / + apagados del mercado y del banco dicen por qué. Auditoría visual: 0 avisos en cantería, armería y banco |
| Guarida, ciclo completo | **hecho** | `oficio_guarida` sigue hasta la noche: robar en una casa ajena y vendérselo al perista (con y sin ventana) |

## Lo que queda
- **El menú «Enviar → Forja» del recado** que con ventana a veces no coge el clic, y el peor fotograma de 109 ms al
  entrar la persona: sin tocar en este bloque (el tiempo se fue en los puntos 1-6).
- **La granja de nivel 1** (`farm_sitio_n1`): la cama solo se alcanza pasando por el hogar (fallo de `rv_auditoria`
  que ya estaba).
- **Los campos se ven poco** con la casa abierta desde algunos ángulos (el bancal queda tras la pared o el porche del
  patio); las marcas sí se ven y se pulsan.
- **Equilibrio**: el granjero llega al día 5 con 0 de oro (pasado al owner).

## Pruebas (2026-11-26)
- Segundo bloque: reglas 1280/1281 y la que fallaba (el color del texto apagado debe salir de `tools/ui/tokens.json`) arreglada y pasada aparte (`--only=test_ui_hud_theme` 7/7); con ventana oficio_carpinteria, canteria, sastreria, granja, armeria, banco y guarida en verde; sin ventana consulta, sastreria y carpinteria.
- Sin ventana: 8/8 flujos en verde.
- Con ventana (por `grimoire heavy`): 8/8 en verde.
- Reglas: 1281/1281. Vista 3D (`--only=world3d`): 6/6.
- Capturas de cada oficio trabajando: `reports/verifica/2026-11-26/oficio_*/` y, las elegidas, en los ficheros del
  canal (`guildmaster3d/oficios/`).

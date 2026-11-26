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

## Lo que queda
- **Sitio en el trazado 3D** para el mostrador de los talleres de nivel 1 y 2 (y nivel 3 de la cantería) y para los
  cuatro campos de la granja: hoy sus marcas van junto a la puerta. Son datos de los trazados que vienen de Prueba3D
  (`tools/sitio_gen.py`); los campos quizá deban ir fuera, en la huerta.
- **Rótulos que se pisan**: los cuatro campos de la granja, juntos junto a la puerta; en la guarida, el almacén, la
  mesa del perista y el nombre de quien está allí, que quedan juntos junto a la puerta y bajo el alero.
- **Texto de la carta «Nuevo: tu mostrador»**: al banquero le dice «en tu forja» (el texto es el de la forja).
- **El menú «Enviar → Forja» del recado** que con ventana a veces no coge el clic: sin tocar en este repaso (no era
  barato); sigue apuntado en `docs/3d/plan.md`.
- **Hallazgos de la auditoría visual** (también en 2D, no son de la vista): el nombre de la pieza recortado en la lista
  de vender del mercado («Piedra de afilar excelente ×1»); los botones «−» y «+» apagados que se ven iguales que los
  encendidos (mercado y banco).
- **Equilibrio**: el granjero llega al día 5 con 0 de oro (el mantenimiento se come la venta del trigo).

## Pruebas (2026-11-26)
- Sin ventana: 8/8 flujos en verde.
- Con ventana (por `grimoire heavy`): 8/8 en verde.
- Reglas: 1281/1281. Vista 3D (`--only=world3d`): 6/6.
- Capturas de cada oficio trabajando: `reports/verifica/2026-11-26/oficio_*/` y, las elegidas, en los ficheros del
  canal (`guildmaster3d/oficios/`).

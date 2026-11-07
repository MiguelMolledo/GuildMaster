# Campos y ganado: los campos, el calendario de siembra y el corral

> Dueño: mecánicas-economía · Estado: borrador · Fecha: 2026-11-07
> Guía de estilo: [00_lenguaje_visual.md](../00_lenguaje_visual.md) · Zonas y reglas del HUD: [01_hud.md](../01_hud.md)

Id: `campos_y_ganado` · Panel de hoy: `game/ui/farm_panel.tscn` (`FarmPanel`) · GDD 4.22.4.1-2, 4.22.4.8 ·
Convenciones: [_comun.md](_comun.md)

## 1. Para qué sirve

La Granja no fabrica en una cola: siembra en su estación y espera. El panel responde a:

- **«¿Si siembro hoy, cuándo cosecho?»** y **«¿hasta cuándo puedo sembrar?»**: el calendario de 8 días.
- **«¿Qué campo está listo y cuál se me pudre?»**: los días marcados en el calendario y la línea de cada campo.
- **«¿Llega el pienso al invierno?»** y **«¿cuándo vienen crías?»**: el corral.

## 2. Cómo se abre y se cierra

- Botón *Campos* de la barra del interior (tecla **C**), solo en un edificio con campos o con corral (hoy, la
  Granja). Es un panel de la zona de gestión: abrirlo cierra Almacén, Producción y Empleados, como entre ellos.
- Se cierra con X, con C o abriendo otro panel lateral. No pausa; se refresca cada hora de juego.
- El trabajo no se da desde aquí: cada campo se trabaja desde su menú de puesto (clic derecho: Arar, Sembrar trigo,
  Cosechar), que ya lleva la línea del campo ([forja_interior.md](forja_interior.md)).

## 3. Jerarquía de información

Panel lateral (356×430), de arriba abajo:

1. **Calendario de siembra (8 días)**: una rejilla de 4×2 casillas, una por día desde hoy. Cada casilla:
   - «Hoy» o «Día N» (en negrita) y la estación;
   - por cada cultivo que se puede sembrar ese día, «Trigo → día N» (el día que estaría listo si se siembra ese día;
     «no» si no llegaría este año); una raya en otoño e invierno;
   - en dorado, «Campo A listo» el día que un campo sembrado madura;
   - en rojo, «Campo E: último día» el día antes de pudrirse uno listo.
2. **Campos**: una línea por campo, «Campo A · Crece: 2 de 4 · listo en 2 días» (los mismos textos que el menú del
   puesto: barbecho, arado con o sin época de siembra, creciendo, listo con los días para cosecharlo, podrido).
3. **Corral**: «Oveja ×4, Cerdo ×2 · 6 de 8 cabezas»; «Pienso de invierno en el almacén: N días»; «Cerdo: crías en N
   días» por cada pareja que cría; en rojo, «Sin pienso N días» si el ganado no comió.

## 4. Datos que lee (solo lectura)

| Qué | De dónde |
|---|---|
| Días, estaciones | `Clock.day`, `Clock.season` con `catalog.time` |
| Siembra de cada día | `data/crops/*.json` (`sow_seasons`) y `Fields.days_to_ready` con `sown_day` = ese día |
| Estado de los campos | `Fields.view` (`days_to_ready`, `days_left`) |
| Corral | `Herds.view` (`herd`, `heads`, `capacity`, `winter_feed_days`, `young_in`, `unfed_days`) |

`FarmPanel.strip()` devuelve la franja ya calculada (`[{day, season, sow {crop: día listo}, ready, last}]`); la
prueba `tests/test_patron_trades.gd` la comprueba contra `Fields.sow_preview`, el mismo cálculo del menú del puesto.

## 5. Pendiente

- Iconos por cultivo y animal en las casillas (hoy, texto); el corral con sus animales dibujados llega con el ciclo de
  PixelLab (04d 4.22.9 #4).
- Más cultivos: la rejilla ya enseña uno por línea, sin cambiar el panel.

# Mecánicas de economía: convenciones comunes

Lo que comparten los siete documentos de `docs/ui/mecanicas/` (forja_interior, produccion, almacen_y_personaje,
mercado_y_libro, empleados, mejoras, parcelas_y_construccion), para no repetirlo en cada uno.

> [!NOTE]
> Si la guía visual del kit (`docs/ui/README.md` y sus ficheros 00-03) fija otra cosa, manda la guía. Las medidas de
> aquí son provisionales hasta que el kit las cierre.

## Pantalla y zonas (960×540 lógicos, ×2 a 1080p)

```
 0                                                                          960
 ┌─ HUD superior (kit) ───────────────────────────────────────────────────────┐ 0
 │ retrato · oro · título · deuda · libro · reloj · velocidades               │
 ├────────────────────────────────────────────────────────────────────────────┤ 48
 │ grupo 1-2-3 (kit)                         barra del edificio (si dentro)   │ 56
 │ objetivo plegable (kit)                ┌── PANEL LATERAL ──────────────┐   │ 96
 │                                        │ 352 × hasta 420                │   │
 │            vista (mapa o interior)     │ x 600..952 · y 96..516         │   │
 │                                        │ (uno a la vez)                 │   │
 │                                        └────────────────────────────────┘   │
 ├────────────────────────────────────────────────────────────────────────────┤ 524
 │ línea de ayuda de controles (kit)                                          │ 540
 └────────────────────────────────────────────────────────────────────────────┘
```

- **Panel lateral**: todos los paneles de gestión de estas mecánicas (producción, almacén, empleados, mejoras,
  mercado, libro, parcela) se abren en la misma caja a la derecha. Abrir uno cierra el anterior. Así nunca tapan el
  puesto en el que trabaja el personaje (el interior se dibuja centrado-izquierda) ni se pisan entre sí.
- **Menú contextual** (clic derecho en un puesto o en una parcela): caja pequeña junto al cursor, nunca dentro del
  panel lateral. Se cierra con Esc, con clic fuera o al dar la orden.
- **Confirmación**: caja centrada de 280×120 sobre la vista, con el resumen en cifras y dos botones (*Confirmar* /
  *Cancelar*). Solo para lo caro o lo que no se deshace (construir, demoler, despedir a un leal, mejora, pagar la
  deuda dejando el oro por debajo de lo que se cobra mañana).
- Ninguno de estos paneles pausa el juego (GDD 4.1). La pausa es la del HUD.

## Rejilla y tamaños

- Rejilla de 4 px. Márgenes interiores del panel: 8 px. Separación entre filas: 4 px.
- Icono de objeto: 16×16 en listas (los 32×32 de Guild Renew reducidos a la mitad con vecino más cercano y
  repasados en el `pixelart_workbench`), 32×32 en las rejillas de inventario y en el detalle.
- Retrato: 32×32 en listas (reducción de los de 64×64), 64×64 en fichas.
- Fila de lista: 20 px de alto (icono 16 + 2 arriba y abajo). Fila doble (nombre + detalle): 28 px.
- Botón pequeño: 12 px de alto (9-patch `button_*` del tema). Botón normal: 16 px.

## Colores con significado (biblia, paleta UI)

| Significado | Color | Dónde |
|---|---|---|
| Positivo, hecho, cabe, ganas | `#7ec87e` | importes +, check de requisito, barra de lealtad alta |
| Negativo, falta, pierdes | `#c85050` | importes −, motivo de rechazo, requisito que falla |
| Atención, oro, seleccionado | `#c8a84e` | filete del elemento activo, ventana del toque de maestro, precio |
| Texto sobre sección oscura | `#d4b896` | texto normal |
| Hueco vacío | `#1a1209` | casillas de inventario libres, barras vacías |

Nunca solo color: cada estado lleva también icono o texto (daltonismo, capturas en gris).

## Iconos que se reutilizan de Guild Renew (`~/Code/guild/assets/sprites/ui/`)

| Uso | Icono |
|---|---|
| Oro | `icons/icon_oro` |
| Objetos | `icons/icon_<objeto>` (hierro, carbon, lingote_hierro, espada, martillo, armadura, madera, piedra…) |
| Estados de trabajo | `icon_working`, `icon_idle`, `icon_in_progress`, `icon_pending`, `icon_completed`, `icon_warning` |
| Bloqueado | `icon_locked` |
| Bucle | `icon_loop` |
| Ramas de mejora | `icon_rama_<rama>` (8) |
| Construcción | `icon_build_mode`, `icon_demolish`, `parcels/parcel_<tipo>` (64×32) |
| Equipo vacío | `slot_empty_herramienta`, `slot_empty_ropa`, `slot_empty_accesorio` |
| Libro, contrato | `icon_libro`, `icon_contrato` |
| Día / noche | `icon_sun`, `icon_moon` |

Los que faltan se piden en cada documento como **pieza de kit pendiente** (no se dibujan aquí).

## Motivos de rechazo

Toda acción que el sim rechazaría se pinta deshabilitada **con el motivo escrito debajo o al lado** (no solo en el
tooltip), en `#c85050`, en una línea corta. El texto sale de `reason.<código>` (`SimQuery.reason_text`) con sus
parámetros: «Falta 1 lingote», no «missing_inputs». Si el motivo tiene arreglo en otro panel, el texto lleva un
enlace subrayado que lo abre («Necesita *Taller de maestro* → Mejoras»).

## Cifras

- Oro siempre con el icono y sin decimales. Diferencias con signo y color: `+42`, `−20`.
- Duraciones en horas de juego como hoy (`SimQuery.hours_label`): «3 h 54», «12 h», «1 d 6 h». Nunca segundos reales.
- Las cifras salen del sim o de `data/`; la UI no calcula reglas. Lo que se pide al sim y no existe aún va en la
  sección 7 de cada documento como **consulta nueva** (se añade en el hito que la implemente, no en esta rama).

# <Pantalla o mecánica> · diseño de interfaz

> Dueño: <worker> · Estado: borrador | revisado | aprobado · Fecha: AAAA-MM-DD
> Guía de estilo: [00_lenguaje_visual.md](00_lenguaje_visual.md) · Zonas y reglas del HUD: [01_hud.md](01_hud.md)

## 1. Para qué sirve
Qué pregunta del jugador responde, en sus palabras («¿me da para pagar la deuda?», «¿quién está parado y por qué?»).
Una o dos frases; si responde a más de tres preguntas, probablemente son dos pantallas.

## 2. Cómo se abre y se cierra
- Abrir: tecla, clic, desde dónde (HUD, menú de puesto, aviso…).
- Cerrar: Esc, botón ×, clic fuera (solo si no hay nada a medio hacer), la misma tecla otra vez.
- Pausa: ¿pausa el juego? Por defecto no (GDD 4.1: solo el menú de pausa pausa). Si se abre en pausa, qué pasa con las
  órdenes (pausa activa: se encolan).

## 3. Jerarquía de información
1. Lo que se ve primero (la respuesta a la pregunta del punto 1).
2. Lo segundo (contexto para decidir).
3. A demanda: tooltip, desplegable o pestaña.

## 4. Acciones y sus estados
| Acción | Orden que emite | Normal | Deshabilitada (motivo visible = `reason` de Orders) | ¿Confirmación? |
|---|---|---|---|---|
| … | `{"type": …}` | … | «Te faltan 12 de oro» | Solo si es cara o irreversible |

## 5. Estados especiales
- Vacío (sin datos todavía): qué se enseña y qué invita a hacer.
- Bloqueado por título o hito: candado + requisito.
- Error / imposible: mensaje del `reason`.
- Primera vez: pista del objetivo de inicio o ayuda (F1).

## 6. Maqueta
Wireframe ASCII y PNG hecho con el kit (`python3 tools/ui/maqueta.py docs/ui/maquetas/src/<id>.json`):

```
┌──────────────────────────────┐
│ Título                    [×]│
├──────────────────────────────┤
│ …                            │
└──────────────────────────────┘
```

![<id>](maquetas/<id>.png) · versión ×2: `maquetas/<id>_x2.png`

## 7. Datos
- Lee de `sim/`: campos y funciones reales (`WorldState.…`, `Ledger.…`).
- Emite: órdenes (`Orders.apply` con `{"type", "actor", …}`) y señales de `Events` que escucha.

## 8. Sonido y feedback
- Eventos de `data/audio.json` que usa (`ui_click`, …) y los que faltan (márcalos «falta»).
- Feedback visual: animación al abrir, al confirmar, al fallar.

## 9. Diferencias con lo que hay y tareas
Qué hay hoy en `game/ui/<panel>.tscn` y qué cambia. Lista de tareas pequeñas (una tarde cada una como mucho):
- [ ] …

## 10. Criterios de aceptación
Comprobables por alguien que no ha leído el documento:
- [ ] Con <situación>, al <acción> se ve <resultado> (captura `docs/novedades/<id>.png`).

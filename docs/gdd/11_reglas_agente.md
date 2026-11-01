## 11. Reglas para el agente (semilla del `CLAUDE.md` del repo nuevo)

```markdown
# Guild Renew — reglas del proyecto

## El diseño manda
- El diseño vive en docs/gdd/ (este documento partido por secciones). Si lo jugado choca con el diseño, gana lo jugado:
  se cambia el diseño en el mismo commit y se apunta en docs/decisiones.json.
- Lo marcado [Gate] necesita visto bueno del owner. Lo que no esté definido, se pregunta: no se inventan mecánicas.
- Ids en inglés y snake_case. Textos del juego en ES (y EN) vía i18n/. Documentos internos en español.

## Arquitectura (no romperla)
- sim/ tiene todas las reglas, es determinista y no usa nodos. game/ solo dibuja y da órdenes.
- Las cifras viven en data/. Toda orden lleva actor_id. Un interior es una vista.
- Guardar/cargar funciona siempre: todo estado nuevo se serializa y tiene su test de ida y vuelta.

## Godot
- Binario fijado (4.7.x). Solo sintaxis de Godot 4. Tipado estático. Sin ternario ?: (usar `a if c else b`).
- Escenas 2D extienden Node2D. UI en .tscn con %UniqueName, nunca rutas $A/B/C.
- Nunca get_image() sobre texturas en el juego (en el exportado puede no dar nada).
- Logs solo en debug con prefijo [Sistema].

## Rituales (antes de dar algo por hecho)
- tests/run_tests.gd · tools/validate_content.py · arranque sin ventana y con escenarios · sim_runner si tocas reglas
- smoke con capturas (mirarlas) como última comprobación, en `grimoire heavy`.

## Cuaderno vivo
- Cada función terminada: entrada al principio de docs/novedades.json con capturas reales; luego python3 tools/cuaderno.py.
  Sin entrada con capturas, no está entregada.

## Forma de trabajo
- Un hito a la vez. Manager + como mucho 4 subgrims, cada uno en su zona de ficheros; los subgrims no hacen commit.
- Procesos con ventana o export: grimoire heavy. Nunca pkill -f general.
- Créditos (PixelLab, ElevenLabs, fal): saldo antes y después en el MANIFEST.
- No añadir features, refactors ni "mejoras" no pedidas. Respuestas cortas y en español.
```

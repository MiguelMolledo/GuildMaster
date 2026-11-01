## 0. Cómo usar este documento

**Para Miguel:** las secciones 1-3 resumen qué es el juego y qué se aprendió del primer intento. La 4 es el diseño de juego completo y consolidado. La 5-6 es la arquitectura técnica nueva. La 10 es el plan por hitos. La 12 recoge las decisiones tomadas (2026-11-01) y las que siguen pendientes.

**Para el agente (Opus 5.5):**

1. Lee primero las secciones 2 (lecciones), 5 (arquitectura) y 11 (reglas de trabajo). Son obligatorias antes de escribir código.
2. Trabaja **hito a hito** (sección 10). No empieces un hito sin cerrar el anterior con sus criterios de aceptación verificados.
3. La sección 4 es la fuente de verdad del diseño. Si algo no está definido ahí, **pregunta**: no inventes mecánicas.
4. Los números (precios, probabilidades, duraciones) son valores iniciales para balancear después. Van en datos (JSON / `.tres`), nunca escritos a mano en el código. Los marcados **[balance]** se ajustan expresamente con bots contra las dianas de `data/targets.json`. Todas las duraciones de referencia están en la tabla de 4.1.
5. Las secciones marcadas **[POST-MVP]** o **[POST-EA]** no se implementan hasta que se pida expresamente, pero la arquitectura no debe impedirlas.

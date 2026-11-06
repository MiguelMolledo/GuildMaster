# Pasada de jugador por la interfaz · primer año (2026-11-06)

Partida por defecto: Vilarrasa, herrero, Normal, con tutorial, semilla fija 11. Jugada solo con ratón y teclado
inyectados, en 15 bloques cortos y en una sola sesión, como la jugaría un novato:
- los cuatro capítulos de lo básico;
- los objetivos del panel;
- las cartas «Nuevo» que van llegando;
- medias jornadas de oficio: forjar espadas, venderlas, aceptar encargos, comprar hierro con recado, contratar al
  aprendiz cuando se abre y pagar la deuda si sobra oro.

Con ventana, una a la vez por `grimoire heavy`. Se repite con:

```bash
python3 tools/verifica/jugador.py --window        # reports/jugador/<fecha>/: capturas por bloque y ritmo.json
python3 tools/verifica/jugador_bloques.py         # regenera los bloques 06-15
```

> [!WARNING]
> El novato acaba arruinado. Siguiendo el tutorial y los objetivos no llega a pagar la deuda el día 8. Le dan una
> prórroga a 250, y el día 10 tiene 166 de oro. En otras dos pasadas, con un guion más torpe, la ruina («Fin de la
> partida») llegó el día 10.

> [!NOTE]
> **Repetida con el equilibrio Eq1-15 dentro** (main dcf7dc86, misma semilla y misma ruta): sigue la ruina el día 10.
> En 10 días, ventas 852 + encargos 153 frente a compras 562, recados 109, mantenimiento 180 y sueldo 56. El oro
> máximo es 209 y al embargo le faltan 71.

> [!NOTE]
> **Repetida con forja #14-19/#27 dentro** (main c03163e9, misma semilla y misma ruta):
> - La espera de 41-43 s al final de la Forja viva ya no aparece (#18 arreglado).
> - El novato sigue sin pagar: el oro no pasa de 198 frente a los 200 del día 8. Prórroga a 250 y llega al día 10
>   con 196.
> - En 10 días: ventas 772 + encargos 153 frente a compras 438, recados 85, mantenimiento 180 y sueldo 56.
>
> El #1 sigue abierto para equilibrio.

## Ritmo (03b §3b.6: mediana < 30 s entre decisiones, máximo < 60 s)

Tramos sin decisión, en segundos reales a la velocidad que llevaba el jugador (×2 o ×4; 1 día = 5 min a ×1):

| Tramo | Segundos | Dónde |
|---|---|---|
| Esperar dos espadas en el yunque | ~24 (×4) | cada media jornada |
| Esperar dos lingotes | 8-16 | cada media jornada |
| **Forja viva: «La pieza termina sola…»** tras templar | **41-43 (a ×1)** | las dos espadas a mano |
| La noche con el mercado cerrado (21:00-06:00) | ~28 (×4) | todas las noches |
| Esperar espadas de madrugada (día 10) | 53 | una vez |

La mediana cumple la diana. El máximo de 60 s se cumple, pero la Forja viva y la noche se quedan rozando el límite.

## Hallazgos, por gravedad

### Bloquea o arruina la partida

| # | Qué | Dueño | Estado |
|---|---|---|---|
| 1 | **El novato no paga la deuda.** En 10 días: ventas 712 + encargos 217 frente a compras 494, recados 96, mantenimiento 180 y sueldo 56. El oro nunca pasa de 214 (pagar 200 dejaría sin hierro). Prórroga a 250 y embargo o ruina el día 10. La mejora de 300 de oro no se abre en todo el año. | **equilibrio** | propuesto: revisar el margen de la espada (73 frente a ~32 de material), el recargo del recado (+20 %) y el plazo de la deuda; que el bot `novice` juegue esta misma ruta |
| 2 | Tras «Deuda y cuentas», el tutorial ofrecía **«Siguiente capítulo: Empleados»** con Empleados aún cerrado (150 de oro): el botón no existe y el capítulo se atasca. Encadenaba todos los capítulos en orden (cortejo el día 1). | UI | **arreglado**: solo se encadena lo básico (primeros pasos, producir, vender, deuda); los demás llegan con su carta «Nuevo» o desde F1, y uno cuya mecánica no se ha abierto dice «Más adelante» |
| 3 | **La tarjeta del tutorial tapaba los botones que pedía** (en el puesto de Recursos, el «+» y el «Enviar a…»). | UI | **arreglado**: se aparta de todo el panel que contiene el objetivo, no solo del objetivo |
| 4 | **La tarjeta del tutorial y la pila de cartas** (pregón de la fiesta, «Nuevo: …») se tapaban una a otra: las dos van al lado del panel abierto. | UI | **arreglado**: mientras el tutorial guía, la pila se aparta (como con un modal) y vuelve después, sin perder su tiempo |
| 5 | **Una carta apartada que se volvía a enseñar se quedaba visible en (0,0)**, encima del objetivo y con la cinta fuera de pantalla. | UI | **arreglado** |
| 6 | **«Ver capítulo» de una carta abría un capítulo ya hecho** (la carta de los encargos, guardada en la pila, volvía a empezar «Vender»), o uno que aún no se puede jugar (la del mostrador lleva a Mejoras, que pide 300 de oro). | UI | **arreglado**: solo se ofrece si el capítulo se puede jugar y no se ha visto; el botón se quita si deja de valer |

### Confunde o no se sabe qué hacer

| # | Qué | Dueño | Estado |
|---|---|---|---|
| 7 | **El capítulo «Vender» nunca pide vender**: enseña la lista con precios y pasa a «Sal a la calle». | UI (tutorial) | **arreglado**: nuevo paso «Vende la espada: Vender en su fila» |
| 8 | «Sal a la calle (Salir o Esc)»: **el primer Esc solo cierra el mostrador** y el paso no avanza. | UI | **arreglado**: el texto dice «cierra el mostrador y Salir (o Esc dos veces)» |
| 9 | El tutorial decía **«Esto es Pueblo-calle»** (el nombre de trabajo del mapa); el mapa de la región la llama Vilarrasa. | UI | **arreglado**: el tutorial toma el nombre del mapa de la región |
| 10 | La barra del taller: el tutorial **nombra Empleados (E) y Mejoras (M), que aún no están**. | UI | **arreglado**: «…Producción (P), Almacén (A) y Salir (Esc). Empleados y Mejoras salen cuando los abras» |
| 11 | La meta pide **«Contrata a un aprendiz»**, pero el primer candidato de la lista era un oficial (20 al día frente a 7). | UI | **arreglado**: los candidatos salen del más barato al más caro |
| 12 | **La cola parada por falta de hierro apenas se ve**: la barra cortaba «Empleados parados: Faltan materiales en el almacén ·…». | UI | **arreglado**: la frase se acorta hasta caber y la entera queda en el tooltip |
| 13 | **El reloj cortaba el suceso y la fiesta** cuando coinciden: «a 4 d Fi». | UI | **arreglado**: la fiesta ocupa lo que mide y el suceso usa formas cortas |
| 14 | El objetivo del encargo de calidad aún dice **«haz clic mientras parpadea (toque de maestro)»**; el toque de maestro ya no existe. | forja | propuesto: cambiar `objective_how.quality_contract` y los demás textos que aún lo nombran (`help.inside_touch` de la ayuda F1, `tutorial.hint.master_touch`, `tutorial.produce.touch`) |
| 15 | La carta **«Nuevo: la deuda del año»** llega el día 8, con un día de plazo, cuando la deuda es la meta desde el día 1. | forja (ritmo 03b) | propuesto: adelantar el desbloqueo `debt` (o quitarle la carta) |
| 16 | La carta **«Nuevo: el mostrador» (día 2) lleva a Mejoras**, que no se abre hasta los 300 de oro: el mostrador no se puede comprar antes. | forja (ritmo 03b) | propuesto: que el desbloqueo del mostrador vaya con las mejoras, o abrir solo el mostrador antes |
| 17 | **«Objetivo cumplido» salía dos veces** con el mismo texto: el objetivo y la meta abierta del mismo id avisan cada uno. | forja (OpenGoals) | **arreglado en la UI** (un mismo aviso no sale dos veces); propuesto en origen: que OpenGoals no repita el aviso de Objectives |

### Aburre (03b)

| # | Qué | Dueño | Estado |
|---|---|---|---|
| 18 | **Forja viva: 41-43 s sin decisión** tras templar («La pieza termina sola…»). Además baja la velocidad a ×1 y no la devuelve. | forja | propuesto: acabar la pieza a la velocidad que llevaba el jugador o con un «Seguir» |
| 19 | **Las noches**: 9 horas de mercado cerrado, ~28 s a ×4 sin nada que vender ni comprar. «Saltar hasta…» existe, pero nada lo enseña. | forja (ritmo) / UI | propuesto: una pista del tutorial la primera noche («Saltar hasta el amanecer») |
| 20 | **Cinco «¡Pelea!» urgentes en dos días**: los urgentes se quedan hasta un clic y llenan la esquina. La carta «Pelea en la calle» se queda días esperando respuesta. | fiestas / vida | propuesto: peleas como «aviso» (no urgente) y su carta con caducidad |

### Se ve mal

| # | Qué | Dueño | Estado |
|---|---|---|---|
| 21 | El pie de la tarjeta del tutorial («Retroceso: repetir») se salía por el borde. | UI | **arreglado** (se maqueta otra vez cuando sus líneas ya saben su alto) |
| 22 | En el mostrador, con una sola pieza, salía «Vender 1 · 73» dos veces. | UI | **arreglado** |
| 23 | Una carta que crece después de colocarse **se salía de la pila por abajo**, bajo la barra de selección. | UI | **arreglado**: espera sitio |
| 24 | El cartel «SE VENDE» con la letra por defecto de Godot. | UI | **arreglado** (letra del pueblo) |
| 25 | **Con el zoom ×2, los rótulos del pueblo se amontonan** («Enseres», «Ayuntamiento», el nombre, «Tablón de encargos»), y los mensajes flotantes («Suero, que viene a comerciar…») cruzan la pantalla cortados por los paneles. | UI | **pendiente**: contraescalar los rótulos con el zoom y acotar el ancho de los mensajes |
| 26 | Nombres de fiesta largos cortados en la cinta («Pregón: San Miguel y la vendim…»); «8 × Comida preparada» cortado en el tablón; los símbolos de las burbujas («!», «X», «+») con poco contraste. | UI | **pendiente** |
| 27 | Los botones de golpe y temple de la Forja viva salen cortados («Fuerte (1)», «Agua (1)»…). | forja | propuesto |

## Lo que se arregló (UI) y dónde

- Tutorial:
  - `data/tutorial.json`: la lista `basics`.
  - `data/tutorial/market.json`: el paso de vender.
  - `staff.json` y `upgrades.json`: piden su desbloqueo.
  - `game/ui/tutorial/*`: la tarjeta evita el panel del objetivo y la pila; el pie se maqueta otra vez; el nombre de
    la villa.
- Pila de cartas (`game/ui/page_card.gd`): se aparta mientras guía el tutorial, no deja visible una carta apartada y
  una carta que crece espera sitio.
- `game/ui/forja/unlock_card.gd`: «Ver capítulo» solo cuando vale.
- HUD (`hud.gd`, `hud.tscn`): el reloj, la barra de selección y un mismo aviso una sola vez.
- `market_panel.gd`: un solo «Vender» con una pieza.
- `staff_panel.gd`: los candidatos del más barato al más caro.
- `plot_layer.gd`: la letra de «SE VENDE».
- Conductor:
  - `start {"keep": true}`.
  - `click` con `times`.
  - Minutos de juego y velocidad por paso.
  - `q.tut()`, `q.tut_text()`, `q.unlocked()` y `q.chapter_done()`.

## 12. Decisiones

### 12.1 Decisiones tomadas (2026-11-01)

El owner aprobó el 2026-11-01 las recomendaciones de la revisión. Se copian a `docs/decisiones.json` (`tomadas`).

| # | Tema | Decisión | Dónde se aplica |
|---|---|---|---|
| **D1** | Cómo envejece la gente | **(b) Año de calendario corto: 4 estaciones × 2 días = 8 días (40 min reales).** Un único "año" para edad, mandatos y estaciones. Una generación (~25 años) ≈ 17 h. Se comprueba con el bot `dynasty`. | 4.1 (y tabla de duraciones), 4.2.5, 4.7.2, 4.10.3, 4.11.5, 4.12, 4.13, 5.4, 10 |
| D2 | Resolución interna | 960×540 escalado ×2 entero. La UI se diseña a esa escala. | 5.1, H1 |
| D3 | Movimiento del personaje | Por casillas desde el sim para todos, interpolado en la vista. Sin `NavigationAgent2D`. | 5.4, H1 |
| D4 | Duración del día | 5 min reales, con velocidades ×2 y ×4 y pausa. | 4.1, H1 |
| D5 | Puntos libres al crear personaje | 5. | 4.2.2, H3 |
| D6 | Ranuras de guardado | 3 + autoguardado diario. | 5.8, H0 |
| D7 | Dificultad | Sí, 3 niveles. | 4.23 |
| D8 | Transporte con coste | Post-MVP. En el MVP se carga a mano (peso) o se paga un recado de entrega (4.5.7). | 4.3.4, 4.5.7 |
| D10 | Estilo de ciudad | **Provisional:** A (villa de mercado orgánica) con río y puerto (C) para el EA; E para la rebanada vertical. La **Gate** definitiva se mantiene tras la prueba de PixelLab (9.4). | 9.4, 9.5, H1, H13 |
| D11 | Entradas al interrumpir una receta | Se devuelven. | 4.4.3, H2 |
| D12 | Mantenimiento diario de edificios | En el MVP (desde H3). | 4.6.3, 4.19, H3 |
| D13 | Idiomas | ES + EN desde H0 vía `i18n/`. | 5.2, H0 |
| D14 | Escala de precios | Rebalancear con bots en H5 (mejoras previsiblemente ×5-×10). | 4.8, 4.19, H5 |

**Diseño nuevo aprobado el mismo día** (huecos detectados en la revisión): herrero rival desde H3 (4.5.5), encargos (4.5.6), recado de entrega (4.5.7), trabajo a mano con modo y toque de maestro (4.4.5), condiciones de inicio y deuda (4.16), objetivos de dinastía y puntuación (4.17), libro de cuentas y avisos (4.18), fuentes y sumideros de oro (4.19), microeventos (4.20), IA de familias rivales (4.21), sistemas propios de las otras clases (4.22), rutina programable y pausa activa (4.10.8, 4.1), identidad visual de la familia (4.10.9), kit modular de interiores (4.6.4, 9.3), hermanos rivales [POST-MVP] (4.10.4) y recálculo de todas las duraciones con D1(b) (tabla de 4.1).

### 12.2 Pendientes

| # | Decisión | Opciones | Recomendación |
|---|---|---|---|
| D9 | Nombre del mapa EA | Bellcaire | Owner, 2026-11-04: el mapa EA es la capital de la región de Valldaura (P-R1). |
| D15 | Mantenimiento impagado (D12 no dice qué pasa si no hay oro) | (a) Se acumula como deuda con la ciudad y se cobra en cuanto haya oro. (b) Además, tras N días impagados el edificio pasa a Dañado. (c) No se puede quedar a deber: se embarga mercancía. | (b) con 3 días [balance]: la deuda se ve en el libro y el castigo llega con aviso. |
| D16 | ¿Las ventas en mostrador bajan la demanda del mercado? (afecta a la competencia con el rival, 4.5.5) | No / Sí, igual que en el mercado / Sí, a la mitad | A la mitad (−0,025 por unidad): el mostrador sigue siendo mejor que el mercado sin ser un hueco sin competencia. |
| D17 | Escala de los edificios con D2 | Mantener escala 1,6 (píxeles no enteros, choca con D2 y con el feedback "192 px a 1,6") / generar los edificios ya a su tamaño final (~300 px) y dibujarlos a escala 1 / generarlos a ~150 px y escalar ×2 | Tamaño final a escala 1: conserva el ratio edificio:personaje ≈ 4,5:1 sin deformar píxeles. Confirmar con una captura de prueba en H1. |
| D18 | ¿La ruina por la deuda inicial termina la partida? (4.16) | Sí (final de partida) / No: se pierde la Forja y se sigue como asalariado | Sí, con los avisos de 2 y 1 días, la prórroga de 1 estación y la deuda menor en Fácil: da tensión al primer año sin ser una trampa. |
| D19 | Cierre voluntario de la dinastía (4.17) | Permitido (pantalla final y puntuación cuando el jugador quiera) / Solo Game Over y ruina | Permitido: las partidas largas necesitan un final elegido para ver la puntuación. |
| P-R1 | Región en vez de un solo mapa EA (petición del owner, 2026-11-04: varias ciudades y pueblos para desbloquear viajes y tratados mercantiles) | (a) La **capital** es el mapa EA de 80×80 con 6 zonas (A + C, D10); los demás asentamientos son mapas de 32×32 a 48×48; la villa `town_e` sigue como rebanada vertical; solo la ciudad de casa se simula entera y las demás de forma abstracta. (b) Todos los asentamientos del mismo tamaño. (c) Un solo mapa y las demás ciudades solo como destinos abstractos, sin mapa | **(a)** · **propuesta, pendiente del owner**: un solo mapa grande que producir y los demás al coste de un pueblo del constructor. Diseño completo, preguntas O-R1 a O-R10 y nombres en `09b_region.md` **Aprobada por el owner (2026-11-04)**, con O-R1–O-R10. |

## 1. Visión

### 1.1 Qué es

Guild Renew es un **simulador de vida y dinastía medieval** en 2D isométrico pixel art. El jugador llega como un don nadie a una ciudad centroeuropea del siglo XIV. A lo largo de varias generaciones levanta negocios, contrata empleados, se casa, tiene hijos que heredan, sube en la escala social, ocupa cargos políticos y se enfrenta a familias rivales y a los tribunales.

Referencias: **The Guild II** (profundidad sistémica) y **The Guild 3** (presentación), con la estética de **Graveyard Keeper** / **Stardew Valley** (pixel art 16-bit SNES).

### 1.2 Pilares de diseño

| # | Pilar | Qué significa en la práctica |
|---|---|---|
| 1 | **Capas simultáneas** | Economía, familia, política e intriga ocurren a la vez y en tiempo real; una decisión en una capa afecta a las demás (p. ej. un juicio te puede quitar un edificio). |
| 2 | **Mundo vivo** | Los NPC tienen rutinas, trabajan, socializan, se casan, compiten por parcelas y votan. La ciudad sigue funcionando aunque no la mires. |
| 3 | **Dinastía** | El protagonista es la familia, no una persona. Morir no es perder: es heredar. Perder es quedarse sin heredero. |
| 4 | **Gestión desde dentro** | Los negocios se gestionan entrando en ellos (vista interior isométrica), viendo a los empleados trabajar en sus puestos. |
| 5 | **Narrativa emergente** | Cada partida cuenta una historia distinta a partir de los sistemas. [POST-EA] Claude API como cronista y diálogo. |

### 1.3 Plataforma y alcance

- **Plataforma:** PC (Windows / macOS), Steam Early Access.
- **Objetivo del Early Access:** 1 mapa, una hora de juego sólida con las mecánicas core funcionando de punta a punta. El arte se puede iterar; el bucle de juego tiene que enganchar.
- **Estrategia del MVP (decisión ya tomada):** todos los sistemas core se construyen primero **solo con la clase Artesano y la profesión Herrero (Forja)**. El resto de profesiones se añaden después sobre todo como *contenido* (datos). Pero no todo es dato: Pícaro, Erudito y Patrón necesitan además sistemas propios (combate, robo y guardias; servicios y préstamos; cultivos por estación), esbozados en 4.22 y que se diseñan en detalle antes de H12. La arquitectura les reserva el hueco desde el principio (receta de tipo servicio, préstamo como entidad, combate como orden: 5.3 y 5.5) para que añadirlos no obligue a rehacer nada.

## 3. Alcance y bucle de juego

### 3.1 Los cuatro bucles

| Escala | Duración real aprox. | Qué hace el jugador |
|---|---|---|
| **Minuto** | 10-60 s | Mueve personajes, compra/vende, elige recetas, trabaja en un puesto, habla con NPC. |
| **Día** | 5 min | Aprovisiona materias primas (a mano o con recado), ajusta la cola de producción, cumple encargos, cobra, paga salarios y mantenimiento, revisa el libro de cuentas, corteja, atiende microeventos. De noche: taberna, intrigas, descanso. |
| **Estación / año** | 10 min (estación de 2 días) / 40 min (año de 8 días), D1(b) | Mejora edificios, construye o compra el siguiente negocio, sube de título, hace campaña (1 estación) y se presenta a cargos (mandatos de 1-4 años), reacciona a eventos estacionales. El primer año, devolver la deuda inicial. |
| **Generación** | ~17 h (25 años de juego) | Se casa, tiene hijos, los educa, designa heredero, muere y continúa con el heredero. Persigue metas de dinastía (4.17). |

### 3.2 Bucle core del MVP (lo que debe ser divertido primero)

```
Comprar hierro y carbón en el mercado
        ↓
Llevarlo al almacén de la Forja (a mano, o con recado pagando un sobrecoste)
        ↓
Producir (tú mismo en el horno/yunque, o tus empleados con la cola)
        ↓
Vender (en el mercado, en el mostrador de la Forja o a un NPC por encargo) compitiendo con el herrero rival
        ↓
Oro → devolver la deuda inicial → mejoras de la Forja / contratar / segundo negocio / título
        ↓
Reputación + título → más edificios, cargos, mejor matrimonio
        ↓
Familia → más manos controlables → heredero → siguiente generación
```

### 3.3 Fases del producto

| Fase | Contenido | Criterio de salida |
|---|---|---|
| **Rebanada vertical** (hitos 0-5) | Mapa pequeño, Forja completa, mercado con herrero rival, condiciones de inicio con deuda, encargos, recado de entrega, libro de cuentas, empleados, mejoras, guardar/cargar. | Se juegan 3 días seguidos ganando dinero sin tocar el editor ni la consola. |
| **MVP** (hitos 6-11) | Construcción con competencia de la IA rival, ciudad viva y microeventos, familia, herencia, rutina programable y final de partida, reputación y títulos, cargos y elecciones, tribunal. Solo Artesano. | Una partida de 2 h (3 años de juego) ocupa un cargo menor y ve nacer un hijo; la herencia se juega desde el escenario del fundador anciano (H11). |
| **Contenido EA** (hitos 12-14) | Resto de clases y profesiones (18) con sus sistemas propios (combate y robo, servicios y préstamos, cultivos), 7 cadenas de producción, estaciones y eventos, IA familiar, 5 familias rivales, mapa 80×80. | Las 4 clases son jugables; 5 familias rivales compiten. |
| **Early Access** | Arte final, audio, tutorial, balance, Steam. | Ver FASE 12-15 del pipeline. |

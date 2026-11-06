## 4.6.5 Interiores II: biblioteca de props, habitaciones, desniveles y clientes

> El owner (2026-11-04): «usar las referencias para generar props, e ir generando props y props hasta que tengamos un
> montón; después podremos usar las configuraciones necesarias para hacer los interiores como queramos. Me imagino
> interiores con desniveles, con escaleras, con habitaciones para dormir, cocinar o entrar al almacén, una parte con
> un mostrador, una barra grande para atender, donde esperen los clientes para recoger o hacer pedidos. Cuando entres
> en una habitación, la pared y la puerta tienen que volverse invisibles para ver por dónde se mueve el personaje.
> ¿Se mueve o se teletransporta a los puntos de acción? Me gustaría que entrasen clientes, aunque de momento se
> teletransporten: sentarse en la mesa con una exclamación para pedir una ración de comida, o en el mostrador para
> comprarte una espada».

Amplía 4.6.4 (interiores con kit modular). El sim no cambia sus reglas: lo nuevo es cómo se **monta** y se **ve** un
interior, y dónde se colocan los personajes que el sim ya tiene (empleados, clientes del mostrador, clientes de la
taberna).

### 4.6.5.1 La biblioteca de props

El camino es el que propone el owner: **muchas piezas sueltas, bien catalogadas**, y los interiores se componen con
ellas.

**Decisión del owner (2026-11-05), tras ver el piloto de la forja:** la **mezcla** de `docs/arte/interiores.md` (camino C).
Cada sala tiene un **fondo pintado** con fal sobre una plantilla de su geometría exacta: suelo, las paredes del
fondo, la puerta, lo que cuelga de ellas y la luz de base. **Encima** van como piezas sueltas todo lo que tiene altura y
todo con lo que se interactúa: puestos, mostrador, expositor, mejoras, atrezo de pie y escaleras. Por último, las
capas de luz y partículas. «Lo importante es que case la estética» (owner). Por eso:

- **Un fondo por sala y por planta**, no uno por edificio. Las paredes **entre salas** son piezas propias, no van en
  el fondo, para que puedan volverse transparentes (4.6.5.3). La plantilla de cada sala la saca el montador de
  4.6.5.2 a partir de los datos del interior, y el fondo se pinta sobre ella.
- **Mismas reglas para fondo y piezas:** la misma paleta (48 colores por interior, sacados del fondo), la luz del mismo
  lado, el mismo grosor de contorno y la misma escala de píxel (bloques de 6-8 en image2pixel, escala B). Una pieza que
  no case se repinta con el fondo como referencia.
- **Biblioteca de props:** sigue siendo el objetivo (abajo), pero para las piezas sueltas y para el atrezo que las
  mejoras añaden. Lo plano va en el fondo.
- **Mejoras que cambian la sala** (suelo de piedra, tapices): una pieza plana encima del fondo o, si cambia todo, un
  segundo fondo que la mejora enciende.
- **Personajes:** son lo que menos casa hoy con los fondos (tienen menos detalle). Cuando vuelva PixelLab (15 de
  noviembre), toca revisar su detalle y su paleta frente a los fondos.


- **De la referencia a la pieza:** para cada render de referencia (assets/art/interiors/_referencias/) se sacan las
  piezas que salen en él, como se hizo con las fachadas: fal/edit con la referencia recortada, fondo plano, recorte
  local y reducción a la paleta, a la escala del juego y con la proyección 2:1.
- **Catálogo** (`data/props/interior.json`, que exporta una herramienta desde `assets/inventario.json`). Cada pieza
  tiene:
  - id y categoría;
  - huella en casillas (1×1, 2×1…) y orientación (las dos diagonales; la otra se saca con espejo si se puede);
  - ancla (los pies) y altura (para ordenar el dibujo y para saber si tapa a un personaje);
  - si se puede pisar o no, y si se puede poner contra la pared o encima de otra (una jarra sobre una mesa);
  - etiquetas de oficio y de estilo (pobre, común o rico), para que el montador elija.
- **Categorías y primer objetivo (unas 150 piezas):**
  - estructura: suelos (tablas, piedra, tierra, alfombra), paredes con vigas, ventanas y puertas, escaleras,
    barandillas y tarimas;
  - muebles: mesas, bancos, sillas, camas, arcones, estanterías, mostradores, barras;
  - del oficio: fragua, yunque, banco de carpintero, telar, mesa de corte, bloque de cantero;
  - contenedores: toneles, cajas, sacos y cestas;
  - luz: velas, candiles, la chimenea y el fuego de la fragua (con su luz cálida por capas);
  - atrezo pequeño: herramientas colgadas, jarras, platos, rollos de tela, lingotes, virutas, ristras, hierbas;
  - textiles y adornos: tapices, escudos, cortinas.
- **Cuando PixelLab vuelva** (15 de noviembre), las piezas que necesiten varias direcciones o animación (fuego,
  fuelle, telar) se rehacen con PixelLab.

### 4.6.5.2 Montar un interior: habitaciones, niveles y escaleras

Cada interior es un fichero de datos (`data/interiors/<edificio>.json`), no una escena hecha a mano:

- **Habitaciones** (rectángulos o formas en L sobre la rejilla), cada una con su tipo:
  - `taller`: los puestos del oficio;
  - `tienda`: el mostrador y la zona de clientes;
  - `almacen`: lo que se ve del almacén;
  - `cocina` y `dormitorio`: la vivienda;
  - `salon`: la taberna;
  - `despacho`.
- **Paredes y puertas** entre habitaciones, con su pieza; las puertas cuentan para la navegación.
- **Niveles:**
  - **desniveles** de un escalón dentro de una planta (una tarima del mostrador, el foso de la fragua), que se
    salvan andando;
  - **plantas**: sótano, planta baja y planta alta (O-I1, owner), unidas por **escaleras**. El sótano es para la
    bodega de la taberna, el almacén frío y, cuando llegue el Pícaro (4.22), la **guarida**: una **jaula** para los
    secuestrados (4.24.5 y 4.22.6.6) y el escondite del **contrabando** (mercancía robada, `@stolen`, 4.22.6.4),
    con trampilla oculta (una inspección puede encontrarla).
- **Puestos y puntos de acción** con su sitio:
  - los puestos del sim (horno, yunque, barra, cocina, camas);
  - los **sitios de clientes**: cola del mostrador, mesas, sitios de espera y camas.
- **Decoración:** piezas de la biblioteca colocadas a mano o por reglas («llena las paredes del almacén de
  estanterías», «atrezo de oficio encima de las mesas»), deterministas con una semilla por edificio.
- **Mejoras que se ven:** cada mejora (4.8) añade, cambia o quita piezas de un interior por datos, como hoy.
- **Herramienta:** `tools/interiors/` valida (todo conectado, puertas que dan a algo, puestos alcanzables, nada pisa
  una puerta ni una escalera) y saca una vista previa en PNG sin abrir el juego, como el generador de ciudades.

### 4.6.5.3 Ver dentro: paredes que se abren

- **Paredes del frente:** las que dan a la cámara (abajo a la izquierda y abajo a la derecha) se ven **bajas**, como
  un zócalo, para que el interior se lea como un diorama.
- **Paredes interiores y puertas:** cuando el personaje seleccionado (o el ratón) está **detrás** de una, se vuelve
  **casi transparente** (25 %), con su contorno. Al salir de esa habitación, vuelve a verse entera.
- **Plantas:** cuando el personaje sube la escalera, la planta alta se ve y la de abajo queda en penumbra. Si sube el
  ratón con la rueda (o pulsa un botón «Planta alta»), se ve la otra planta sin mover a nadie, como en Los Sims.
- **Luz:** cada habitación tiene su luz (la fragua roja y viva, la cocina cálida, el almacén en penumbra), por capas
  sobre el día y la noche de 4.15.

### 4.6.5.4 ¿Andar o aparecer? (respuesta a la pregunta del owner)

| Quién | Cómo se mueve dentro | Por qué |
|---|---|---|
| **Tus personajes** (los que controlas) | **Andan**, como hoy (4.6.4): clic en un puesto y van, por las puertas y la escalera | Es lo que da vida a la escena y ya existe |
| **Empleados** | **Andan** entre su puesto, el almacén y la puerta | Igual que hoy; se ven trabajar |
| **Clientes** (mostrador, taberna, posada) | **De momento aparecen** en su sitio de acción con un fundido corto de 0,3 s: en la cola del mostrador, en una silla de la mesa, en la barra o junto a la cama. Al irse, desaparecen igual | Es lo que propone el owner para empezar: barato, sin atascos en puertas estrechas y sin cambiar el sim |
| **Más adelante** | Los clientes entran por la puerta y andan hasta su sitio | Cuando la navegación del interior aguante el tráfico de una taberna llena |

**El cliente que aparece** enseña lo que quiere en una burbuja sobre la cabeza:
- en la mesa, una **exclamación** con el icono del plato («una ración de olla»);
- en el mostrador, el icono de lo que viene a comprar («una espada») o «encargo» si viene a pedir una pieza;
- en la cola, «esperando».

También lleva su **barra de paciencia**. Clic en él (o el empleado del puesto) para atenderle: se le cobra, se va
contento o, si se le acaba la paciencia, se va con una queja.

### 4.6.5.5 El mostrador y la barra

- **Mostrador de tienda** (forja, armería, sastrería y carpintería): una pieza larga con 2 o 3 **sitios de cliente**
  delante y la **cola** detrás. A él vienen:
  - los **clientes del mostrador** (4.5.4), que compran del expositor;
  - los que **hacen un encargo** (4.5.6) y los que **lo recogen**;
  - en las fiestas, los que vienen a por su encargo de fiesta (4.25.4).
- **Expositor:** detrás o al lado, una estantería o panoplia que **enseña lo que tienes a la venta** (las espadas de
  verdad del almacén, hasta 6 a la vista).
- **Barra de la taberna** (4.27): la barra grande con sus taburetes, los toneles detrás y sitios para pedir de pie;
  las mesas del salón; y la escalera a las habitaciones de la posada, en la planta alta.

### 4.6.5.6 Los interiores que se quieren

| Edificio | Planta baja | Planta alta |
|---|---|---|
| Forja | taller (fragua en un foso de un escalón, yunque, temple), tienda con mostrador y expositor, puerta al almacén | vivienda: cocina y dormitorio |
| Armería | tienda grande con mostrador, panoplias y maniquíes; trastienda | — |
| Carpintería | taller con banco y sierra, patio de tablones, tienda pequeña | vivienda |
| Cantería | patio de bloques con tarima de trabajo, cobertizo | — |
| Sastrería | taller con mesa de corte y telar, tienda con probador | vivienda |
| Taberna-Posada | salón con barra, mesas, chimenea y rincón del juglar; cocina | habitaciones de la posada; **sótano**: bodega |
| Ayuntamiento | sala del concejo, archivo, despacho del Alcalde | — |
| Tribunal | sala con estrado, banco del acusado y banco de testigos | — |
| Casa de la familia | hogar, cocina y mesa | dormitorios |
| Guarida de ladrones (4.22) | taller del perista, mesa de juego | — ; **sótano**: jaula de los secuestrados y contrabando tras una trampilla |

### 4.6.5.7 De dónde salen los clientes (sin romper la vida del pueblo)

El owner pregunta cómo tener clientes en todos los negocios a la vez que se respeta la vida del pueblo, si es difícil
equilibrarlo y si los NPC que no son competidores deberían tener dinero ilimitado y venir porque el negocio es famoso,
no porque necesiten algo. La respuesta es **dos capas de clientes**:

| Capa | Quiénes | Cuántos | De dónde sale su dinero | Cómo se ven |
|---|---|---|---|---|
| **Vecinos** | Los 20-32 habitantes de la villa, con su agenda (4.24.1) | Pocos: los que su agenda manda (hambre → la taberna, «ir a la compra» → la tienda) | Su bolsa (como hoy) | Andan por la calle hasta tu puerta y dentro aparecen en su sitio. Tienen nombre, y atenderles bien sube la relación |
| **Clientela de la comarca** | Gente de las aldeas y caseríos de alrededor, de paso o de otras ciudades: no son habitantes del mapa | La mayoría. Salen de la **demanda** del negocio, no de la población | **De fuera** (P4, 4.19): su bolsa no se simula, pero tienen un **precio máximo** que están dispuestos a pagar | Aparecen dentro con un fundido (O-I2) y desaparecen al irse. Llevan ropa de aldea o de viaje; no cuentan en la población ni pasean por la villa |

- **Lo que se equilibra no es su dinero, sino cuántos vienen y cuánto aceptan pagar.** Para cada negocio:
  ```
  clientes_día(b)   = base(oficio) × fama(b) × reputación(familia) × estación × fiesta × reparto(competencia)
  precio_máximo(c)  = precio_ref(objeto) × calidad × (1 + fama(b) × 0,1) × gusto(grupo)
  ```
  `base(oficio)` está en los datos (`data/services.json` y la configuración del mostrador de 4.5.4); el reparto se
  hace con el rival y los demás proveedores por la fórmula de atractivo de 4.22.3.2. Así **vienen porque el negocio es
  famoso** (fama, calidad, precio), y no porque un vecino concreto lo necesite, como propone el owner.
- **No es difícil de equilibrar**, porque es como se ha hecho desde H12: cada oficio tiene su bot y su diana de oro
  neto por día. Una clientela nueva solo cambia `base(oficio)`, y se ajusta midiendo con el bot de ese oficio.
- **La vida del pueblo se respeta:** los vecinos siguen su agenda. Los de la comarca no ocupan casas, ni comen ni
  duermen en el pueblo (salvo los forasteros de 4.24.3, que duermen en la posada). Las tiendas se llenan sin vaciar la
  plaza.
- **Fiestas y feria:** suben las dos capas (más forasteros y más comarca), que es justo lo que se espera del día de
  feria.

**La fama de un taller (Equilibrio 13, 2026-11-05).** El `fama(b)` de la fórmula, para los talleres (no la Taberna-Posada,
que tiene la suya de 0-5, 4.27): un multiplicador **0,5-2,0** que empieza en 1.

```
fama(b)  = clamp(1 + calidad_media × 0,25 + renombre, 0,5, 2,0)
calidad_media = la de lo vendido en los últimos 4 días (0 normal, 1 buena, 2 excelente), mercado y mostrador
renombre = Σ puntos por hecho (±0,75 como mucho), que pierde un 15 % cada alba:
           obra maestra +0,3 · encargo cumplido +0,04 · encargo de fiesta +0,15 · concurso ganado +0,2
           encargo incumplido −0,1 · queja (cliente que se va sin atender o sin nada que comprar) −0,03
```

Hoy la lee el mostrador de 4.5.4 (clientes cada intervalo / fama y precio + (fama − 1) × 0,1); la clientela de
comarca de la rama interiores la leerá como `fama(b)` cuando se unifique (Equilibrio 14). Los hechos de la familia sin
edificio (ventas en la plaza, encargos, obras maestras) van a su taller principal. Los concursos ganados los apunta
fiestas en `buildings[taller].contests_won` (`FestivalCourt._judge`), que la fama lee con su evento `festival_contest`
(cada victoria nueva, +0,2). Se ve en el título del panel de
producción («Forja · fama 1,25», con su explicación). Cifras en `data/town.json` `workshop_fame`; reglas en
`sim/balance/workshop_fame.gd`; estado `buildings[b].fame` (sin versión nueva: se lee con su valor por defecto).

**La bolsa de los hogares (Equilibrio 15, 2026-11-05).** Con la vida encendida, la capa de **Vecinos** tiene dinero
propio: al empezar el atardecer, cada adulto con un oficio del mapa (y sin empleo con una familia) trae a la bolsa de
su casa su **jornal** (7; 9 los del puesto o la tienda) [balance], dinero de fuera (P4). Al alba la casa paga **la
comida** (2 por adulto, 1 por niño), que sale de la economía, y lo que pudo pagar alimenta a sus empleados y niños
(4.24.1, el hambre). **La taberna es un capricho:** un vecino solo gasta allí lo que le sobra sobre la comida del día
siguiente. Diana: **6-12 vecinos por noche** en la taberna un día normal (escenario de la posada). Cifras en
`data/town.json` `households`; reglas en `sim/balance/households.gd`; estado `families[hogar].household`.

**Una sola clientela de comarca (Equilibrio 14, 2026-11-06).** `sim/town/clientele.gd` es la clientela de comarca de
los talleres y de la Taberna-Posada: el atractivo del proveedor de 4.22.3.2 (`Clientele.provider_appeal`: precio,
reputación y el bonus de clientes de sus mejoras, cifras de `data/services.json`), la fama (`Clientele.fame`: la del taller
de Equilibrio 13 o la de la taberna) y el factor de precio máximo (`Clientele.max_price_mult`) son una sola fórmula; la
taberna (`InnClientele`) la lee y conserva su turno de noche y sus grupos. **Encendida para la forja** (`data/town.json`
`counter.clientele.enabled`): medido con el experto en el mostrador (un empleado, 5 semillas × 24 días), el mostrador
vende 113-120 de oro al día frente a un salario de 19-20 (×5,8-6,2, Equilibrio 8), con o sin la vida. Lo que lo limitaba
no eran los clientes sino las existencias: el bot lo llevaba todo a la plaza y 3 de cada 4 clientes se iban sin nada;
ahora guarda 2 piezas de cada producto para el mostrador mientras alguien lo atiende. Carpintería, cantería y sastrería
quedan a 0 (sus cifras propuestas en `_proposed_base_per_day`) hasta que un bot del oficio con mostrador las mida. **Sus dianas** (`data/targets.json` `counter_shop`, bot `counter_shop`, paso counter
de la QA): el mostrador con un empleado vende al menos 2 veces su salario (3 de media) y llegan 1,5-4 clientes de
comarca al día. Medido (5 semillas × 24 días): ventas ×5,0-6,6 el salario; 2,4-2,8 clientes de comarca al día que casi
nunca encuentran pieza (0,05-0,19 compras): el taller ya vende en el mostrador todo lo que forja (con 4 o 6 piezas
guardadas sale igual), así que la comarca es demanda de sobra para quien produzca más.

**La taberna comprada (equilibrio, 2026-11-06).** Se vende con lo que dejó el tabernero anterior en la despensa
(`data/buildings/tavern_inn.json` `sale_stock`: las existencias del escenario innkeeper_start). Medido con el jugador
completo: la taberna pierde sus 7-10 primeros días (−595 de oro de media; −523 con la despensa) porque arranca sin fama,
se agotan platos y compra por recado; luego compensa: del año 5 al 6, 300-336 de oro al día con fama 4,6-5, y en una
generación la familia gana 400-800 al día (oro máximo 42.000, 29.200 al final con la pecha). Lo que pide decisión es el
largo plazo (rinde 3 veces la forja): sumideros de H6.

### 4.6.5.8 Preguntas para el owner (decididas el 2026-11-04)

| # | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| **O-I1** | ¿Cuántas plantas? | (a) Como mucho dos (baja y alta) más desniveles de un escalón. (b) Sótano, baja y alta. (c) Una sola planta con desniveles | **Owner: (b)**, sótano, baja y alta; en el sótano del Pícaro, la jaula y el contrabando |
| **O-I2** | Clientes que aparecen | (a) Sí, de momento, con fundido y burbuja. (b) Que anden ya | **Owner: (a)**, con fundido |
| **O-I3** | Paredes | (a) Las del frente, bajas siempre, y las interiores transparentes cuando estás detrás. (b) Todas bajas siempre | **Owner: (a)** |

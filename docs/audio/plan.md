# Audio básico con ElevenLabs — plan y coste

Encargo del 2026-11-02 (rama `audio-base`). **Tope duro: 20.000 créditos de ElevenLabs** (los créditos se renuevan cada
día 20/21 del mes). Saldo al empezar: 69.266 usados de 121.034 (quedan 51.768). El tope se corta en 89.266 usados.

Tono (docs/style/biblia.md): siglo XIV centroeuropeo, cálido y vivido (Stardew Valley, Graveyard Keeper). Instrumentos
de época (laúd, flauta de pico, fídula, zanfona, tambor de marco), pocos y cercanos. **Nada de música épica de
Hollywood**: sin orquesta, coros ni percusión de tráiler.

## Herramientas

| Herramienta | Qué hace |
|---|---|
| `tools/audio/eleven.py` | API directa de ElevenLabs: `balance`, `budget`, `sfx`, `music`, `voices`, `voice`, `log`. Estima, se niega si pasaría del tope, registra coste real (cabecera `character-cost`) y saldo antes/después en `audio-generations/log.jsonl`. |
| `tools/audio/master.py` | Crudo → `assets/audio/<sección>/<id>[_NN].ogg`: recorta silencios, normaliza (pico en efectos, LUFS en loops), cierra bucles con fundido y comprueba duración, picos y costura del loop. |
| `audio-generations/` | Descargas en bruto (fuera de git, `.gdignore`). |

`tools/audio/generate_audio.py` y `generate_voice.py` vienen de Guild Renew (fal.ai) y no se usan.

## Tarifas medidas

| Qué | Tarifa | Fuente |
|---|---|---|
| Efecto (`eleven_text_to_sound_v2`, duración fija) | ~11 créditos por segundo pedido | medido: 3 × 1 s = 33 |
| Música (`music_v1`) | ~825 créditos por minuto | medido: 1.238 por 90 s (dos veces) |
| Voz (`eleven_multilingual_v2`) | ~0,45 créditos por carácter | medido: 84 por 5 frases (186 caracteres) |
| Ambiente (`eleven_text_to_sound_v2`, `loop`) | 330 por 30 s | medido |

El saldo de `/v1/user/subscription` llega con unos segundos de retraso; el coste real de cada llamada es la cabecera
`character-cost`, y el saldo se usa como comprobación cruzada.

## Lista priorizada (lo que más se oye primero)

| Prio | Id | Qué | Disparo | Variantes × duración | Estimado |
|---|---|---|---|---|---|
| a1 | `sfx_hammer` | martillo sobre yunque | `work_done` | 3 × 1 s | 33 (hecho) |
| a2 | `sfx_coins` | monedas en la bolsa / mostrador | `market_sold`, `market_bought` | 3 × 1 s | 35 |
| a3 | `sfx_ui_click` | clic de madera/pergamino | (sin enganchar: los botones son encargo aparte) | 3 × 0,5 s | 20 |
| a4 | `sfx_door` | puerta de madera con bisagra | `building_entered`, `building_left` | 2 × 1,5 s | 35 |
| a5 | `sfx_bellows` | fuelle de forja | `master_touch_done` | 2 × 1,5 s | 35 |
| b1 | `music_city_day` | laúd, flauta, fídula; plaza de mercado | fases dawn/day/dusk | 1 × ~90 s (2.ª toma si no sirve) | ~3.000–6.000 |
| b2 | `music_night` | laúd lento, zanfona suave | fase night | 1 × ~90 s | ~3.000–6.000 |
| c1 | `ambient_town_day` | plaza: gente, carros, pájaros | fases de día (exterior) | 1 × 30 s loop | ~330 |
| c2 | `ambient_night` | grillos, viento, perro lejano | noche (exterior) | 1 × 30 s loop | ~330 |
| c3 | `ambient_forge` | fuego de fragua, crepitar | interior de la forja | 1 × 30 s loop | ~330 |
| d1 | `sfx_hire` | apretón / firma con pluma | `employee_hired` | 2 × 1,5 s | 35 |
| d2 | `sfx_upgrade_done` | martillazos de carpintero + campanilla | `upgrade_done` | 2 × 2 s | 45 |
| d3 | `sfx_notice` | campanilla de aviso | aviso de severidad `warning` | 2 × 1 s | 25 |
| d4 | `sfx_alarm` | campana de alarma | aviso de severidad `urgent` | 1 × 2 s | 25 |
| d5 | `sfx_debt` | cadena / sello pesado | avisos de deuda (sueldo, mantenimiento, embargo, ruina) | 2 × 1,5 s | 35 |
| d6 | `sfx_objective_done` | fanfarria corta de flauta y campanas | aviso `notice.objective_done` | 1 × 2,5 s | 30 |
| d7 | `sfx_objective_failed` | laúd descendente | aviso `notice.objective_failed` | 1 × 2,5 s | 30 |
| d8 | `sfx_contract_done` | sello de cera + monedas | `contract_delivered` | 2 × 1,5 s | 35 |
| e | `voice_*` | frases cortas en castellano (vendedor, pregonero del tablón) | sin disparo aún (encargo aparte) | ~8 × ~40 caracteres | ~400 |

Reserva para segundas tomas: ~30 % del estimado. Total previsto: ~8.000–14.000 créditos, por debajo del tope.

## Enganche en el juego

- Efectos de eventos: `events` de `data/audio.json`. Para los avisos (`notice_added`), el AudioDirector busca primero
  la clave del aviso (`notice.objective_done`…) y luego la severidad (`notice_added.warning`, `notice_added.urgent`),
  para que un mismo aviso no suene dos veces.
- Ambiente: `phase_ambient` (fase → id, en el pueblo) e `interior_ambient` (tipo de edificio → id, dentro), en un
  reproductor propio del AudioDirector, bus `Ambient`.
- Música y ambiente se importan con *Loop* activado (`.import`).

## Resultado (2026-11-02)

**Gastado: 4.010 de 20.000 créditos** (saldo: 73.276 usados de 121.034; quedan 47.758). Detalle por tanda en
`assets/audio/MANIFEST.md`. Todo lo de la lista está generado e integrado salvo lo marcado.

| Id | Ficheros | Comprobación | Nota |
|---|---|---|---|
| `sfx_hammer` | 3 | ataque seco y caída de ~0,4 s, brillante | |
| `sfx_coins` | 3 | tintineo de ~0,8 s | |
| `sfx_ui_click` | 3 | golpe de < 0,1 s | **sin enganchar**: los botones no llaman a AudioDirector (encargo aparte) |
| `sfx_door` | 2 | crujido + golpe, ~1,2 s | |
| `sfx_bellows` | 2 | soplido sostenido, ~1,4 s | |
| `music_city_day` | 1 | 100 bpm; bucle de 32 compases (76,8 s) cortado donde la pieza repite su frase (correlación 0,85); costura sin clic | -18 LUFS |
| `music_night` | 1 | textura de bordón sin pulso; bucle de 85 s con fundido de 3 s; costura sin clic | -20 LUFS |
| `ambient_town_day` | 1 | loop nativo de 30 s, costura sin clic | |
| `ambient_night` | 1 | loop nativo; se quitó un hueco de 1,5 s sin grillos (16,6–18,0 s) | 28,25 s |
| `ambient_forge` | 1 | loop nativo de 30 s, crepitar | |
| `sfx_hire`, `sfx_upgrade_done`, `sfx_notice`, `sfx_debt`, `sfx_contract_done` | 2 cada uno | envolventes coherentes con el prompt | |
| `sfx_alarm` | 1 | campana, caída de ~2 s | |
| `sfx_objective_done` | 2 | tono ascendente (689→1.160 Hz; 459→918 Hz) | |
| `sfx_objective_failed` | 1 | tono descendente (469→400→350 Hz) | **1 toma descartada**: no bajaba con claridad |
| `voice_market_vendor` | 3 | pausas donde las comas | **sin disparo** (encargo aparte) |
| `voice_board_crier` | 2 | pausas donde las comas | **sin disparo** (encargo aparte) |

Comprobado con análisis (envolvente, pico, RMS, tono por autocorrelación, salto en la costura), **no escuchado por
un humano**: el owner debe oírlo antes de darlo por `final`.

**Verificación (2026-11-02):** `python3 tools/qa/run_all.py` en verde (349 pruebas). Arranque con ventana y driver real
(CoreAudio), `--dev-time --smoke-script=rebanada` por `grimoire heavy`: sale con 0, sin ningún `ERROR`; suenan
`music_city_day` ↔ `music_night`, los tres ambientes (la forja al entrar), martillo, puerta, fuelle, monedas, contratar,
mejora, encargo entregado, aviso y objetivo cumplido. Con el driver Dummy (headless) el AudioDirector no arranca
reproducciones: Godot 4.7 deja una reproducción colgada si se para mientras el juego se cierra
(«resources still in use at exit»), y con Dummy no se oye nada de todos modos.

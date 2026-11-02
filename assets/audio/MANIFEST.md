# Audio · gasto de créditos

Créditos de ElevenLabs (plan Creator, se renuevan el día 21 de cada mes). Detalle de cada llamada (prompt, parámetros,
coste, saldo) en `audio-generations/log.jsonl` (fuera de git); `python3 tools/audio/eleven.py log` lo resume.
Coste real = cabecera `character-cost` de la respuesta; el saldo de `/v1/user/subscription` llega con unos segundos de
retraso y se usa para conciliar.

| Fecha | Encargo | Herramienta | Assets | Saldo antes (usados) | Saldo después (usados) | Gasto |
|---|---|---|---|---|---|---|
| 2026-11-02 | Audio básico (rama audio-base, tope 20.000) · a: efectos de data/audio.json | ElevenLabs sfx v2 | sfx_hammer ×3, sfx_coins ×3, sfx_ui_click ×3, sfx_door ×2, sfx_bellows ×2 | 69.266 / 121.034 | 69.418 | 152 |
| 2026-11-02 | ídem · b: música en bucle | ElevenLabs music_v1 (90 s cada una) | music_city_day, music_night | 69.418 | 71.894 | 2.476 |
| 2026-11-02 | ídem · c: ambientes en bucle | ElevenLabs sfx v2, loop, 30 s | ambient_town_day, ambient_night, ambient_forge | 71.894 | 72.884 | 990 |
| 2026-11-02 | ídem · d: efectos de eventos del sim | ElevenLabs sfx v2 | sfx_hire ×2, sfx_upgrade_done ×2, sfx_notice ×2, sfx_alarm, sfx_debt ×2, sfx_objective_done ×2, sfx_objective_failed ×2 (1 descartada), sfx_contract_done ×2 | 72.884 | 73.192 | 308 |
| 2026-11-02 | ídem · e: voces en castellano | ElevenLabs TTS multilingual v2 | voice_market_vendor ×3, voice_board_crier ×2 | 73.192 | 73.276 | 84 |
| | **Total del encargo** | | 20 ids, 37 ficheros en assets/audio/ | **69.266** | **73.276** | **4.010 de 20.000** |

Tarifas medidas: efecto ~11 créditos por segundo pedido; música ~825 por minuto (1.238 por 90 s); voz ~0,45 por carácter.
Descartado (pagado, no integrado): 1 toma de `sfx_objective_failed` (28 créditos).

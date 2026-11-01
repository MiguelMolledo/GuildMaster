## Apéndice B. Qué llevarse del repo actual

| Llevarse | Desde | Notas |
|---|---|---|
| Assets | `assets/sprites/`, `assets/concept/` | Renombrar al contrato de `ASSETS.md`, registrar en el MANIFEST. |
| Datos | `data/items.json`, `recipes.json`, `social_phrases.json`, `upgrades/forja_upgrade_tree.tres` | Convertir a una ficha por cosa, ids en inglés; corregir `piedra`, `acero`, precio del pan. |
| Diseño | `docs/GDD.md`, `specs/*.md` | Ya consolidados aquí; quedan como histórico. |
| Guías de estilo | `docs/style_guide*.md` | Base de `docs/style/biblia.md`. |
| Herramientas | `scripts/tools/generate_concept.py`, `generate_voice.py`, `generate_audio.py`, `generate_item_icons.py`, `convert_*.py` | A `tools/art/` y `tools/audio/`. |
| Comandos | `.claude/commands/generar-asset.md`, `revisar-assets.md`, `aparcar-mejora.md` | Actualizar al MANIFEST y a los protocolos. |
| De Wizards Broke It | `tests/run_tests.gd` + `test_case.gd`, `tools/validate_content.py`, `new_content.py`, `sim_runner.gd`, `sim_report.py`, `cuaderno.py`, `paginas.py`, `qa/run_all.py`, `qa/boot_check.sh`, `preparar_jugar.sh`, `git-hooks/`, `assets/art/_tools/`, `tools/audio/` | Adaptar nombres y dianas. |
| **No** llevarse | Código de `scripts/` | Sirve de consulta para detalles, pero se reescribe con la arquitectura nueva. |

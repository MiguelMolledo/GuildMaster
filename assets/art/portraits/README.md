# Retratos · pool por sexo, edad y tipo social

Contrato entre el arte (rama `arte-fal`) y quien asigna retratos con la semilla (rama `poblacion`). **Lo que manda es
`index.json`**: no hace falta recorrer carpetas ni adivinar nombres. Formato fijado el 2026-11-03, versión 1. Si
cambia, sube `version` y se apunta aquí.

## Carpetas

```
assets/art/portraits/
  index.json                        ← el índice (abajo)
  <sexo>/<edad>/<tipo>/<id>.png     ← busto 64×64 (fichas, cartas, árbol grande)
  <sexo>/<edad>/<tipo>/<id>_32.png  ← cara 32×32 (HUD, árbol, listas)
  <id_antiguo>.png, <id_antiguo>_32.png   ← los 80 de la primera tanda (siguen ahí para quien ya los use; no
                                             están en el índice con ese nombre: van copiados al pool, abajo)
```

- `sexo`: `m` | `f`.
- `edad` (franjas en años de juego):

  | Franja | Años |
  |---|---|
  | `child` | 6-11 |
  | `youth` | 12-17 |
  | `adult` | 18-44 |
  | `mature` | 45-59 |
  | `elder` | 60+ |

  Menores de 6 años: se usa `child`.
- `tipo` (tipo social):

  | Tipo | Quién |
  |---|---|
  | `artisan` | artesano |
  | `commoner` | vecino humilde |
  | `merchant` | mercader o rico |
  | `noble` | noble |
  | `clergy` | clérigo o monja |
  | `guard` | guardia o soldado |
  | `scholar` | erudito o médico |
  | `farmer` | granjero |
  | `rogue` | pícaro |

- `id`: `<sexo>_<edad>_<tipo>_<nn>` (p. ej. `f_mature_merchant_03`), minúsculas y snake_case. Es único y no cambia:
  se puede guardar en la partida.

## `index.json`

```json
{
  "version": 1,
  "sizes": {"bust": 64, "face": 32},
  "ages": {"child": [6, 11], "youth": [12, 17], "adult": [18, 44], "mature": [45, 59], "elder": [60, null]},
  "types": ["artisan", "commoner", "merchant", "noble", "clergy", "guard", "scholar", "farmer", "rogue"],
  "fallback": {"clergy": {"child": "commoner"}, "guard": {"child": "commoner"}},
  "regions": {"hair": 50, "skin": 100, "primary": 150, "secondary": 200},
  "portraits": [
    {
      "id": "m_adult_artisan_01",
      "sex": "m",
      "age": "adult",
      "type": "artisan",
      "file": "m/adult/artisan/m_adult_artisan_01.png",
      "face": "m/adult/artisan/m_adult_artisan_01_32.png",
      "recolor": ["hair", "skin", "primary", "secondary"],
      "traits": ["beard", "apron"]
    }
  ]
}
```

| Campo | Qué es |
|---|---|
| `portraits[].file` / `face` | Ruta relativa a `assets/art/portraits/` del busto (64) y de la cara (32). |
| `portraits[].recolor` | Zonas que lleva codificadas y que el shader puede cambiar. `hair` incluye barba, bigote y cejas; `skin`, labios, cuello y manos. Si falta `primary`/`secondary`, la ropa es fija (el hábito del clérigo, la librea de la guardia…): no se tiñe con los colores de la familia. |
| `portraits[].traits` | Etiquetas libres para variar o filtrar: `beard`, `moustache`, `bald`, `glasses`, `scar`, `eyepatch`, `hat`, `hood`, `headscarf`, `veil`, `wimple`, `helmet`, `apron`, `braids`, `curly`, `long_hair`, `jewellery`, `tonsure`, `freckles`… Ninguna regla depende de ellas. |
| `fallback` | Combinaciones sin retrato propio: `fallback[tipo][edad]` da el tipo que se usa en su lugar (por ejemplo, un niño de familia de guardias usa `commoner`). Si para `sexo + edad + tipo` no hay ningún retrato y no hay fallback, usar `commoner` con esa edad y sexo: esa combinación existe siempre. |
| `regions` | Valor del canal azul de cada zona (ver abajo). |

**Garantías.**
- Toda combinación `sexo × edad × tipo` que no esté en `fallback` tiene al menos **4** retratos; la mayoría, **6**.
- `commoner` existe en todas las edades y sexos.
- `fallback` también puede apuntar a combinaciones que en otras ciudades se cubrirán: el índice crece sin cambiar de
  formato.

## Cómo elegir y teñir (para `poblacion`)

1. **Candidatos:** los de `portraits` con `sex`, `age` y `type` de la persona, después de aplicar `fallback`.
2. **Uno con la semilla:** usar el azar del sim por clave (como los demás). Guardar el `id` en la persona, no el índice
   de la lista: así añadir retratos no cambia los de las partidas guardadas.
3. **Al cambiar de franja de edad** se elige otro de la franja nueva. Para que «crezca» el mismo, se puede preferir el
   mismo `nn` si existe (las caras de un mismo `nn` **no** son la misma persona: es solo para que sea estable).
4. **Teñir:** los PNG están codificados como los sprites de personaje (`tools/art/personajes_guild.py`):
   - píxel con **alfa 254** = zona recolorable;
   - **azul** = zona (50 pelo, 100 piel, 150 ropa principal, 200 ropa secundaria);
   - **rojo** = brillo relativo (color final = color de la zona × rojo / 127,5).

   Se pintan con `game/visuals/characters/identity_swap.gdshader` y sus uniformes `hair`, `skin`, `primary` y
   `secondary`. El resto de píxeles se dibujan tal cual.
5. **Canas:** el dibujo no las fuerza. Para un `elder` (o un `mature` con canas), el juego pasa un `hair` gris o
   blanco.
6. **Fondo transparente:** el fondo lo pone el marco del retrato.

## Estado

El pool se está generando. Hasta que esté, `index.json` puede no existir o estar a medias: los retratos que estén en
el índice son válidos. Los 80 de la primera tanda se copian al pool con un id nuevo de su tipo equivalente
(`artisan_adult_m` → `m/adult/artisan/…`, `townsfolk_*` → `commoner`, `patron_*` → `farmer`, `priest` → `clergy`…).

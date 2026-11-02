## Apéndice A. Fórmulas consolidadas

```
Calendario (D1(b))      = 1 día = 5 min reales · 1 estación = 2 días · 1 año = 8 días (40 min) · 1 año de edad por año
Precio de compra (F1)   = round(base × calidad × demanda × estado_npc × regulación)       calidad: 1,0 / 1,3 / 1,6
Precio de venta         = round(precio_compra × 0,70)
Demanda                 ∈ [0,5 ; 2,0]; −0,04 por unidad vendida en el mercado por cualquier actor (unidad a unidad); +0,4/día hacia 1,0 [balance]
Precio en mostrador     = base × calidad × (1 + carisma/100 + equipo + rango + bonus_edificio + min(rep/100 × 0,15 ; 0,15))
Duración de receta      = duración_horas / (velocidad_rango × mult_mejoras) × modo (rápido 0,7 / normal 1 / con cuidado 1,5)
Calidad a mano          = tabla de 4.4.2 con Artesanía −3 (rápido) / +2 (con cuidado); toque de maestro +15 % de subir un escalón
Pago de encargo         = cantidad × precio_venta_actual(objeto, calidad) × 1,4
Recado de entrega       = precio_compra × 1,2; llega en 2 h
Salario/día (4.7.2)     = aprendiz 7 · oficial 20 · maestro 40; velocidad ×1 / ×2 / ×3 [balance]
Mantenimiento/día       = Forja 20 [balance] (D12)
Mejoras (4.8)           = oro de la tabla de 4.8 (×5 de D14 sobre el primer intento) [balance]
Sumideros recurrentes   = (salarios + mantenimiento + impuestos) / margen bruto ∈ [30 %, 60 %]; margen bruto = ventas + encargos − compras − recados
Deuda inicial           = 200 (Normal) en 1 año; vencida: +25 % y prórroga de 1 estación; luego embargo
SkillCheck              = d100 ≤ 50 + (actor − objetivo) × 5 + mods; ≤5 crítico, ≥96 pifia
Afinidad por acción     = base × (1 + (carisma − 5) × 0,1) × (1,15 si misma clase)
Stat del hijo           = (padre + madre)/2 + rand(−1,1), [1,10], +1 si ambos ≥ 7
Actitud del hijo        = (padre + madre)/2 × 0,5
Muerte (≥55)            = 0,02 × 1,25^(edad−55) × (1 − (constitución−5) × 0,05) por año (tirada al cambiar de año)
Hijos                   = posibles 1 estación tras la boda; 10 %/día; 1 año entre hijos; máx. 3
Carga máxima            = 60 + (constitución − 5) × 3 kg (implementado: 60 kg fijos) [balance]
Inspección/día          = Σ inspection_risk × (1 − honestidad/200)
Voto                    = afinidad × 0,3 + reputación_norm × 0,3 + mod_clase × 0,2 + campaña × 0,2
Juicio                  = defensa: retórica×2 + a_favor×15 + rep×0,1  vs  acusación: retórica×2 + en_contra×15 + pruebas×20
Reputación pasiva       = +1/día por negocio operativo con empleados
Utilidad IA rival       = Σ peso_obj × avance_obj − coste_oro_norm − riesgo × aversión + ruido
Conservación del oro    = Σ asientos del libro de una familia = variación de su oro
Puntuación de dinastía  = Σ puntos de los hechos de la crónica (data/score.json) + patrimonio_máx / 100
```

Todas las duraciones: tabla "Duraciones de referencia" de 4.1.

# Zahoris

Juego de plataformas 2D en Godot 4.7 (GDScript, renderer GL Compatibility), estilo pixel art con grilla de 16 px y resolución base 576x324.

## Mecánica principal

El player no salta: mantiene `action` (Z) para generar bloques bajo sus pies y elevarse una celda por bloque (máximo `Global.max_blocks`). Al soltar, los bloques desaparecen uno a uno y la habilidad no se puede volver a usar hasta que se borre el último, salvo que el player se baje y pise otro piso: ahí se desvanecen todos a la vez y la habilidad queda libre al instante. Las puertas conectan rooms (se entra con UP) y el agua es muerte instantánea (reaparece en la puerta por la que entró).

## Estructura

- `scripts/Global.gd`: autoload. Estado global y lógica de spawn entre rooms (qué puerta usar al volver).
- `scenes/`: escenas y scripts de cada entidad (`player`, `block`, `door`, `water`, `explosion`) más shaders (`silhouette`, `fx`).
- `scenes/rooms/`: niveles (`level0`, `level1`, ...). `Intro.tscn` es la escena inicial.
- `sprites/`: PNGs sueltos con formato `<entidad>_<accion>_spr_<frame>.png` (ver skill `art-maker`).
- `fonts/`: Pirata One.

## Convenciones

- Comentarios, docstrings (`##`) y commits en español.
- Interacciones por duck typing (`has_method("die")`, `has_method("enter_door")`) en lugar de chequear tipos.
- Parámetros ajustables como `@export` con su unidad comentada.
- Puertas: grupo `doors`, `target_scene` apunta al `.tscn` destino.
- Inputs definidos: `action`, `LEFT`, `RIGHT`, `UP` (flechas o WASD).

## Workflow

- Commits granulares sobre `master`, sin branches (ver skill `commit-push`).

## TODO / pendientes

<!-- completar -->

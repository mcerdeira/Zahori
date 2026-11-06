# Zahoris

Juego de plataformas 2D en Godot 4.7 (GDScript, renderer GL Compatibility), estilo pixel art con grilla de 16 px y resolución base 576x324.

## Mecánica principal

El player no salta: mantiene `action` (Z) para generar bloques bajo sus pies y elevarse una celda por bloque (máximo `Global.max_blocks`, sin límite con la habilidad `reach` del altar 03). Al soltar, los bloques desaparecen uno a uno y la habilidad no se puede volver a usar hasta que se borre el último, salvo que el player se baje y pise otro piso: ahí se desvanecen todos a la vez y la habilidad queda libre al instante. Con la habilidad `eat` (altar 03), parado sobre un tile de piedra (`block_stone_spr_0.png`) y manteniendo DOWN, el player se lo come y cae; si sigue apretando, come el siguiente al aterrizar (nunca en el aire, y nunca los bloques verdes propios). Las puertas conectan rooms (se entra con UP) y el agua es muerte instantánea (reaparece en la puerta por la que entró), salvo con la habilidad `hydro` (altar 02).

## Estructura

- `scripts/Global.gd`: autoload. Estado global y lógica de spawn entre rooms (qué puerta usar al volver).
- `scenes/`: escenas y scripts de cada entidad (`player`, `block`, `door`, `water`, `explosion`) más shaders (`silhouette`, `fx`).
- `scenes/rooms/`: niveles (`level0`, `level1`, ...). `Intro.tscn` es la escena inicial.
- `sprites/`: PNGs sueltos con formato `<entidad>_<accion>_spr_<frame>.png` (ver skill `art-maker`).
- `fonts/`: Pirata One y Press Start K (`prstartk.ttf`, la de la terminal; importada sin antialiasing).
- `scenes/terminal*`: terminal que abre el `altar` (UP encima). Pausa el juego y corre el puzzle del glifo: las letras de una palabra superpuestas en un solo glifo, que hay que adivinar (feedback tipo Wordle). El glifo se dibuja con trazos finos de 1 px (fuente vectorial propia en `glyph_view.gd`) y al lado hay un segundo cuadro con el glifo de lo que el jugador va tipeando. Hecha con nodos de UI (`RichTextLabel`, `LineEdit`, `Label`) dentro de un SubViewport con shader CRT (`crt.gdshader`); el input se le reenvía con `push_input`.
- `puzzles/altar_XX.tres`: un `GlyphPuzzle` (`scripts/glyph_puzzle.gd`) por altar; el altar elige el suyo con `altar_number`. Una sola palabra por puzzle, relacionada con la habilidad que desbloquea. Su `ability_id` es la clave en `Global.abilities` (todas arrancan en false); al resolverlo se marca en `Global.solved_altars` y se activa. Volver a un altar resuelto pregunta TURN OFF/ON con YES/NO. Para una habilidad nueva: agregar el id en `Global.abilities`, chequear `Global.has_ability(&"id")` donde se use y crear su `altar_XX.tres`.
- Altares de pistas: el mismo `altar.tscn` con `kind = HINT`. Abren la terminal pero sólo muestran un texto fijo (pista sobre la palabra de algún altar de puzzle), sacado de `puzzles/hint_XX.tres` (un `AltarHint`, `scripts/altar_hint.gd`) según su `altar_number`. La numeración es independiente de la de los puzzles. La pantalla entra ~20 caracteres por línea y ~13 líneas.
- `music/`: tema principal (`main_theme.ogg`, ~2 min en loop, chiptune con canales estilo NES: 2 pulse, triángulo y ruido) generado con `tools/gen_music.py` (numpy + ffmpeg). Lo reproduce el autoload `Music` (`scripts/Music.gd`), que sigue sonando con el juego pausado.
- `sounds/`: efectos `.wav` estilo 8-bit generados con `tools/gen_sfx.py` (editar ahí y volver a correrlo). Se reproducen con el autoload `Sfx` (`scripts/Sfx.gd`): `Sfx.play("nombre", pitch, volumen_db)`.

## Convenciones

- Comentarios, docstrings (`##`) y commits en español. Todo texto visible en el juego, en inglés.
- Interacciones por duck typing (`has_method("die")`, `has_method("enter_door")`) en lugar de chequear tipos.
- Parámetros ajustables como `@export` con su unidad comentada.
- Puertas: grupo `doors`, `target_scene` apunta al `.tscn` destino.
- Inputs definidos: `action`, `LEFT`, `RIGHT`, `UP`, `DOWN` (flechas o WASD).

## Workflow

- Commits granulares sobre `master`, sin branches (ver skill `commit-push`).

## TODO / pendientes

<!-- completar -->

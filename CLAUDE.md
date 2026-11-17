# Zahoris

Juego de plataformas 2D en Godot 4.7 (GDScript, renderer GL Compatibility), estilo pixel art con grilla de 16 px y resolución base 576x324.

## Mecánica principal

El player no salta: mantiene `action` (Z) para generar bloques bajo sus pies y elevarse una celda por bloque (máximo `Global.max_blocks`, sin límite con la habilidad `reach` del altar 03). Al soltar, los bloques desaparecen uno a uno y la habilidad no se puede volver a usar hasta que se borre el último, salvo que el player se baje y pise otro piso: ahí se desvanecen todos a la vez y la habilidad queda libre al instante. Con la habilidad `eat` (altar 03), el player se come automáticamente cada tile de piedra (`block_stone_spr_0.png`) que pisa y cae; al aterrizar sobre otro, se lo come también (nunca en el aire, y nunca los bloques verdes propios). También come las piedras que toca de costado (empujando contra ellas) y la que tiene encima de la cabeza al construir hacia arriba. Las puertas conectan rooms (se entra con UP) y el agua es muerte instantánea (reaparece en la puerta por la que entró), salvo con la habilidad `hydro` (altar 02): con ella activa los tiles de agua de la room se evaporan (se ven ~1 s soltando vapor y se disuelven con un siseo, `scenes/water_evaporation.gd`; el agua queda "apagada") y vuelven al apagarla (`Global.update_water_tiles`).

## Estructura

- `scripts/Global.gd`: autoload. Estado global y lógica de spawn entre rooms (qué puerta usar al volver).
- `scenes/`: escenas y scripts de cada entidad (`player`, `block`, `door`, `water`, `explosion`) más shaders (`silhouette`, `fx`).
- `scenes/rooms/`: niveles (`level0`, `level1`, ...). `Intro.tscn` es la escena inicial; lleva a `Intro2.tscn` (monólogo del protagonista con voz sintética: cada letra que aparece dispara una sílaba inventada `sounds/voice_*.wav` en el bus `Voice`, con reverb) y de ahí a `level0`.
- `scenes/boat.*`: canoa. Flota sobre los nodos `Water` (grupo `water`) mientras `Global.water_active` (pasa a false cuando la evaporación de hydro borra los tiles); sin agua cae hasta un tile, y si cae al vacío se borra 1.2 s después de salir de pantalla. Parado encima con el bote frenado, LEFT/RIGHT lo lanzan y avanza hasta chocar; mientras avanza el player no puede hacer nada (viaja como plataforma).
- Teleport (habilidad `teleport`, altar 05): con X (acción `shoot`), parado en el piso, el player dispara hacia donde mira un proyectil (`scenes/teleport_shot.*`); sólo uno vivo a la vez (incluida su animación de pop). Se deshace contra lo primero que toca; si eso tiene `interchangeable = true` el player intercambia lugar con él, alineados por los pies (`feet_offset()` opcional en el objetivo, `on_swapped()` opcional). `scenes/plant.*` es el primer objeto intercambiable (Area2D, no sólida).
- `scenes/ghost.*`: fantasma enemigo (16x16, titila rápido en violetas). `direction` HORIZONTAL (arranca a la derecha) o VERTICAL (arranca abajo), `start_reversed` lo invierte; da la vuelta al chocar con tiles, bloques verdes o el bote. Mata al player al tocarlo (hurtbox, chequeando la geometría real). Está en la capa de colisión 2: el player no choca con él, pero es `interchangeable` para el teleport. Tras morir, el player es invulnerable `respawn_grace` (0.6 s, parpadea).
- `sprites/`: PNGs sueltos con formato `<entidad>_<accion>_spr_<frame>.png` (ver skill `art-maker`).
- `fonts/`: Pirata One y Press Start K (`prstartk.ttf`, la de la terminal; importada sin antialiasing).
- `scenes/terminal*`: terminal que abre el `altar` (UP encima). Pausa el juego y corre el puzzle del glifo: las letras de una palabra superpuestas en un solo glifo, que hay que adivinar (feedback tipo Wordle). El glifo se dibuja con trazos finos de 1 px (fuente vectorial propia en `glyph_view.gd`) y al lado hay un segundo cuadro con el glifo de lo que el jugador va tipeando. Hecha con nodos de UI (`RichTextLabel`, `LineEdit`, `Label`) dentro de un SubViewport con shader CRT (`crt.gdshader`); el input se le reenvía con `push_input`.
- `puzzles/altar_XX.tres`: un `GlyphPuzzle` (`scripts/glyph_puzzle.gd`) por altar; el altar elige el suyo con `altar_number`. Una sola palabra por puzzle, relacionada con la habilidad que desbloquea. Su `ability_id` es la clave en `Global.abilities` (todas arrancan en false); al resolverlo se marca en `Global.solved_altars` y se activa. Volver a un altar resuelto pregunta TURN OFF/ON con YES/NO. Para una habilidad nueva: agregar el id en `Global.abilities`, chequear `Global.has_ability(&"id")` donde se use y crear su `altar_XX.tres`.
- Altares de pistas: el mismo `altar.tscn` con `kind = HINT`. Abren la terminal pero sólo muestran un texto fijo (pista sobre la palabra de algún altar de puzzle), sacado de `puzzles/hint_XX.tres` (un `AltarHint`, `scripts/altar_hint.gd`) según su `altar_number`. La numeración es independiente de la de los puzzles. La pantalla entra ~20 caracteres por línea y ~13 líneas.
- Laberinto de puertas: autoload `DoorMaze` (`scripts/DoorMaze.gd`). En `level181` y `level181a`…`g` las puertas con `target_scene = "-1"` son del laberinto: una sola por room (se identifica por nombre de nodo) lleva a la siguiente, el resto vuelve a `level181`. La combinación se sortea de a un paso y se descarta entera al errar (fuerza bruta inviable). Con la habilidad `zahori` (varita que da la hermana) la puerta correcta late, suena `dowse` y sobre la cabeza del player aparece un ícono de señal (`scenes/dowse_indicator.gd`, 1 a 3 rayitas) que parpadea con el ping, más rápido cuanto más cerca.
- Pausa: el autoload `Pause` (`scripts/Pause.gd`) abre `scenes/pause_menu.tscn` con Q (acción `pause`) sólo en las rooms (no en las intros ni con una terminal abierta). Mismo monitor CRT que la terminal, opciones CONTINUE / QUIT; mientras está abierto baja el bus Master un 60% y al cerrar restaura el volumen previo.
- `music/`: tema principal (`main_theme.ogg`, ~2 min en loop, chiptune con canales estilo NES: 2 pulse, triángulo y ruido) generado con `tools/gen_music.py` (numpy + ffmpeg). Lo reproduce el autoload `Music` (`scripts/Music.gd`), que sigue sonando con el juego pausado. Desde `level180` en adelante (parte final, `SILENT_FROM_LEVEL`) el tema se apaga con fade y queda en pausa; al volver a una room menor se reanuda desde donde quedó.
- `sounds/`: efectos `.wav` estilo 8-bit generados con `tools/gen_sfx.py` (editar ahí y volver a correrlo). Se reproducen con el autoload `Sfx` (`scripts/Sfx.gd`): `Sfx.play("nombre", pitch, volumen_db)`.

## Convenciones

- Comentarios, docstrings (`##`) y commits en español. Todo texto visible en el juego, en inglés.
- Interacciones por duck typing (`has_method("die")`, `has_method("enter_door")`) en lugar de chequear tipos.
- Parámetros ajustables como `@export` con su unidad comentada.
- Puertas: grupo `doors`, `target_scene` apunta al `.tscn` destino. Con `instant = true` la puerta es invisible y cambia de escena apenas el player la toca (para salir por los bordes del nivel); emite una luz aditiva que parpadea con los colores de la puerta (`door_glow.gdshader`, grupo Glow). Con `use_spawn_point` + `spawn_point` (coords de la room) el player aparece ahí al volver en vez de sobre la puerta. Al aparecer en una puerta: `with_boat` trae el bote de la room (grupo `boat`) y lo pone bajo sus pies; `facing` ("L"/"R", "-" = no cambiar) define para dónde mira.
- Inputs definidos: `action`, `LEFT`, `RIGHT`, `UP`, `DOWN` (flechas o WASD), `pause` (Q), `shoot` (X).

## Workflow

- Commits granulares sobre `master`, sin branches (ver skill `commit-push`).

## TODO / pendientes

<!-- completar -->

---
name: art-maker
description: Esta skill se usa para generar assets graficos al momento en que sea requerido que generes sprites o arte grafico
---

# Guidelines artisticos y tecnicos

- Todos los sprites van en la carpeta "sprites", en formato png. La paleta de colores debe estar basada en esta [paleta](/home/stinchi/Godot/tides/sprites/color-palette/gameboy-color-type1.gpl)


- IMPORTANTE: Basarse **SIEMPRE** en mi estilo artistico, podes encontrar ejemplos [aca](/home/stinchi/Godot/tides/sprites/examples)
- Preferir tamaños de 32x32 o 64x64 ya que todo es una grilla.
- No usar sprites-sheets para las animaciones. 
- Siempre utilizar formato png y tener en cuenta la [paleta](/home/stinchi/Godot/tides/sprites/color-palette/gameboy-color-type1.gpl)
- Siempre usar sprites separados y numerados (como los que se generarian usando Aseprite) numerados desde 0 y con el numero al final (para que Aseprite los tome automaticamente), por ejemplo, para un sprite que se llama player con 3 frames de animacion, debería ser: player_spr_0.png, player_spr_1.png, player_spr_2.png
- Si son sprites con acciones se deben separar en otro archivo con el formato: <entidad>_<accion>_spr_<frame>.png, supongamos que sea para la accion walk de player, deberia ser: player_walk_spr_0.png, player_walk_spr_1.png, player_walk_spr_2.png
- Respetar la resolución de los sprites, es decir, el tamaño de los pixeles para que haya homogeneidad entre los diferentes objetos.
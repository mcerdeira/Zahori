"""Debug del chequeo de progresión: dibuja las celdas a las que llega el player en una room.

Uso: python3 tools/room_reach.py level1 Door2 blocks,eat,reach   (puerta "-" = posición inicial)
o = celda donde puede pararse, ~ = agua letal, x = killer. Al final, los eventos posibles (puertas, muertes...)."""
import sys
sys.path.insert(0, "tools")
import check_progression as cp
room, door, abil = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
path = f"res://scenes/rooms/{room}.tscn"
class A: goal=None; maze_luck=False; assume=[]; verbose=False; fix={}
g = cp.Game(A())
act = 0
for a in abil.split(","):
    if a: act |= cp.BIT[a]
d = None if door == "-" else next(x for x in g.rooms[path].of_kind("door") if x.name == door)
node = g.initial_node(path, d, act, act)
sim = g.sims[path]
_, resp, _, _, dyn, _, _ = node
seen = set(); events = set()
todo = [(ev, dyn) for ev in sim.land(resp[0][0], resp[0][1], act, dyn, 0)]
while todo:
    ev, dy = todo.pop()
    if ev[0] != "stand":
        events.add(ev); continue
    k = (ev[1], ev[2], dy)
    if k in seen: continue
    seen.add(k)
    for e2, d2, lab in sim.moves(ev[1], ev[2], act, dy):
        todo.append((e2, d2))
    for dd in sim.doors.get((ev[1], ev[2]), []):
        events.add(("door", dd.name))
cells = {(x, y) for x, y, _ in seen}
r = g.rooms[path]
print("resp", resp, "boat", dyn[2], "events", sorted(events))
for y in range(cp.ROW_MIN, cp.ROWS):
    row = ""
    for x in range(-2, cp.COLS + 2):
        if (x, y) in cells: row += "o"
        elif (x, y) in sim.water: row += "~"
        elif (x, y) in sim.killer: row += "x"
        else: row += r.solid(x, y) if 0 <= x < cp.COLS and 0 <= y < cp.ROWS else " "
    print(f"{y:3d} {row}")

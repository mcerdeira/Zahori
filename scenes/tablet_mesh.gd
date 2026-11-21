extends RefCounted
## Geometría de la tableta de piedra rota en 4 pedazos (coleccionable).
##
## Las caras se modelan en coordenadas de texel de las texturas (60x80, y hacia
## abajo): dos grietas dentadas cruzan la tableta y se juntan en JUNCTION, y el
## contorno tiene las esquinas y algunos bordes desportillados. Cada pedazo se
## extruye a una malla 3D con 3 superficies: 0 = frente (enredaderas),
## 1 = reverso (glifos, con la U espejada para leerse al dar vuelta la tableta) y
## 2 = canto. Los vértices quedan relativos al centro de cada pedazo; su lugar
## en la tableta armada es `offset` (incluye una separación que deja ver la grieta).

const W := 60.0
const H := 80.0
const TEXEL := 0.05      # unidades 3D por texel
const THICKNESS := 8.0   # espesor en texels
const GAP := 1.0         # texels que se separa cada pedazo del centro (la grieta)
const SIDE_TEX := 16.0   # tamaño en texels de la textura del canto (se repite)
const JUNCTION := Vector2(31, 38)
const SEED := 2024

## Puntos donde las grietas llegan al borde: arriba, derecha, abajo, izquierda.
const EDGE_T := Vector2(28, 0)
const EDGE_R := Vector2(60, 35)
const EDGE_B := Vector2(33, 80)
const EDGE_L := Vector2(0, 42)

## Contorno entre grieta y grieta, en sentido horario (esquinas desportilladas).
const ARC_TR := [EDGE_T, Vector2(40, 0), Vector2(42, 2), Vector2(45, 1), Vector2(47, 0),
		Vector2(56, 0), Vector2(58, 1), Vector2(60, 3), EDGE_R]
const ARC_BR := [EDGE_R, Vector2(60, 58), Vector2(59, 60), Vector2(60, 63),
		Vector2(60, 77), Vector2(58, 80), EDGE_B]
const ARC_BL := [EDGE_B, Vector2(18, 80), Vector2(16, 78), Vector2(13, 80),
		Vector2(4, 80), Vector2(1, 79), Vector2(0, 76), EDGE_L]
const ARC_TL := [EDGE_L, Vector2(0, 22), Vector2(2, 20), Vector2(0, 18),
		Vector2(0, 5), Vector2(1, 2), Vector2(4, 0), EDGE_T]


## Devuelve un Array de 4 Dictionary { "mesh": ArrayMesh, "offset": Vector3 },
## en el orden de los índices de los fragmentos: 0 arriba-izq, 1 arriba-der,
## 2 abajo-der, 3 abajo-izq.
static func build_pieces() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var crack_t := _crack(JUNCTION, EDGE_T, rng)
	var crack_r := _crack(JUNCTION, EDGE_R, rng)
	var crack_b := _crack(JUNCTION, EDGE_B, rng)
	var crack_l := _crack(JUNCTION, EDGE_L, rng)
	var polys := [
		_piece_polygon(ARC_TL, crack_l, crack_t),
		_piece_polygon(ARC_TR, crack_t, crack_r),
		_piece_polygon(ARC_BR, crack_r, crack_b),
		_piece_polygon(ARC_BL, crack_b, crack_l),
	]
	var out := []
	var center := Vector2(W, H) / 2.0
	for poly in polys:
		var c := _centroid(poly)
		var push := (c - center).normalized() * GAP
		out.append({
			"mesh": _extrude(poly, c),
			"offset": _to_3d(c + push, 0.0),
		})
	return out


## Grieta dentada de `from` a `to`: puntos enteros con un corrimiento al azar
## perpendicular a la dirección.
static func _crack(from: Vector2, to: Vector2, rng: RandomNumberGenerator,
		step := 5.0, jitter := 2.2) -> Array:
	var pts := [from]
	var n := maxi(1, int(from.distance_to(to) / step))
	var perp := (to - from).orthogonal().normalized()
	for i in range(1, n):
		pts.append((from.lerp(to, float(i) / n) + perp * rng.randf_range(-jitter, jitter)).round())
	pts.append(to)
	return pts


## Contorno de un pedazo: el arco de borde (de la grieta `start` a la `end`) y
## las dos grietas hasta el centro.
static func _piece_polygon(arc: Array, crack_start: Array, crack_end: Array) -> PackedVector2Array:
	var pts: Array = arc.duplicate()
	var back := crack_end.duplicate()
	back.reverse()
	pts += back.slice(1)              # del borde al centro
	pts += crack_start.slice(1, -1)   # del centro al borde (sin repetir puntas)
	var poly := PackedVector2Array()
	for p in pts:
		if poly.is_empty() or not poly[-1].is_equal_approx(p):
			poly.append(p)
	if poly[0].is_equal_approx(poly[-1]):
		poly.remove_at(poly.size() - 1)
	return poly


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / poly.size()


## Texel (y hacia abajo) -> espacio 3D (y hacia arriba), con el centro de la tableta en 0.
static func _to_3d(p: Vector2, z: float) -> Vector3:
	return Vector3((p.x - W / 2.0) * TEXEL, (H / 2.0 - p.y) * TEXEL, z)


static func _extrude(poly: PackedVector2Array, center: Vector2) -> ArrayMesh:
	var origin := _to_3d(center, 0.0)
	var zf := THICKNESS * TEXEL / 2.0
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		push_warning("tablet_mesh: no se pudo triangular un pedazo")

	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in tris:
		var p := poly[i]
		front.set_normal(Vector3.BACK)
		front.set_uv(Vector2(p.x / W, p.y / H))
		front.add_vertex(_to_3d(p, zf) - origin)
	# Reverso con el orden invertido (mira hacia -Z)
	for k in range(tris.size() - 1, -1, -1):
		var p := poly[tris[k]]
		back.set_normal(Vector3.FORWARD)
		back.set_uv(Vector2(1.0 - p.x / W, p.y / H))
		back.add_vertex(_to_3d(p, -zf) - origin)

	# Canto: un quad por arista, con la normal hacia afuera
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	var orient := 1.0 if area > 0.0 else -1.0
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	var v := THICKNESS / SIDE_TEX
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized() * orient
		var n := Vector3(n2.x, -n2.y, 0.0)
		var u2 := u + e.length() / SIDE_TEX
		var quad := [
			[_to_3d(a, zf), Vector2(u, 0)], [_to_3d(b, zf), Vector2(u2, 0)],
			[_to_3d(b, -zf), Vector2(u2, v)], [_to_3d(a, -zf), Vector2(u, v)],
		]
		for j in [0, 1, 2, 0, 2, 3]:
			side.set_normal(n)
			side.set_uv(quad[j][1])
			side.add_vertex(quad[j][0] - origin)
		u = u2

	var mesh := front.commit()
	back.commit(mesh)
	side.commit(mesh)
	return mesh

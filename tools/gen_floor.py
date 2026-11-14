"""Genera tiles de piso 16x16 (paleta gameboy-color-type1). Fill = tileable en los 4 lados; top = superficie arriba."""
import random, sys
from PIL import Image
S=16
OUT=sys.argv[1]
def C(*a): return a+(255,)
BLACK=C(0,0,0); WHITE=C(255,255,255)
G1,G2,G3,G4=C(82,82,82),C(148,148,148),C(165,165,165),WHITE
B0,B1,B2,B3=C(58,40,2),C(125,73,0),C(165,107,49),C(255,173,99)
LAVA1,LAVA2,LAVA3=C(230,0,0),C(255,66,0),C(255,222,0)
P0,P1,P2=C(91,49,91),C(83,82,140),C(139,140,222)
GR0,GR1=C(0,131,0),C(123,255,48)
I0,I1,I2,I3=C(1,99,198),C(100,165,255),C(139,140,222),WHITE
T0,T1,T2=C(0,132,134),C(101,164,155),C(255,231,197)

def wdist(a,b):
    dx=abs(a[0]-b[0]); dy=abs(a[1]-b[1])
    dx=min(dx,S-dx); dy=min(dy,S-dy)
    return (dx*dx+dy*dy)**.5

def voronoi(seed,n,gap=1.0):
    r=random.Random(seed)
    pts=[(r.uniform(0,S),r.uniform(0,S)) for _ in range(n)]
    cell=[[0]*S for _ in range(S)]; mort=[[False]*S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            d=sorted((wdist((x+.5,y+.5),p),i) for i,p in enumerate(pts))
            cell[y][x]=d[0][1]; mort[y][x]=(d[1][0]-d[0][0])<gap
    return cell,mort

def shade_cells(cell,mort,mortar,dark,mid,light,seed,speck=None,speck_n=0):
    r=random.Random(seed)
    im=Image.new('RGBA',(S,S))
    m=lambda x,y: mort[y%S][x%S]
    for y in range(S):
        for x in range(S):
            if m(x,y): c=mortar
            elif m(x,y-1) or m(x-1,y): c=light
            elif m(x,y+1) or m(x+1,y): c=dark
            else: c=mid
            im.putpixel((x,y),c)
    for _ in range(speck_n):
        x,y=r.randrange(S),r.randrange(S)
        if not m(x,y) and im.getpixel((x,y))==mid: im.putpixel((x,y),speck or dark)
    return im

def add_top(im,rows):
    """rows: lista de (color o funcion x->color) para las primeras filas."""
    im=im.copy()
    for y,row in enumerate(rows):
        for x in range(S):
            c=row(x) if callable(row) else row
            if c: im.putpixel((x,y),c)
    return im


def stones(rects,mortar,dark,mid,light,cracks=(),specks=(),speck_c=None):
    """Piedras redondeadas (rects con wrap) sobre mortero; luz arriba-izq, sombra abajo-der."""
    im=Image.new('RGBA',(S,S),mortar)
    for (rx,ry,w,h) in rects:
        for j in range(h):
            for i in range(w):
                if (i in (0,w-1)) and (j in (0,h-1)): continue
                if j==0 or i==0: c=light
                elif j==h-1 or i==w-1: c=dark
                else: c=mid
                im.putpixel(((rx+i)%S,(ry+j)%S),c)
    for x,y in cracks: im.putpixel((x%S,y%S),dark)
    for x,y in specks: im.putpixel((x%S,y%S),speck_c or light)
    return im
STONE_RECTS=[(0,0,8,7),(9,0,6,7),(4,8,7,7),(12,8,7,7)]
STONE_CRACKS=[(3,3),(4,4),(4,5),(11,2),(12,3),(7,11),(6,12),(15,11)]
STONE_SPECKS=[(2,2),(13,4),(6,10),(1,12)]

tiles={}
# 1. roca gris (adoquines)
rock=stones(STONE_RECTS,G1,G2,G3,G4,STONE_CRACKS,STONE_SPECKS,G4)
# corregir: mid=G3 pero oscuro=G2
tiles['floor_rock']=rock
tiles['floor_rock_top']=add_top(rock,[G4,G3,G3,G1])

# 2. roca volcanica (basalto con grietas de lava)
volc=stones(STONE_RECTS,LAVA2,BLACK,G1,G2,STONE_CRACKS,[],None)
volc.putpixel((8,0),LAVA1);volc.putpixel((11,15),LAVA1);volc.putpixel((15,6),LAVA1)
r=random.Random(5)
for _ in range(5):  # puntos brillantes en las grietas
    x,y=r.randrange(S),r.randrange(S)
    if volc.getpixel((x,y))==LAVA2: volc.putpixel((x,y),LAVA3)
tiles['floor_volcanic']=volc
tiles['floor_volcanic_top']=add_top(volc,[lambda x:G2 if x%7 else G1,G1,lambda x:BLACK if x%3==0 else None])
# variante enfriada (grietas oscuras, sin lava)
tiles['floor_volcanic_cold']=stones(STONE_RECTS,BLACK,BLACK,G1,G2,STONE_CRACKS,[],None)

# 3. ladrillos de templo (violeta, estilo mazmorra)
def bricks(mortar,dark,mid,light,seed):
    r=random.Random(seed); im=Image.new('RGBA',(S,S))
    for y in range(S):
        row=y//4; off=0 if row%2==0 else 4
        for x in range(S):
            yy=y%4; xx=(x+off)%8
            if yy==3 or xx==7: c=mortar
            elif yy==0 or xx==0: c=light
            elif yy==2 or xx==6: c=dark
            else: c=mid
            im.putpixel((x,y),c)
    for _ in range(4):
        x,y=r.randrange(S),r.randrange(S)
        if im.getpixel((x,y))==mid: im.putpixel((x,y),dark)
    return im
temple=bricks(BLACK,P0,P1,P2,7)
tiles['floor_temple']=temple
tiles['floor_temple_top']=add_top(temple,[P2,P2,P1,BLACK])

# 4. tierra con pasto
def dirt(seed):
    r=random.Random(seed); im=Image.new('RGBA',(S,S),B1)
    for _ in range(14):
        x,y=r.randrange(S),r.randrange(S); im.putpixel((x,y),B0)
    for x,y in [(2,3),(11,6),(6,10),(14,13),(3,14)]:  # piedritas: claro arriba, oscuro abajo
        im.putpixel((x,y),B3); im.putpixel((x,(y+1)%S),B2); im.putpixel(((x+1)%S,(y+1)%S),B0)
    return im
d=dirt(4)
tiles['floor_dirt']=d
grass_h=[3,4,3,2,3,4,5,4,3,3,2,3,4,3,4,4]
gt=d.copy()
for x in range(S):
    h=grass_h[x]
    for y in range(h+1):
        gt.putpixel((x,y), GR1 if y==0 or (y==1 and x%3==0) else (B0 if y==h else GR0))
    if x%4==1: gt.putpixel((x,h+1),GR0)  # raicillas
tiles['floor_dirt_top']=gt

# 5. hielo / cristal
c,m=voronoi(21,3,0.5)
ice=shade_cells(c,m,I0,I0,I1,I3,3)
r=random.Random(9)
for _ in range(4):  # destellos diagonales
    x,y=r.randrange(S-2),r.randrange(S-2)
    if ice.getpixel((x,y))==I1: ice.putpixel((x,y),I3); ice.putpixel((x+1,y+1),I2)
tiles['floor_ice']=ice
tiles['floor_ice_top']=add_top(ice,[I3,lambda x:I3 if x%4 else I1,I1,lambda x:I0 if x%6==3 else None])

# 6. metal / ruina tecnologica (placas remachadas)
def metal():
    im=Image.new('RGBA',(S,S),T1)
    for y in range(S):
        for x in range(S):
            xx,yy=x%8,y%8
            if xx==7 or yy==7: c=BLACK
            elif xx==0 or yy==0: c=T2 if (xx+yy)%3 else T1
            elif xx==6 or yy==6: c=T0
            else: c=T1
            im.putpixel((x,y),c)
    for px,py in [(1,1),(5,1),(1,5),(5,5)]:
        for ox in (0,8):
            for oy in (0,8):
                im.putpixel((px+ox,py+oy),T0)
    return im
met=metal()
tiles['floor_metal']=met
tiles['floor_metal_top']=add_top(met,[T2,T1,lambda x:LAVA3 if (x//2)%2==0 else BLACK,BLACK])

for name,im in tiles.items():
    im.save(f'{OUT}/{name}_spr_0.png')

# preview: cada tile x3 repetido en fila (top arriba, fill abajo) escalado
groups=[('floor_rock','floor_rock_top'),('floor_volcanic','floor_volcanic_top'),('floor_volcanic_cold','floor_volcanic_top'),
        ('floor_temple','floor_temple_top'),('floor_dirt','floor_dirt_top'),('floor_ice','floor_ice_top'),('floor_metal','floor_metal_top')]
W=len(groups)*(S*4+8); H=S*4
pv=Image.new('RGBA',(W,H),C(40,40,60))
for i,(f,t) in enumerate(groups):
    for gx in range(4):
        for gy in range(4):
            pv.paste(tiles[t] if gy==0 else tiles[f],(i*(S*4+8)+gx*S,gy*S))
pv.resize((W*4,H*4),Image.NEAREST).save(sys.argv[2])

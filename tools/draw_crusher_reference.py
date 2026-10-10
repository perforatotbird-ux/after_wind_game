"""Референс дробилки (docs/art/crusher_reference.svg): вид спереди и сбоку, анимация, палитра.
Запуск из корня проекта: python3 tools/draw_crusher_reference.py"""
import math
S=300
out=[]
def P(x,z,ox,oz): return (ox+x*S, oz-z*S)
def poly(pts,fill,stroke="#2a2622",sw=3,ox=0,oz=0,extra=""):
    d=" ".join("%.1f,%.1f"%P(x,z,ox,oz) for x,z in pts)
    out.append(f'<polygon points="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" {extra}/>')
def rect(x0,z0,x1,z1,fill,ox,oz,sw=3,extra=""):
    poly([(x0,z0),(x1,z0),(x1,z1),(x0,z1)],fill,ox=ox,oz=oz,sw=sw,extra=extra)
def circ(x,z,r,fill,ox,oz,sw=3,stroke="#2a2622",extra=""):
    cx,cy=P(x,z,ox,oz); out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r*S:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')
def text(x,y,s,size=20,fill="#2d2a26",w="normal",anchor="start"):
    out.append(f'<text x="{x}" y="{y}" font-family="Arial" font-size="{size}" fill="{fill}" font-weight="{w}" text-anchor="{anchor}">{s}</text>')
def line(pts,stroke,sw,ox,oz,extra=""):
    d=" ".join("%.1f,%.1f"%P(x,z,ox,oz) for x,z in pts)
    out.append(f'<polyline points="{d}" fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" {extra}/>')
Y="#d9a520"; YD="#a97c14"; IRON="#2b2d30"; RUST="#7b4a2a"; WOOD="#8a7a64"; GALV="#9aa3a8"; GRAV="#8d8b86"; GREEN="#4f6b4a"
W,H=1960,1160
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
out.append('<defs><pattern id="haz" width="28" height="28" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="14" height="28" fill="#1d1d1d"/><rect x="14" width="14" height="28" fill="#e2b11f"/></pattern>'
 '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#cfd8dc"/><stop offset="1" stop-color="#eef0ea"/></linearGradient>'
 '<linearGradient id="yel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#e7b733"/><stop offset="1" stop-color="#b98a18"/></linearGradient></defs>')
out.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
text(40,62,"Дробилка камня — референс",40,w="bold")
text(40,98,"Щековая дробилка «После бури»: жёлтый корпус со сколами, чугунные маховики, мотор с ремнём, бункер с камнями, лоток со щебнем. Масштаб 1 м = 300 px.",20)
ox,oz=600,1000
text(ox,140,"Вид спереди (к двору, +Z в Godot)",24,w="bold",anchor="middle")
out.append(f'<rect x="{ox-560}" y="{oz}" width="1120" height="20" fill="#6f8f3a"/>')
rect(-1.0,0,1.0,0.14,WOOD,ox,oz)
for sx in (-1,1):
    x=0.45*sx
    poly([(x-0.06,0.14),(x+0.06,0.14),(x+0.06,0.16),(x+0.008,0.16),(x+0.008,0.28),(x+0.06,0.28),(x+0.06,0.30),(x-0.06,0.30),(x-0.06,0.28),(x-0.008,0.28),(x-0.008,0.16),(x-0.06,0.16)],RUST,ox=ox,oz=oz,sw=2)
rect(-0.55,0.30,0.55,0.32,"#5a5d61",ox,oz)
for sx in (-1,1):
    rect(0.62*sx,0.53,0.71*sx,1.57,IRON,ox,oz)
    rect(0.58*sx,0.96,0.80*sx,1.14,"#3b3e42",ox,oz)
rect(-0.82,1.02,0.82,1.08,"#6d7278",ox,oz,sw=2)
rect(-0.48,0.32,0.48,1.12,"url(#yel)",ox,oz)
for x in (-0.25,0,0.25):
    rect(x-0.025,0.45,x+0.025,1.12,YD,ox,oz,sw=2)
rect(-0.40,0.32,0.40,0.45,"#3a3632",ox,oz)
poly([(0.08,0.62),(0.33,0.60),(0.35,0.86),(0.10,0.88)],"#6b6f73",ox=ox,oz=oz,sw=2)
for x,z in ((0.11,0.64),(0.31,0.63),(0.32,0.84),(0.12,0.85),(-0.42,0.4),(0.42,0.4),(-0.42,1.05),(0.42,1.05)):
    circ(x,z,0.014,"#8d9298",ox,oz,sw=1.5)
for x,z,r in ((-0.44,0.9,0.03),(0.2,1.08,0.025),(-0.1,0.5,0.02),(0.46,0.6,0.02)):
    circ(x,z,r,"#4a4642",ox,oz,sw=0)
for x in (-0.42,0.42,0.12):
    line([(x,1.0),(x+0.005,0.78)],"#8a4a22",5,ox,oz,'opacity="0.55"')
poly([(-0.40,1.12),(0.40,1.12),(0.65,1.69),(-0.65,1.69)],"url(#yel)",ox=ox,oz=oz)
poly([(-0.66,1.69),(0.66,1.69),(0.67,1.76),(-0.67,1.76)],"url(#haz)",ox=ox,oz=oz)
for t in (0.33,0.66):
    a=-0.40-0.25*t; b=1.12+0.57*t
    line([(a,b),(-a,b)],"#8d6a12",2,ox,oz)
for i in range(9):
    x=-0.6+i*0.15; circ(x,1.66,0.01,"#8d9298",ox,oz,sw=1)
for x,z,r in ((-0.45,1.8,0.08),(-0.25,1.83,0.1),(-0.02,1.8,0.09),(0.2,1.84,0.11),(0.42,1.79,0.08),(0.05,1.88,0.07)):
    circ(x,z,r,"#8e8a83",ox,oz,sw=2)
rect(-0.22,1.30,0.22,1.44,"#efeae0",ox,oz,sw=2)
text(ox,oz-1.335*S,"ДРОБИЛКА",22,fill="#2b2826",w="bold",anchor="middle")
poly([(-0.30,0.42),(0.30,0.42),(0.32,0.20),(-0.32,0.20)],GALV,ox=ox,oz=oz)
poly([(-0.26,0.38),(0.26,0.38),(0.28,0.24),(-0.28,0.24)],GRAV,ox=ox,oz=oz,sw=0)
poly([(-0.5,0.0),(-0.25,0.12),(0.0,0.16),(0.28,0.11),(0.52,0.0)],GRAV,ox=ox,oz=oz)
rect(-0.92,0.0,-0.88,0.85,"#5a5d61",ox,oz,sw=2)
rect(-1.0,0.85,-0.80,1.08,"#b23a2a",ox,oz)
circ(-0.9,1.12,0.035,"#57e36b",ox,oz,sw=2)
circ(-0.9,0.94,0.04,"#e04030",ox,oz,sw=2)
def label(x1,y1,x2,y2,s):
    out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#2d2a26" stroke-width="1.5"/>'); text(x2+(6 if x2>x1 else -6),y2+6,s,18,anchor="start" if x2>x1 else "end")
label(*P(0.6,1.76,ox,oz),ox+280,oz-570,"бункер, полосы на кромке, камни")
label(*P(0.68,0.8,ox,oz),ox+300,oz-330,"маховики Ø1.05 м (вращаются)")
label(*P(0.25,0.7,ox,oz),ox+300,oz-200,"сварная заплата, болты")
label(*P(0.2,0.3,ox,oz),ox+300,oz-70,"лоток: сыплется щебень и пыль")
label(*P(-0.9,1.12,ox,oz),ox-280,oz-420,"пульт: зелёная лампа «работа»")
label(*P(-0.75,0.07,ox,oz),ox-280,oz-30,"двутавры на шпалах")
ox,oz=1450,1000
text(ox,140,"Вид сбоку (справа): привод и анимация",24,w="bold",anchor="middle")
out.append(f'<rect x="{ox-480}" y="{oz}" width="960" height="20" fill="#6f8f3a"/>')
def sp(y,z): return (y,z)   # фасад (-Y) слева
for y in (-0.6,0.9): rect(*sp(y-0.12,0),*sp(y+0.12,0.14),WOOD,ox,oz)
rect(*sp(-0.85,0.14),*sp(1.25,0.30),RUST,ox,oz)
poly([sp(-0.5,0.32),sp(0.6,0.32),sp(0.6,0.62),sp(0.45,0.95),sp(0.05,0.95),sp(0.05,1.12),sp(-0.5,1.12)],"url(#yel)",ox=ox,oz=oz)
for y in (-0.3,0.0,0.3): rect(*sp(y-0.025,0.32),*sp(y+0.025,0.94 if y>0 else 1.12),YD,ox,oz,sw=2)
poly([sp(-0.475,1.12),sp(0.075,1.12),sp(0.3,1.69),sp(-0.7,1.69)],"url(#yel)",ox=ox,oz=oz)
poly([sp(-0.71,1.69),sp(0.31,1.69),sp(0.31,1.76),sp(-0.71,1.76)],"url(#haz)",ox=ox,oz=oz)
for y,z,r in ((-0.55,1.8,0.08),(-0.3,1.84,0.1),(-0.05,1.8,0.09),(0.15,1.79,0.07)): circ(*sp(y,z),r,"#8e8a83",ox,oz,sw=2)
rect(*sp(0.8,0.30),*sp(1.2,0.34),"#5a5d61",ox,oz)
circ(*sp(1.0,0.55),0.16,GREEN,ox,oz)
for k in range(8):
    a=k*math.pi/4; line([sp(1.0+0.16*math.cos(a),0.55+0.16*math.sin(a)),sp(1.0+0.19*math.cos(a),0.55+0.19*math.sin(a))],"#3d5539",5,ox,oz)
rect(*sp(0.92,0.71),*sp(1.08,0.80),"#3d5539",ox,oz,sw=2)
c1=(0.25,1.05,0.53); c2=(1.0,0.55,0.12)
dx,dz=c2[0]-c1[0],c2[1]-c1[1]; d=math.hypot(dx,dz); base=math.atan2(dz,dx); a=math.acos((c1[2]-c2[2])/d)
for s in (1,-1):
    t=base+s*a
    p1=(c1[0]+c1[2]*math.cos(t),c1[1]+c1[2]*math.sin(t)); p2=(c2[0]+c2[2]*math.cos(t),c2[1]+c2[2]*math.sin(t))
    line([sp(*p1),sp(*p2)],"#151515",8,ox,oz)
circ(*sp(1.0,0.55),0.11,"#55595e",ox,oz)
circ(*sp(1.0,0.55),0.03,IRON,ox,oz)
circ(*sp(0.25,1.05),0.53,"none",ox,oz,sw=10,stroke="#151515")
circ(*sp(0.25,1.05),0.52,"none",ox,oz,sw=18,stroke=IRON)
for k in range(6):
    a0=k*math.pi/3; pts=[]
    for i in range(9):
        t=i/8; r=0.09+t*0.37; a=a0+0.35*math.sin(t*math.pi)
        pts.append(sp(0.25+r*math.cos(a),1.05+r*math.sin(a)))
    line(pts,IRON,13,ox,oz)
circ(*sp(0.25,1.05),0.09,"#3b3e42",ox,oz)
circ(*sp(0.25,1.05),0.04,"#6d7278",ox,oz,sw=2)
rect(*sp(0.25-0.04,1.05+0.47),*sp(0.25+0.04,1.05+0.53),Y,ox,oz,sw=2)
poly([sp(-0.42,0.45),sp(-0.42,0.38),sp(-0.98,0.17),sp(-0.98,0.26)],GALV,ox=ox,oz=oz)
poly([sp(-1.4,0.0),sp(-1.2,0.1),sp(-1.05,0.13),sp(-0.85,0.0)],GRAV,ox=ox,oz=oz)
for i,(y,z) in enumerate(((-1.02,0.2),(-1.05,0.15),(-1.08,0.1),(-1.03,0.07))): circ(*sp(y,z),0.012,"#77746f",ox,oz,sw=0)
def arc_arrow(cx,cz,r,a0,a1,col,s):
    pts=[sp(cx+r*math.cos(a0+(a1-a0)*i/20),cz+r*math.sin(a0+(a1-a0)*i/20)) for i in range(21)]
    line(pts,col,4,ox,oz,'stroke-dasharray="10,6"')
    x,y=P(*pts[-1],ox,oz); text(x+8,y,s,18,fill=col,w="bold")
arc_arrow(0.25,1.05,0.68,math.radians(60),math.radians(140),"#c0392b","≈1.6 об/с")
arc_arrow(1.0,0.55,0.26,math.radians(-60),math.radians(40),"#c0392b","×4.8")
text(ox-450,oz-1.3*S,"шатун ходит",18,fill="#c0392b",w="bold"); text(ox-450,oz-1.3*S+22,"по эксцентрику ±3 см",18,fill="#c0392b")
text(ox+330,oz-0.95*S,"мотор, шкив,",18); text(ox+330,oz-0.95*S+22,"клиновой ремень",18)
px,py=60,1080
for i,(c,n) in enumerate(((Y,"краска"),("#4a4642","сколы"),("#8a4a22","ржавчина"),(IRON,"чугун"),(GALV,"оцинковка"),(GREEN,"мотор"),(WOOD,"шпалы"),(GRAV,"щебень"),("#151515","резина"),("#57e36b","лампа"))):
    x=px+i*185; out.append(f'<rect x="{x}" y="{py}" width="40" height="40" rx="6" fill="{c}" stroke="#2a2622" stroke-width="2"/>'); text(x+50,py+27,n,18)
out.append('</svg>')
open('docs/art/crusher_reference.svg','w', encoding='utf-8').write("\n".join(out))

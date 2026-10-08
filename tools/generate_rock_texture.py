"""Тайлящаяся текстура камня (шум + сеть трещин) для tools/generate_rocks.gd.

Пишет .godot/rock_albedo.png (кэш, не в git); generate_rocks.gd встраивает её
в материал rock_material.tres как оттенки серого с mipmap-ами.
Запуск из корня проекта: python3 tools/generate_rock_texture.py
"""
import os
import numpy as np
from PIL import Image
N=512;rng=np.random.default_rng(7)
def fnoise(beta,seed):
    r=np.random.default_rng(seed);k=np.fft.fftfreq(N)[:,None]**2+np.fft.fftfreq(N)[None,:]**2
    k[0,0]=1;spec=(r.normal(size=(N,N))+1j*r.normal(size=(N,N)))/k**(beta/2);spec[0,0]=0
    n=np.real(np.fft.ifft2(spec));return (n-n.mean())/n.std()
base=0.6*fnoise(2.2,1)+0.25*fnoise(1.4,2)+0.15*fnoise(0.6,3)
# tileable voronoi cracks
P=rng.random((26,2))*N
yy,xx=np.mgrid[0:N,0:N].astype(float)
wx=xx+fnoise(2.3,21)*14+fnoise(1.6,22)*3;wy=yy+fnoise(2.3,23)*14+fnoise(1.6,24)*3
d=[]
for px,py in P:
    dx=np.abs(wx-px);dx=np.minimum(dx,N-dx);dy=np.abs(wy-py);dy=np.minimum(dy,N-dy);d.append(np.hypot(dx,dy))
d=np.sort(np.stack(d),0);edge=d[1]-d[0]
warp=fnoise(2.0,5)
mask=(fnoise(2.6,9)>0.25)  # only part of edges become cracks
w=1.2+0.8*np.clip(fnoise(2.2,31),-1,1)
cm=np.clip((fnoise(2.6,9)+0.1)*2.0,0,1)
crack=np.clip(1-edge/w,0,1)**1.5*cm
fine=np.clip(1-np.abs(fnoise(2.4,11))*18,0,1)*(fnoise(2.5,12)>0.6)  # hairline cracks
v=0.84+0.09*base-0.42*crack-0.18*fine
speck=fnoise(0.2,13);v-=0.05*(speck>2.2)
v=np.clip(v,0,1)
img=(np.stack([v*0.97,v*0.985,v*1.0],-1)*255).astype(np.uint8)
os.makedirs('.godot',exist_ok=True)
Image.fromarray(img).save('.godot/rock_albedo.png')
print('OK: .godot/rock_albedo.png', round(float(v.mean()),3))

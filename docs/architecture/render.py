#!/usr/bin/env python3
"""Render with Python stdlib + libfreetype; usage: python3 render.py /path/to/font.ttc"""
import ctypes as C
import ctypes.util
import math
import struct
import sys
import zlib
from pathlib import Path
from html import escape
W,H=2480,1960
pixels=bytearray(bytes.fromhex('f4f7fb')*(W*H))
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="100%" height="100%" fill="#f4f7fb"/>']
if len(sys.argv) != 2:
 raise SystemExit('Usage: python3 render.py /path/to/font.ttc')
ft_name=ctypes.util.find_library('freetype')
if not ft_name:
 raise SystemExit('libfreetype is required')
ft=C.CDLL(ft_name)
class Vec(C.Structure): _fields_=[('x',C.c_long),('y',C.c_long)]
class Bitmap(C.Structure): _fields_=[('rows',C.c_uint),('width',C.c_uint),('pitch',C.c_int),('buffer',C.POINTER(C.c_ubyte)),('num_grays',C.c_ushort),('pixel_mode',C.c_ubyte),('palette_mode',C.c_ubyte),('palette',C.c_void_p)]
class Generic(C.Structure): _fields_=[('data',C.c_void_p),('finalizer',C.c_void_p)]
class Slot(C.Structure): _fields_=[('library',C.c_void_p),('face',C.c_void_p),('next',C.c_void_p),('index',C.c_uint),('generic',Generic),('metrics',C.c_long*8),('linearHoriAdvance',C.c_long),('linearVertAdvance',C.c_long),('advance',Vec),('format',C.c_uint),('bitmap',Bitmap),('bitmap_left',C.c_int),('bitmap_top',C.c_int)]
class Face(C.Structure): _fields_=[('num_faces',C.c_long),('face_index',C.c_long),('face_flags',C.c_long),('style_flags',C.c_long),('num_glyphs',C.c_long),('family_name',C.c_char_p),('style_name',C.c_char_p),('num_fixed_sizes',C.c_int),('available_sizes',C.c_void_p),('num_charmaps',C.c_int),('charmaps',C.c_void_p),('generic',Generic),('bbox',C.c_long*4),('units_per_EM',C.c_ushort),('ascender',C.c_short),('descender',C.c_short),('height',C.c_short),('max_advance_width',C.c_short),('max_advance_height',C.c_short),('underline_position',C.c_short),('underline_thickness',C.c_short),('glyph',C.POINTER(Slot))]
lib=C.c_void_p(); assert ft.FT_Init_FreeType(C.byref(lib))==0
face=C.POINTER(Face)(); assert ft.FT_New_Face(lib,sys.argv[1].encode(),0,C.byref(face))==0
ft.FT_Get_Char_Index.argtypes=[C.POINTER(Face),C.c_ulong]
ft.FT_Load_Char.argtypes=[C.POINTER(Face),C.c_ulong,C.c_int32]
used=set()
def rgb(c): return bytes.fromhex(c.lstrip('#'))
def put(x,y,col,a=255):
 if 0<=x<W and 0<=y<H:
  i=(y*W+x)*3
  if a==255: pixels[i:i+3]=col
  elif a:
   for k in range(3): pixels[i+k]=(col[k]*a+pixels[i+k]*(255-a))//255

def rect(x,y,w,h,fill,stroke='#ced9e5'):
 col=rgb(fill); edge=rgb(stroke)
 for yy in range(y,y+h):
  pixels[(yy*W+x)*3:(yy*W+x+w)*3]=col*w
 for xx in range(x,x+w):
  put(xx,y,edge); put(xx,y+h-1,edge)
 for yy in range(y,y+h): put(x,yy,edge); put(x+w-1,yy,edge)
 svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}"/>')
def text(x,y,s,size=24,color='#20334b'):
 ft.FT_Set_Pixel_Sizes(face,0,size); cursor=x
 for ch in s:
  used.add(ch); assert ft.FT_Get_Char_Index(face,ord(ch)), f'Missing glyph: {ch}'
  assert ft.FT_Load_Char(face,ord(ch),4)==0
  g=face.contents.glyph.contents; b=g.bitmap
  for yy in range(b.rows):
   for xx in range(b.width): put(cursor+g.bitmap_left+xx,y-g.bitmap_top+yy,rgb(color),b.buffer[yy*b.pitch+xx])
  cursor+=g.advance.x//64
 assert cursor<W-15,(s,cursor)
 svg.append(f'<text x="{x}" y="{y}" font-family="WenQuanYi Zen Hei, Noto Sans CJK TC, sans-serif" font-size="{size}" fill="{color}">{escape(s)}</text>')
def line(points,color='#3375b9',width=3,arrow=True):
 col=rgb(color)
 for (x1,y1),(x2,y2) in zip(points,points[1:]):
  n=max(abs(x2-x1),abs(y2-y1),1)
  for t in range(n+1):
   x=round(x1+(x2-x1)*t/n); y=round(y1+(y2-y1)*t/n)
   for dx in range(-width//2,width//2+1):
    for dy in range(-width//2,width//2+1): put(x+dx,y+dy,col)
 svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in points)}" fill="none" stroke="{color}" stroke-width="{width}"/>')
 if arrow:
  x,y=points[-1]; px,py=points[-2]; angle=math.atan2(y-py,x-px)
  for a in [angle-.5,angle+.5]: line([(round(x-14*math.cos(a)),round(y-14*math.sin(a))),(x,y)],color,width,False)
def box(x,y,w,h,title,lines,fill='#ffffff',color='#20334b'):
 assert len(lines) <= 1, 'Each box has at most two lines'
 rect(x,y,w,h,fill); text(x+22,y+40,title,30,color)
 for s in lines: text(x+22,y+80,s,27)

def dashed_container(x,y,w,h):
 # Use the same dash geometry for the raster and vector outputs.
 for start,end,fixed,horizontal in [
     (x,x+w,y,True),(x,x+w,y+h,True),
     (y,y+h,x,False),(y,y+h,x+w,False)]:
  for a in range(start,end,20):
   b=min(a+11,end)
   points=[(a,fixed),(b,fixed)] if horizontal else [(fixed,a),(fixed,b)]
   line(points,'#78909f',2,False)

def process_tag(x,y,label='process'):
 text(x,y,label,18,'#607586')

def process_box(x,y,w,title,role,fill,title_size=28,label='process'):
 rect(x,y,w,130,fill)
 tag_x=x+w-90
 if label != 'process':
  # Preserve the original right margin using the same advances as text().
  ft.FT_Set_Pixel_Sizes(face,0,18)
  for value,direction in [(label,-1),('process',1)]:
   for ch in value:
    assert ft.FT_Load_Char(face,ord(ch),4)==0
    tag_x+=direction*(face.contents.glyph.contents.advance.x//64)
 process_tag(tag_x,y+23,label)
 text(x+20,y+59,title,title_size)
 text(x+20,y+103,role,22 if title.startswith('③') else 25,'#435b70')

# Complete namespace rectangles and separate routing corridors.
text(50,75,'rdp-vscode｜系統運作架構',44)
rect(410,130,2020,1640,'#eaf1f9','#93adc7')
text(440,178,'Kubernetes 叢集',32)
rect(440,350,1180,1300,'#f8fbff','#9fb9d3')
text(1000,395,'namespace：rdp-vscode',30)
rect(470,710,1130,920,'#ffffff','#6e98bf')
text(500,752,'rdp-vscode Pod',32)
dashed_container(490,775,1090,830)
text(520,818,'container：desktop（單一 container）',27)
text(520,855,'ghcr.io/braveantony/rdp-vscode:1.2',24,'#596e85')
rect(1650,800,750,640,'#f8fbff','#9fb9d3')
text(1680,845,'namespace：taroko',30)

box(40,220,320,110,'Windows mstsc',['Mac Windows App'])
text(48,375,'連入即是 VSCodium',26,'#3375b9')
box(500,220,550,110,'叢集節點（node）',['NodePort :30390'])
box(500,430,550,110,'Service：rdp-vscode',['30390 → 3389'])
box(1100,430,450,110,'Secret',['/etc/rdp-vscode/users'],'#fff7e9')
box(1100,570,450,110,'ConfigMap（選用）',['/etc/rdp-vscode/ssh/config'],'#fff7e9')
process_box(520,890,980,'① xrdp :3389／xrdp-sesman',
            '驗證帳號、每次登入開一個新桌面','#edf5ff',30,label='processes')
rect(520,1130,980,300,'#eef8f4')
text(1400,1155,'session',18,'#607586')
text(542,1180,'② Xorg session × N',30)
text(542,1220,'每次登入一個獨立桌面',25,'#435b70')
text(542,1255,'openbox · 關掉 VSCodium 就登出',23,'#596e85')
rect(550,1300,920,110,'#ffffff')
process_tag(1370,1324)
text(572,1348,'VSCodium（全螢幕）',30)
text(572,1390,'Open Remote-SSH · 繁中語言包 · Integrated Browser',25,'#435b70')
line([(1000,1268),(1000,1300)],width=6)
rect(520,1490,450,85,'#f1f4f7')
text(885,1513,'volume',18,'#607586')
text(540,1550,'/home：emptyDir 或 PVC',26)
rect(1000,1490,370,85,'#f1f4f7')
text(1285,1513,'volume',18,'#607586')
text(1020,1550,'/dev/shm：記憶體 1Gi',26)

# tkadm contains both its remote editor process and kubectl.
rect(1680,880,690,530,'#edf8f8')
text(1700,925,'叢集管理 Pod：tkadm',30)
text(1700,969,'tkadm.taroko :22100',27)
text(1700,1008,'sshd：AllowTcpForwarding local',24,'#596e85')
process_box(1700,1080,650,'③ vscodium-server',
            '~/.vscodium-server（Alpine 版，首次連線自動下載）','#ffffff',30)
# The server path stays on one line inside the process box.
box(1700,1280,210,100,'kubectl',[])
# The cluster API sits outside taroko, above the Web service.
box(2020,1455,330,60,'Kubernetes API',[],'#fff7ed')
box(1680,1530,690,150,'你的 Web 服務',
    ['http://<svc>.<ns>.svc.<cluster-domain>'],'#fff7ed')

# Thick blue desktop route, with provisioning kept to its right.
line([(360,275),(500,275)],width=6)
text(415,253,'RDP',25,'#3375b9')
line([(760,330),(760,430)],width=6)
line([(760,540),(480,540),(480,950),(520,950)],width=6)
line([(1000,1020),(1000,1130)],width=6)
text(1025,1080,'開新桌面',25,'#3375b9')
line([(1550,485),(1560,485),(1560,945),(1500,945)],'#b78a3f')
text(1430,875,'帳號',25,'#b78a3f')
# ConfigMap terminates at the container boundary before the account route.
line([(1320,680),(1320,775)],'#b78a3f')
text(1350,735,'SSH 設定',25,'#b78a3f')

# Green and orange paths leave distinct edges and never intersect.
line([(1470,1350),(1635,1350),(1635,700),(2300,700),(2300,880)],'#298b68',3)
text(1665,680,'SSH（輸入 tkadm 密碼）',27,'#298b68')
line([(2020,1025),(2020,1080)],'#298b68',3)
text(2045,1063,'轉發',25,'#298b68')
line([(1910,1330),(1980,1330),(1980,1485),(2020,1485)],'#cf7b32',3)
text(2005,1395,'kubectl apply',23,'#cf7b32')
line([(1400,1410),(1400,1715),(2020,1715),(2020,1680)],'#cf7b32',3)
text(1660,1750,'Integrated Browser',27,'#cf7b32')
text(440,1840,'粗藍：VSCodium 桌面主路徑　　綠：SSH　　橙：HTTP／kubectl　　金：帳號與設定',27,'#596e85')
text(440,1890,'虛線框 = container，內部方塊 = process(es)／session／volume',27,'#596e85')
out=Path(__file__).resolve().parent
svg.append('</svg>'); (out/'rdp-vscode-architecture.svg').write_text('\n'.join(svg))
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
raw=b''.join(b'\0'+pixels[y*W*3:(y+1)*W*3] for y in range(H))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,H,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
(out/'rdp-vscode-architecture.png').write_bytes(png)
print(f'PNG {W}x{H}: {len(png)} bytes; verified {len(used)} glyphs; font: {face.contents.family_name.decode()}')

ft.FT_Done_Face(face)
ft.FT_Done_FreeType(lib)

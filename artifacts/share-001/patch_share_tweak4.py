# Stage SHARE-TWEAK4 (2026-10-17) — แก้บั๊ก: PDF ที่ตั้งค่าหมุนหน้าไว้ในไฟล์ (/Rotate เช่นเอกสารสแกนแนวนอน)
#   แสดงตะแคง เพราะปุ่มหมุนของเราไปทับค่าหมุนเดิมของไฟล์ → ใช้ (ค่าหมุนของไฟล์ + ค่าที่ผู้ใช้กดหมุน)
import sys,io,re
path=sys.argv[1]
s=io.open(path,encoding='utf-8',newline='').read()
if 'Stage SHARE-TWEAK4' in s: raise SystemExit('already patched')
if 'Stage SHARE-TWEAK3' not in s: raise SystemExit('needs SHARE-TWEAK3 first')
a=s.count('pg.page.getViewport({scale:1, rotation:my.rot})')
b=s.count('pg.page.getViewport({scale, rotation:my.rot})')
c=s.count('page.getViewport({scale:1, rotation:my.rot})')-a
d=s.count('page.getViewport({scale, rotation:my.rot})')-b
if (a,b,c,d)!=(2,1,1,1): raise SystemExit(f'unexpected counts {(a,b,c,d)}')
s=s.replace('pg.page.getViewport({scale:1, rotation:my.rot})','pg.page.getViewport({scale:1, rotation:(pg.page.rotate+my.rot)%360})')
s=s.replace('pg.page.getViewport({scale, rotation:my.rot})','pg.page.getViewport({scale, rotation:(pg.page.rotate+my.rot)%360})')
s=s.replace('page.getViewport({scale:1, rotation:my.rot})','page.getViewport({scale:1, rotation:(page.rotate+my.rot)%360})')
s=s.replace('page.getViewport({scale, rotation:my.rot})','page.getViewport({scale, rotation:(page.rotate+my.rot)%360})')
assert 'rotation:my.rot}' not in s
s=s.replace('// ── Stage SHARE-TWEAK3: แถบเครื่องมือ PDF ──','// ── Stage SHARE-TWEAK3: แถบเครื่องมือ PDF ── (Stage SHARE-TWEAK4: หมุน = ค่าหมุนของไฟล์ + ที่ผู้ใช้กด)',1)
assert 'Stage SHARE-TWEAK4' in s
io.open(path,'w',encoding='utf-8',newline='').write(s)
print('patched',path)

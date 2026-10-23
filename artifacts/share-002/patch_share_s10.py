# Stage SHARE-S10 — บรรทัดสรุปบนหัว ใช้เกณฑ์เดียวกับการ์ด (ตัวเลขตรงกับหัวข้อ "ต้องดำเนินการ")
#   นับเอกสารที่ขึ้นสีส้ม (ใกล้ครบตามวันแจ้งเตือนใน CRM) + สีแดง (เลยกำหนด)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage SHARE-S10' in t: print('already'); sys.exit(0)
assert 'Stage SHARE-S8' in t, 'run patch_share_s8.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("""  let n=0; const ppl=new Set(); let over=0;
  DATA.workers.forEach(w=>DOCS.forEach(doc=>{const d=days(w.dates&&w.dates[doc.k]); if(d===null) return; if(d<0){over++;return;} if(d<=30){n++;ppl.add(w.id);}}));""","""  // Stage SHARE-S10: เกณฑ์เดียวกับการ์ด — ส้ม (ใกล้ครบ) + แดง (เลยกำหนด)
  let n=0; const ppl=new Set(); let over=0;
  DATA.workers.forEach(w=>DOCS.forEach(doc=>{const s=st(doc,w.dates&&w.dates[doc.k]); if(s.c==='warn'||s.c==='bad'){n++;ppl.add(w.id);if(s.c==='bad')over++;}}));""")
rep("""(n?`30 วันข้างหน้า ครบกำหนด <b>${n}</b> ฉบับ (${ppl.size} คน)`:'30 วันข้างหน้า ไม่มีเอกสารครบกำหนด')+(over?` · เลยกำหนด <b>${over}</b> ฉบับ`:'')""","""(n?`ต้องดำเนินการ <b>${n}</b> ฉบับ (${ppl.size} คน)`:'เอกสารทุกฉบับปกติ ยังไม่มีเรื่องต้องดำเนินการ')+(over?` · เลยกำหนด <b>${over}</b> ฉบับ`:'')""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

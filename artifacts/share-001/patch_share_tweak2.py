# Stage SHARE-TWEAK2 (2026-10-17) — ต่อจาก SHARE-TWEAK
#  - กรอบใส (แบบช่อง "ใกล้ครบกำหนด") รอบโลโก้ RUNGFAR และรอบชื่อนายจ้าง + คำบรรยาย
#  - คำบรรยาย: "ระบบติดตามเอกสารแรงงาน"
#  - แถบมืดบนหัวหน้ารายละเอียด อ่อนลง
#  - ป้ายสถานะในรายชื่อ: เล็กลง + สีชมพูอ่อน
import sys,io
path=sys.argv[1]
s=io.open(path,encoding='utf-8',newline='').read()
NL='\r\n' if s.count('\r\n')>s.count('\n')//2 else '\n'
def rep(old,new,count=1):
    global s
    old=old.replace('\n',NL); new=new.replace('\n',NL)
    n=s.count(old)
    if n!=count: raise SystemExit(f'anchor x{n} (want {count}): {old[:90]!r}')
    s=s.replace(old,new)
if 'Stage SHARE-TWEAK2' in s: raise SystemExit('already patched')
if 'Stage SHARE-TWEAK' not in s: raise SystemExit('needs SHARE-TWEAK first')

rep("""    <h1 id="empName">กำลังโหลดข้อมูล…</h1>
    <div class="sub" id="empSub">บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด</div>""",
"""    <div class="hdglass"><h1 id="empName">กำลังโหลดข้อมูล…</h1>
    <div class="sub" id="empSub">บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด</div></div>""")
rep("textContent='ข้อมูล เอกสารแรงงาน วันหมดอายุ'+", "textContent='ระบบติดตามเอกสารแรงงาน'+")
rep("'linear-gradient(180deg,rgba(0,0,0,.38) 0%,rgba(0,0,0,.66) 100%),'", "'linear-gradient(180deg,rgba(0,0,0,.16) 0%,rgba(0,0,0,.46) 100%),'")
rep("</style>","""/* Stage SHARE-TWEAK2 */
.hd .logo{background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.24);-webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px);padding:3px 13px 3px 3px;border-radius:99px}
.hdglass{width:fit-content;max-width:100%;margin-top:12px;background:rgba(255,255,255,.16);border:1px solid rgba(255,255,255,.24);-webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px);border-radius:14px;padding:8px 13px 9px}
.hdglass h1{margin-top:0}
.hd.has-bg .hdglass,.hd.has-bg .logo{text-shadow:0 1px 3px rgba(0,0,0,.35)}
.w .wst{max-width:27%;font-size:10.5px;line-height:1.3;padding:3px 8px;border-radius:9px;color:#b4235a;background:#fdeef2;border-color:#f7d4de;-webkit-line-clamp:2}
@media (min-width:700px){.w .wst{max-width:30%;font-size:11.5px;padding:4px 10px}}
</style>""")
io.open(path,'w',encoding='utf-8',newline='').write(s)
print('patched',path)

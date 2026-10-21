# Stage SHARE-TWEAK (2026-10-17)
#  - ไอคอนไฟล์ PDF = โลโก้ PDF สีแดงเดียวกับที่บอทสร้าง PDF ใช้ (ย่อเหลือ 64px ฝังในหน้า ~3.5KB)
#  - หัวหน้า: "สถานะเอกสารแรงงาน" → "ข้อมูล เอกสารแรงงาน วันหมดอายุ" + "ขอบคุณที่ใช้บริการ" ตัวเล็กมุมขวาล่าง
#  - หน้ารายละเอียดแรงงาน: พื้นหลังหัวใช้รูปเดียวกับหน้าแรก + แถบมืดให้อ่านตัวอักษรชัด
#  - การ์ดกำหนดวันเอกสาร: เล็กลง
import sys,io
path,icon_path=sys.argv[1],sys.argv[2]
s=io.open(path,encoding='utf-8',newline='').read()
NL='\r\n' if s.count('\r\n')>s.count('\n')//2 else '\n'
icon=io.open(icon_path,encoding='utf-8').read().strip()
assert icon.startswith('data:image/png;base64,') and len(icon)<8000
def rep(old,new,count=1):
    global s
    old=old.replace('\n',NL); new=new.replace('\n',NL)
    n=s.count(old)
    if n!=count: raise SystemExit(f'anchor x{n} (want {count}): {old[:90]!r}')
    s=s.replace(old,new)
if 'Stage SHARE-TWEAK' in s: raise SystemExit('already patched')

# 1) PDF icon
i=s.index("const ICON_PDF='<svg"); j=s.index("';",i)+2
s=s[:i]+"const ICON_PDF='<img class=\"pdfic\" alt=\"\" src=\""+icon+"\">'; // Stage SHARE-TWEAK"+s[j:]

# 2) subtitle
rep("document.getElementById('empSub').textContent='สถานะเอกสารแรงงาน'+",
    "document.getElementById('empSub').textContent='ข้อมูล เอกสารแรงงาน วันหมดอายุ'+")

# 3) thanks
rep("""      <button class="stat s-bad" data-f="bad"><b id="nBad">0</b><span>เลยกำหนด</span></button>
    </div>
  </header>""",
"""      <button class="stat s-bad" data-f="bad"><b id="nBad">0</b><span>เลยกำหนด</span></button>
    </div>
    <div class="thx">ขอบคุณที่ใช้บริการ</div>
  </header>""")

# 4) detail header background = banner ของหน้าแรก + แถบมืด
rep("""  const dt=document.getElementById('dt'); dt.classList.add('open'); document.getElementById('dtbg').classList.add('on'); dt.scrollTop=0; dt.setAttribute('aria-hidden','false');""",
"""  { // Stage SHARE-TWEAK: หัวหน้ารายละเอียดใช้รูปพื้นหลังเดียวกับหน้าแรก (ใช้รูปที่โหลด/จำไว้แล้ว ไม่โหลดใหม่)
    const hb=document.querySelector('.hd .hdbg.on'), dh=document.querySelector('#dtIn .dhd');
    const bi=hb&&hb.style.backgroundImage;
    if(dh&&bi&&bi!=='none'){ dh.classList.add('has-bg'); dh.style.backgroundImage='linear-gradient(180deg,rgba(0,0,0,.38) 0%,rgba(0,0,0,.66) 100%),'+bi; }
  }
  const dt=document.getElementById('dt'); dt.classList.add('open'); document.getElementById('dtbg').classList.add('on'); dt.scrollTop=0; dt.setAttribute('aria-hidden','false');""")

# 5) CSS
rep("</style>","""/* Stage SHARE-TWEAK */
.files .ic img.pdfic{width:32px;height:32px;object-fit:contain}
.thx{text-align:right;font-size:11px;opacity:.9;margin-top:8px;letter-spacing:.02em;text-shadow:0 1px 3px rgba(0,0,0,.45)}
.dhd.has-bg{background-size:cover;background-position:center}
.dhd.has-bg h2,.dhd.has-bg .en,.dhd.has-bg .meta{text-shadow:0 1px 3px rgba(0,0,0,.55)}
.docs{gap:7px;padding:10px 16px}
.dc{min-height:84px;padding:9px 12px;border-radius:12px}
.dc .lb{font-size:12.5px}
.dc .dd{font-size:15px}
.dc .r2{margin:2px 0 6px;min-height:28px}
.dc .pill{font-size:11.5px;padding:1px 8px}
.dc .view{font-size:12px;padding:4px 11px}
.dc .bar{height:4px}
</style>""")
io.open(path,'w',encoding='utf-8',newline='').write(s)
print('patched',path)

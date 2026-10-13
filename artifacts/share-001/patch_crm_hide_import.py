# Stage UI-HIDE-CASES + IMPORT-SHEETS — แพตช์ rungfar_crm_17.html และ .STAGING.local.html ด้วยโค้ดชุดเดียวกัน
#  1) ซ่อนเมนู "งานเอกสารแรงงาน" และ "แม่แบบเอกสาร / ขั้นตอนงาน" (ไม่ลบข้อมูล — เปิดกลับได้: HIDE_CASE_MODULE=false)
#  2) นำเข้า: อ่านหัวตารางที่ไม่ได้อยู่บรรทัดแรกใน CSV, รองรับหัวคอลัมน์ WORK / เวิร์คหมด / เล่มหมดอายุ / ชื่อต่างด้าว,
#     แปลงสัญชาติแบบรหัส (KHM/LAO/MMR/VNM), ไม่บันทึกคำว่า "สถานะ" เป็นสถานะงาน, และวางข้อมูลที่ copy จาก Google Sheets ได้
import sys

MARK = 'Stage UI-HIDE-CASES'

def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:70]}')
    return s.replace(old, new)

PASTE_UI = (
    '<details id="impPasteBox" style="margin-top:12px;border:1px solid var(--g2);border-radius:10px;padding:10px 14px;background:#fff">'
    '<summary style="cursor:pointer;font-weight:700;font-size:13px;color:var(--g7)">📋 วางข้อมูลจาก Google Sheets</summary>'
    '<div style="font-size:12px;color:var(--g5);margin:8px 0">ใน Google Sheets เลือกตารางรวมแถวหัวคอลัมน์ → กด Ctrl+C → วางในช่องนี้ (Ctrl+V) → กด "อ่านข้อมูล"</div>'
    '<textarea id="impPasteText" class="fi2" rows="5" style="width:100%;font-family:var(--mono);font-size:11px" placeholder="วางข้อมูลที่ copy มาที่นี่"></textarea>'
    '<div style="display:flex;justify-content:flex-end;margin-top:8px"><button class="btn btn-p btn-sm" onclick="impFromPaste()">อ่านข้อมูล</button></div>'
    '</details>'
)

JS_HELPERS = r'''// ── Stage IMPORT-SHEETS: สัญชาติแบบรหัส/อังกฤษ → ชื่อไทยที่ CRM ใช้ ──
const _IMP_NAT_MAP={KHM:'กัมพูชา',KH:'กัมพูชา',CAM:'กัมพูชา',CAMBODIA:'กัมพูชา',CAMBODIAN:'กัมพูชา','เขมร':'กัมพูชา','กัมพูชา':'กัมพูชา',
  LAO:'ลาว',LA:'ลาว',LAOS:'ลาว','ลาว':'ลาว',
  MMR:'เมียนมา',MM:'เมียนมา',MYA:'เมียนมา',MYANMAR:'เมียนมา',BURMA:'เมียนมา','พม่า':'เมียนมา','เมียนมา':'เมียนมา','เมียนมาร์':'เมียนมา',
  VNM:'เวียดนาม',VN:'เวียดนาม',VIE:'เวียดนาม',VIETNAM:'เวียดนาม','เวียดนาม':'เวียดนาม'};
function _impNat(v){const c=_impClean(v);if(!c)return null;const k=String(c).trim().toUpperCase().replace(/[\s.]/g,'');return _IMP_NAT_MAP[k]||c;}
// ค่าที่เป็นแค่คำหัวคอลัมน์ (เช่น ช่องสถานะที่พิมพ์ว่า "สถานะ") → ถือว่าว่าง
function _impStatus(v){const s=String(v==null?'':v).trim();return(!s||s==='สถานะ'||s==='-')?'':s;}
// วางจาก Google Sheets (TSV) → ใช้ pipeline เดิมของการนำเข้า
function impFromPaste(){
  const ta=document.getElementById('impPasteText');const text=(ta&&ta.value||'').replace(/\r/g,'');
  if(!text.trim()){toast('ยังไม่ได้วางข้อมูล','err');return;}
  const rows=text.split('\n').map(l=>l.split('\t').map(c=>String(c).trim())).filter(r=>r.some(c=>c));
  if(rows.length<2){toast('ต้องมีหัวคอลัมน์และข้อมูลอย่างน้อย 1 แถว','err');return;}
  impPhotos={};impPhotoScan=false;impPhotoFilter='all';impSaveUnsure=false;
  const _h=impDetectHeaderRow(rows);
  impCols=(rows[_h]||[]).map(c=>String(c).trim());
  impData=rows.slice(_h+1).filter(r=>r.some(c=>c));
  impMap={};const _nz=s=>String(s||'').trim().toLowerCase();const _used=new Set();
  IMP_FIELDS.forEach(f=>{const al=(f.aliases||[f.label]).map(_nz);
    let found=impCols.findIndex((c,i)=>!_used.has(i)&&al.includes(_nz(c)));
    if(found<0)found=impCols.findIndex((c,i)=>!_used.has(i)&&al.some(a=>a.length>=3&&_nz(c).includes(a)));
    if(found>=0){impMap[f.key]=found;_used.add(found);}});
  renderImpPreview();
  const p=document.getElementById('impPreview');if(p)p.scrollIntoView({behavior:'smooth',block:'start'});
}
'''

def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    # 1) ซ่อนเมนูงานเอกสาร/แม่แบบ
    a = '<meta name="apple-mobile-web-app-title" content="Rungfar CRM">'
    s = rep(s, a, a + nl + '<style id="hideCaseModule">/* ' + MARK + ': ซ่อนงานเอกสารแรงงาน + แม่แบบ (ข้อมูลยังอยู่) */'
            '#niCases,#niCaseTpl,.di[data-view="cases"],.di[data-view="casetpl"],#detCaseSec{display:none!important}</style>', path)
    a = 'function gv(v,opts={}){'
    s = rep(s, a, '// ' + MARK + ': true = ซ่อนเมนูงานเอกสารแรงงาน/แม่แบบ (เปลี่ยนเป็น false เพื่อเปิดกลับ)' + nl
            + 'const HIDE_CASE_MODULE=true;' + nl + a + "if(HIDE_CASE_MODULE&&(v==='cases'||v==='casetpl'))v='dash';", path)
    a = 'async function _loadDetCases(cid){'
    s = rep(s, a, a + 'if(HIDE_CASE_MODULE)return;', path)
    # 2) นำเข้า
    s = rep(s, "impCols=(_rows[0]||[]).map(c=>String(c).trim());",
            "const _ch=impDetectHeaderRow(_rows);impCols=(_rows[_ch]||[]).map(c=>String(c).trim());", path)
    s = rep(s, "impData=_rows.slice(1).map(r=>r.map(c=>String(c).trim())).filter(r=>r.some(c=>c));",
            "impData=_rows.slice(_ch+1).map(r=>r.map(c=>String(c).trim())).filter(r=>r.some(c=>c));", path)
    s = rep(s, "aliases:['รายชื่อ','ชื่อ','ชื่อลูกค้า','ชื่อ-นามสกุล','name']",
            "aliases:['รายชื่อ','ชื่อ','ชื่อลูกค้า','ชื่อ-นามสกุล','name','ชื่อต่างด้าว','ชื่อแรงงาน']", path)
    s = rep(s, "aliases:['เลขคำขอ','เลขคำขอ wp','wp_no','work permit']",
            "aliases:['เลขคำขอ','เลขคำขอ wp','wp_no','work permit','work','เลขใบอนุญาตทำงาน','เลข wp']", path)
    a = "{key:'exp_wp',label:'วันหมด WP',aliases:['วันหมด wp','exp_wp']},"
    s = rep(s, a, "{key:'exp_wp',label:'วันหมด WP',aliases:['วันหมด wp','exp_wp','เวิร์คหมด','วันหมดเวิร์ค','wp หมด','วันหมดใบอนุญาตทำงาน']}," + nl
            + "  {key:'exp_passport',label:'วันหมดพาสปอร์ต',aliases:['วันหมดพาสปอร์ต','เล่มหมดอายุ','พาสปอร์ตหมด','วันหมด passport','passport หมด','exp_passport']},", path)
    a = "data.receive_date=_ds('receive_date',get(row,'receive_date'));"
    s = rep(s, a, a + nl + "      data.exp_passport=_ds('exp_passport',get(row,'exp_passport')); // Stage IMPORT-SHEETS", path)
    s = rep(s, "nationality:_impClean(nat)||'เมียนมา'", "nationality:_impNat(nat)||'เมียนมา'", path)
    s = rep(s, "work_status:get(row,'work_status')||'รับเรื่อง'", "work_status:_impStatus(get(row,'work_status'))||'รับเรื่อง'", path)
    a = 'function normImpStr(s){'
    s = rep(s, a, JS_HELPERS.replace('\n', nl) + a, path)
    a = '<div id="impPreview" style="margin-top:16px"></div>'
    s = rep(s, a, PASTE_UI + a, path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

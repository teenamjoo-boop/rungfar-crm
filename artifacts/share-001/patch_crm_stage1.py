# Stage S1-SIMPLE + S1-BULKDOC
#  S1-SIMPLE: โหมดเรียบง่าย — หน้าลูกค้าเหลือ ข้อมูล + วันหมดอายุ + เอกสาร
#    ซ่อน (ไม่ลบข้อมูล): timeline สถานะงาน, การเงิน, ข้อมูลตาม Excel/การยื่น, คำขอ e-WorkPermit, ติดต่อ/ประวัติ,
#    ช่องบริการ/สถานะงาน/วันที่ยื่น/ตัวแทน/เจ้าหน้าที่ 3 ตำแหน่ง/นัดหมาย, คอลัมน์ วันที่ยื่น/รายการ/สถานะ/ชำระเงิน
#    เปิดกลับ: SIMPLE_WORKER_MODE=false
#  S1-BULKDOC: หน้า "นำเข้า" อัปโหลด PDF/รูปทีละหลายไฟล์ จับคู่แรงงานจากเลขพาสปอร์ต/เลขต่างด้าว/เลขใบอนุญาตในชื่อไฟล์
#    ใช้ฟังก์ชันเดิม customer-doc-upload (ไม่มี backend ใหม่)
import sys

MARK = 'Stage S1-SIMPLE'

CSS = ('<style id="simpleWorkerMode">/* ' + MARK + ': โหมดเรียบง่าย (ข้อมูลยังอยู่ครบ แค่ซ่อน) */'
       'html.simple-worker #cModal .tbar3 .tbtn:nth-child(4){display:none!important}'
       'html.simple-worker #ct1 .fsec:has(#svcT),html.simple-worker #ct1 .fsec:has(#f_medical){display:none!important}'
       'html.simple-worker .fgi:has(#f_src),html.simple-worker .fgi:has(#f_ws),html.simple-worker .fgi:has(#f_submit),'
       'html.simple-worker .fgi:has(#f_agent),html.simple-worker #staffSec{display:none!important}'
       'html.simple-worker #ct2 .fsec:has(#f_apptdate){display:none!important}'
       'html.simple-worker #view-customers th:nth-child(2),html.simple-worker #view-customers td:nth-child(2),'
       'html.simple-worker #view-customers th:nth-child(9),html.simple-worker #view-customers td:nth-child(9),'
       'html.simple-worker #view-customers th:nth-child(10),html.simple-worker #view-customers td:nth-child(10),'
       'html.simple-worker #view-customers th:nth-child(14),html.simple-worker #view-customers td:nth-child(14){display:none!important}'
       '</style>')

FLAG = r'''// ── Stage S1-SIMPLE: true = หน้าลูกค้าเหลือ ข้อมูล + วันหมดอายุ + เอกสาร (false = เปิดทุกส่วนกลับมา) ──
const SIMPLE_WORKER_MODE=true;
if(SIMPLE_WORKER_MODE)document.documentElement.classList.add('simple-worker');
'''

BULK_UI = ('<div id="bulkDocBox" style="margin-top:12px;border:1px solid var(--g2);border-radius:var(--rx);padding:14px 16px;background:#fff">'
           '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">'
           '<div><div style="font-weight:700;color:var(--g8)">📚 อัปโหลดหลายไฟล์พร้อมกัน</div>'
           '<div style="font-size:12px;color:var(--g5);margin-top:2px">ตั้งชื่อไฟล์ให้มีเลขพาสปอร์ต / เลขต่างด้าว / เลขใบอนุญาต เช่น T0974538_passport.pdf — ระบบจับคู่แรงงานและเดาประเภทเอกสารให้</div></div>'
           '<label class="btn btn-p btn-sm" style="cursor:pointer">เลือกไฟล์…<input type="file" id="bulkDocInput" multiple accept="image/*,.pdf" style="display:none" onchange="bulkDocPick(event)"></label>'
           '</div><div id="bulkDocList" style="margin-top:10px"></div></div>')

BULK_JS = r'''// ── Stage S1-BULKDOC: อัปโหลด PDF/รูปทีละหลายไฟล์ + จับคู่แรงงานจากชื่อไฟล์ ──
let _bulkDocs=[];
const _BULK_TYPES=[['passport_photo','พาสปอร์ต'],['visa','VISA'],['wp','Work Permit'],['photo','รูปถ่าย'],['pow','หนังสือมอบอำนาจ'],['other','อื่นๆ']];
function _bulkNorm(s){return String(s||'').toUpperCase().replace(/[^A-Z0-9]/g,'');}
function _bulkGuessType(n){const s=String(n||'').toLowerCase();
  if(/passport|พาสปอร์ต|หนังสือเดินทาง|(^|[^a-z])pp([^a-z]|$)/.test(s))return'passport_photo';
  if(/visa|วีซ่า/.test(s))return'visa';
  if(/work|permit|ใบอนุญาต|เวิร์ค|(^|[^a-z])wp([^a-z]|$)/.test(s))return'wp';
  if(/มอบอำนาจ|(^|[^a-z])pow([^a-z]|$)/.test(s))return'pow';
  if(/photo|รูป/.test(s))return'photo';
  return'other';}
function _bulkMatch(fileName){
  const f=_bulkNorm(String(fileName||'').replace(/\.[^.]+$/,''));let best=null,bestLen=0,tie=false;
  (typeof customers!=='undefined'?customers:[]).forEach(c=>{[c.passport_no,c.alien_id,c.license_no,c.wp_no].forEach(k=>{const n=_bulkNorm(k);
    if(n.length>=6&&f.includes(n)){if(n.length>bestLen){best=c;bestLen=n.length;tie=false;}else if(n.length===bestLen&&best&&best.id!==c.id)tie=true;}});});
  return tie?null:best;}
function bulkDocPick(e){
  const files=[...(e.target.files||[])];e.target.value='';
  const ok=files.filter(f=>f.type==='application/pdf'||(f.type||'').startsWith('image/'));
  if(ok.length<files.length)toast('ข้ามไฟล์ที่ไม่ใช่ PDF/รูป '+(files.length-ok.length)+' ไฟล์','err');
  ok.slice(0,40).forEach(file=>{const c=_bulkMatch(file.name);_bulkDocs.push({file,cust:c?c.id:null,type:_bulkGuessType(file.name),status:''});});
  if(ok.length>40)toast('เลือกได้ครั้งละ 40 ไฟล์','err');
  _bulkRender();}
function _bulkRender(){
  const box=document.getElementById('bulkDocList');if(!box)return;
  if(!_bulkDocs.length){box.innerHTML='';return;}
  const list=(typeof customers!=='undefined'?customers:[]).slice().sort((a,b)=>String(a.name||'').localeCompare(String(b.name||'')));
  const opts=list.map(c=>'<option value="'+c.id+'">'+esc(c.name||'—')+(c.passport_no?' · '+esc(c.passport_no):'')+'</option>').join('');
  const matched=_bulkDocs.filter(d=>d.cust).length,done=_bulkDocs.filter(d=>d.status==='ok').length;
  box.innerHTML='<div style="font-size:12px;color:var(--g6);margin-bottom:6px">จับคู่แรงงานได้ '+matched+'/'+_bulkDocs.length+' ไฟล์'+(done?' · อัปโหลดแล้ว '+done:'')+' — ไฟล์ที่ยังไม่จับคู่ เลือกแรงงานเองได้</div>'
   +'<div style="overflow-x:auto"><table style="width:100%;font-size:12px;border-collapse:collapse">'
   +_bulkDocs.map((d,i)=>{const kb=Math.round(d.file.size/1024);
     const st=d.status==='ok'?'<span style="color:#15803d;font-weight:700">✓ สำเร็จ</span>':d.status==='busy'?'<span style="color:var(--g5)">กำลังอัปโหลด…</span>':d.status?'<span style="color:#b91c1c">'+esc(d.status)+'</span>':'';
     const dis=d.status==='ok'||d.status==='busy'?' disabled':'';
     return '<tr style="border-top:1px solid var(--g1)"><td style="padding:6px 4px;max-width:220px;word-break:break-all">'+(d.file.type==='application/pdf'?'📄 ':'🖼️ ')+esc(d.file.name)+' <span style="color:var(--g4)">'+kb+' KB</span></td>'
      +'<td style="padding:6px 4px"><select class="fi2" style="min-width:180px;'+(d.cust?'':'border-color:#f59e0b')+'" onchange="_bulkDocs['+i+'].cust=this.value?Number(this.value):null;_bulkRender()"'+dis+'><option value="">— เลือกแรงงาน —</option>'+opts.replace('value="'+d.cust+'"','value="'+d.cust+'" selected')+'</select></td>'
      +'<td style="padding:6px 4px"><select class="fi2" onchange="_bulkDocs['+i+'].type=this.value"'+dis+'>'+_BULK_TYPES.map(t=>'<option value="'+t[0]+'"'+(t[0]===d.type?' selected':'')+'>'+t[1]+'</option>').join('')+'</select></td>'
      +'<td style="padding:6px 4px;white-space:nowrap">'+st+(d.status!=='ok'&&d.status!=='busy'?' <button class="btn btn-g btn-xs" onclick="_bulkDocs.splice('+i+',1);_bulkRender()">ลบ</button>':'')+'</td></tr>';}).join('')
   +'</table></div><div style="display:flex;justify-content:flex-end;gap:8px;margin-top:10px">'
   +'<button class="btn btn-g btn-sm" onclick="_bulkDocs=[];_bulkRender()">ล้างรายการ</button>'
   +'<button class="btn btn-p btn-sm" id="bulkDocGo" onclick="bulkDocUpload()">อัปโหลด '+_bulkDocs.filter(d=>d.cust&&d.status!=='ok').length+' ไฟล์</button></div>';}
async function _bulkPrepare(file){
  const isPdf=file.type==='application/pdf';
  if(isPdf){if(file.size>10*1024*1024)throw new Error('PDF ใหญ่เกิน 10MB');return{data:await readAsDataURL(file),type:'application/pdf'};}
  let data=await compressImage(file,1600,0.72);
  if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(file,1200,0.6);
  if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)throw new Error('รูปใหญ่เกิน 1.5MB หลังย่อ');
  return{data,type:'image/jpeg'};}
async function bulkDocUpload(){
  if(!(await guardSession()))return;
  const todo=_bulkDocs.filter(d=>d.cust&&d.status!=='ok');
  if(!todo.length){toast('ยังไม่มีไฟล์ที่เลือกแรงงานแล้ว','err');return;}
  let ok=0,fail=0;
  for(const d of todo){
    d.status='busy';_bulkRender();
    try{const p=await _bulkPrepare(d.file);const c=(customers||[]).find(x=>x.id===d.cust);
      const r=await _callDocUpload({customer_id:d.cust,doc_type:d.type,doc_name:docTypeLabel(d.type),file_name:d.file.name,file_type:p.type,data_url:p.data});
      if(!r||!r.ok)throw new Error(r&&r.error||'upload_failed');
      d.status='ok';ok++;void c;
    }catch(e){d.status='ไม่สำเร็จ: '+(e&&e.message||e);fail++;}
    _bulkRender();
  }
  try{logAudit('document.upload.bulk','document',null,{count:ok,failed:fail});}catch(_){}
  toast(fail?('อัปโหลดสำเร็จ '+ok+' · ไม่สำเร็จ '+fail):('อัปโหลดสำเร็จ '+ok+' ไฟล์'),fail?'err':undefined);
}
'''

def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:70]}')
    return s.replace(old, new)

def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<style id="hideCaseModule">', CSS + nl + '<style id="hideCaseModule">', path)
    a = 'const SIMPLE_CUSTOMER_DETAIL=true;'
    i = s.index(a); j = s.index('\n', i) + 1     # หลังจบบรรทัดนั้น
    s = s[:j] + FLAG.replace('\n', nl) + s[j:]
    for v in ['_updBtn', '_tlSec', '_finSec', '_xlSec', '_wpr2Section(c)', '_clogSec', '_histSec']:
        s = rep(s, '  ${' + v + '}', "  ${SIMPLE_WORKER_MODE?'':" + v + "}", path)
    a = 'function swTab(n){'
    s = rep(s, a, a + "if(SIMPLE_WORKER_MODE){const _b=document.querySelectorAll('#cModal .tbar3 .tbtn');if(_b[1])_b[1].textContent='เลขเอกสาร';}", path)
    a = 'PDF · JPEG · PNG · เลือกลูกค้าแล้วบันทึก</div>' + nl + '      </div>'
    s = rep(s, a, a + nl + '      ' + BULK_UI, path)
    a = 'const IMP_FIELDS=['
    s = rep(s, a, BULK_JS.replace('\n', nl) + a, path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

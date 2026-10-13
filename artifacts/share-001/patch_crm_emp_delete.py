# Stage EMP-DELETE (CRM): ปุ่ม "ลบนายจ้าง" ในหน้านายจ้าง (แอดมินเท่านั้น)
#   - ยังมีแรงงาน → ไม่ลบ บอกจำนวนให้ย้าย/ลบแรงงานก่อน
#   - ยืนยันก่อนลบ · ส่งชื่อนายจ้างไปตรวจฝั่ง server (กันลบผิดตัว)
#   - server ตรวจซ้ำ: เคส / สถานประกอบการ / เอกสารนายจ้าง → บอกว่าติดอะไร
#   ต้องรัน SQL 20261013_employer_delete.sql ก่อน (ไม่รัน = แจ้งว่ายังไม่ได้รัน SQL ไม่พัง)
import sys

MARK = 'Stage EMP-DELETE'

JS = r'''// ── Stage EMP-DELETE: ลบนายจ้าง (แอดมินเท่านั้น — server ตรวจซ้ำ) ──
async function empDelete(id){
  if(!_isAdminRole()){toast('เฉพาะผู้ดูแลระบบเท่านั้น','err');return;}
  const e=(employers||[]).find(x=>x.id===id);if(!e)return;
  const n=(customers||[]).filter(c=>c.employer_id===id).length;
  if(n){alert(`ลบไม่ได้ — นายจ้าง "${e.name}" ยังมีแรงงาน ${n} คน\n\nย้ายแรงงานไปนายจ้างอื่น หรือลบแรงงานก่อน แล้วค่อยลบนายจ้าง`);return;}
  if(!confirm(`ลบนายจ้าง "${e.name}" ถาวร?\n\nลิงก์/QR ของนายจ้างนี้จะใช้ไม่ได้อีก และกู้คืนไม่ได้`))return;
  if(!(await guardSession()))return;
  const r=await _shareRpc('app_delete_employer',{p_employer_id:id,p_confirm_name:e.name});
  if(r.status==='missing'){toast('ต้องรัน SQL 20261013_employer_delete บนฐานข้อมูลนี้ก่อน','err');return;}
  if(r.status==='unauthorized'){toast('ไม่มีสิทธิ์ลบ — เฉพาะผู้ดูแลระบบ','err');return;}
  const d=r.status==='ok'?r.data:null;
  if(!d){toast('ลบไม่สำเร็จ — กรุณาลองใหม่','err');return;}
  if(d.ok){
    const m=document.getElementById('empDetModal');if(m)m.style.display='none';
    employers=employers.filter(x=>x.id!==id);
    try{renderEmployers();}catch(_){}
    toast(`ลบนายจ้าง "${e.name}" แล้ว`);
    try{await loadAll(true);}catch(_){}
    return;
  }
  if(d.error==='has_dependents'){
    const parts=[];
    if(d.customers)parts.push(`แรงงาน ${d.customers} คน`);
    if(d.cases)parts.push(`เคส ${d.cases} เคส`);
    if(d.establishments)parts.push(`สถานประกอบการ ${d.establishments} แห่ง`);
    if(d.documents)parts.push(`เอกสารนายจ้าง ${d.documents} ไฟล์`);
    alert(`ลบไม่ได้ — นายจ้าง "${e.name}" ยังมี ${parts.join(', ')}\n\nจัดการรายการเหล่านี้ก่อน แล้วค่อยลบนายจ้าง`);
    return;
  }
  toast(d.error==='not_found'?'ไม่พบนายจ้างนี้แล้ว (อาจถูกลบไปแล้ว)':d.error==='name_mismatch'?'ชื่อนายจ้างไม่ตรง — โหลดหน้าใหม่แล้วลองอีกครั้ง':'ลบไม่สำเร็จ','err');
}
'''


def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:80]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<button class="btn btn-g btn-sm" id="empDetEditBtn" onclick="openEditEmp(${id})">${T(\'btnEdit\')}</button>',
            '<button class="btn btn-sm" id="empDetDelBtn" style="display:none;color:#b91c1c;background:#fff5f5;border:1px solid #fecaca">ลบนายจ้าง</button>'
            '<button class="btn btn-g btn-sm" id="empDetEditBtn" onclick="openEditEmp(${id})">${T(\'btnEdit\')}</button>', path)
    old = "  const edb=document.getElementById('empDetEditBtn');if(edb){edb.textContent=T('btnEdit');edb.onclick=()=>{document.getElementById('empDetModal').style.display='none';openEditEmp(id);};}"
    s = rep(s, old, old + nl + "  {const ddb=document.getElementById('empDetDelBtn');if(ddb){ddb.style.display=_isAdminRole()?'':'none';ddb.onclick=()=>empDelete(id);}} // " + MARK, path)
    s = rep(s, 'function openEmpDet(id){', JS.replace('\n', nl) + 'function openEmpDet(id){', path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

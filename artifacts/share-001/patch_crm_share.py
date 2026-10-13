# Stage SHARE-001 — เพิ่มส่วน "ลิงก์ให้นายจ้างดูข้อมูลแรงงาน" ในหน้าต่างรายละเอียดนายจ้าง
# ใช้แพตช์ rungfar_crm_17.html และ rungfar_crm_17.STAGING.local.html ด้วยโค้ดชุดเดียวกัน
# (โค้ดที่เพิ่มไม่มี project ref — ใช้ SB_URL/SB_KEY ที่มีอยู่แล้วในแต่ละไฟล์)
import sys, io

MARK = 'Stage SHARE-001'

JS_BLOCK = r'''// ── Stage SHARE-001: ลิงก์ให้นายจ้างดูข้อมูลแรงงาน (ส่งทาง LINE · read-only) ──────────
//   RPC: app_get/create/revoke_employer_share_link (ตรวจตัวตนฝั่ง server)
//   หน้าเว็บลูกค้า: share.html?t=<token> → Edge Function employer-share-view
//   ตั้ง SHARE_PAGE_URL เป็นที่อยู่จริงเมื่อขึ้นเว็บ (เช่น 'https://rungfar.netlify.app/share.html')
//   ว่างไว้ = ใช้ไฟล์ข้าง ๆ CRM (STAGING ใช้ share.STAGING.local.html อัตโนมัติ)
const SHARE_PAGE_URL='';
function _shareBaseUrl(){
  if(SHARE_PAGE_URL)return SHARE_PAGE_URL;
  const f=/STAGING\.local/i.test(location.pathname)?'share.STAGING.local.html':'share.html';
  try{return new URL(f,location.href).href.split('?')[0].split('#')[0];}catch(_){return f;}
}
function _shareLinkUrl(token){return _shareBaseUrl()+'?t='+encodeURIComponent(token);}
async function _shareRpc(fname,extra){
  const uid=(curUser&&curUser.id!=null)?String(curUser.id):'';
  const uname=(curUser&&curUser.username)||'';
  let res;
  try{
    res=await fetch(`${SB_URL}/rest/v1/rpc/${fname}`,{
      method:'POST',mode:'cors',
      headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json','Accept':'application/json'},
      body:JSON.stringify(Object.assign({p_user_id:uid,p_username:uname},extra||{}))
    });
  }catch(e){return{status:'error'};}
  let d=null;try{d=await res.json();}catch(_){d=null;}
  if(res.ok)return{status:'ok',data:d};
  const code=(d&&d.code)||'';const msg=(d&&d.message)||'';
  if(res.status===404||code==='PGRST202'||/Could not find the function/i.test(msg))return{status:'missing'};
  if(msg==='unauthorized')return{status:'unauthorized'};
  return{status:'error',msg};
}
async function _copyText(t){
  try{if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(t);return true;}}catch(_){}
  try{const ta=document.createElement('textarea');ta.value=t;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();const ok=document.execCommand('copy');ta.remove();return ok;}catch(_){return false;}
}
let _empShareCur={id:null,link:null};
function _renderEmpShare(){
  const box=document.getElementById('empShareSec');if(!box)return;
  const e=employers.find(x=>x.id===_empShareCur.id);
  const L=_empShareCur.link;
  const head=`<div style="display:flex;align-items:flex-start;justify-content:space-between;gap:10px;flex-wrap:wrap">
    <div><div style="font-weight:700;font-size:13px;color:var(--g9)">🔗 ลิงก์ให้นายจ้างดูข้อมูลแรงงาน</div>
    <div style="font-size:11px;color:var(--g5)">ส่งทาง LINE · นายจ้างเห็นวันหมดอายุ รูปแรงงาน และรูปเอกสาร (ดูได้อย่างเดียว)</div></div>`;
  let body;
  if(L==='loading'){body=head+`<span style="font-size:12px;color:var(--g5)">กำลังโหลด…</span></div>`;}
  else if(L==='missing'){body=head+`</div><div style="font-size:11px;color:var(--g5);margin-top:6px">ยังไม่ได้รัน SQL 20261009_employer_share_links บนฐานข้อมูลนี้</div>`;}
  else if(L==='error'){body=head+`<button class="btn btn-g btn-sm" onclick="_loadEmpShare(${_empShareCur.id})">ลองใหม่</button></div><div style="font-size:11px;color:var(--r,#b91c1c);margin-top:6px">โหลดลิงก์ไม่สำเร็จ</div>`;}
  else if(!L){body=head+`<button class="btn btn-p btn-sm" onclick="_empShareCreate(false)">สร้างลิงก์</button></div>`;}
  else{
    const url=_shareLinkUrl(L.token);
    const seen=L.view_count?`เปิดดูแล้ว ${L.view_count} ครั้ง${L.last_viewed_at?' · ล่าสุด '+new Date(L.last_viewed_at).toLocaleString('th-TH',{dateStyle:'medium',timeStyle:'short'}):''}`:'ยังไม่มีคนเปิดดู';
    body=head+`<div style="display:flex;gap:6px;flex-wrap:wrap">
        <button class="btn btn-p btn-sm" onclick="_empShareCopy(true)">คัดลอกข้อความส่ง LINE</button>
        <button class="btn btn-g btn-sm" onclick="_empShareCopy(false)">คัดลอกลิงก์</button>
        <button class="btn btn-g btn-sm" onclick="window.open(_shareLinkUrl(_empShareCur.link.token),'_blank','noopener')">เปิดดู</button>
      </div></div>
      <div style="margin-top:8px;font-size:11px;font-family:var(--mono);color:var(--g6);background:var(--g1);border-radius:8px;padding:6px 8px;word-break:break-all">${esc(url)}</div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:6px;flex-wrap:wrap">
        <span style="font-size:11px;color:var(--g5)">สร้างโดย ${esc(L.created_by_code||'—')} · ${L.created_at?new Date(L.created_at).toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'2-digit'}):''} · ${seen}</span>
        <span style="display:flex;gap:6px">
          <button class="btn btn-g btn-xs" onclick="_empShareCreate(true)">สร้างลิงก์ใหม่</button>
          <button class="btn btn-g btn-xs" style="color:#b91c1c" onclick="_empShareRevoke()">ยกเลิกลิงก์</button>
        </span>
      </div>`;
  }
  box.innerHTML=`<div style="border:1px solid var(--g2);border-radius:12px;padding:12px 14px;margin-bottom:14px">${body}</div>`;
  void e;
}
async function _loadEmpShare(id){
  _empShareCur={id,link:'loading'};_renderEmpShare();
  const r=await _shareRpc('app_get_employer_share_link',{p_employer_id:id});
  if(_empShareCur.id!==id)return;
  if(r.status==='missing'){_empShareCur.link='missing';}
  else if(r.status!=='ok'){_empShareCur.link='error';}
  else{const row=Array.isArray(r.data)?r.data[0]:null;_empShareCur.link=row||null;}
  _renderEmpShare();
}
async function _empShareCreate(rotate){
  const id=_empShareCur.id;if(id==null)return;
  if(rotate&&!confirm('สร้างลิงก์ใหม่?\nลิงก์เดิมที่ส่งให้นายจ้างไปแล้วจะเปิดไม่ได้ ต้องส่งลิงก์ใหม่ให้อีกครั้ง'))return;
  const r=await _shareRpc('app_create_employer_share_link',{p_employer_id:id,p_rotate:!!rotate});
  if(r.status==='ok'){const row=Array.isArray(r.data)?r.data[0]:null;_empShareCur.link=row||null;_renderEmpShare();toast(rotate?'สร้างลิงก์ใหม่แล้ว':'สร้างลิงก์แล้ว');}
  else if(r.status==='missing'){_empShareCur.link='missing';_renderEmpShare();}
  else toast(r.status==='unauthorized'?'ไม่มีสิทธิ์ — กรุณาเข้าสู่ระบบใหม่':'สร้างลิงก์ไม่สำเร็จ','err');
}
async function _empShareRevoke(){
  const id=_empShareCur.id;if(id==null)return;
  if(!confirm('ยกเลิกลิงก์นี้?\nนายจ้างจะเปิดลิงก์เดิมไม่ได้อีก'))return;
  const r=await _shareRpc('app_revoke_employer_share_link',{p_employer_id:id});
  if(r.status==='ok'){_empShareCur.link=null;_renderEmpShare();toast('ยกเลิกลิงก์แล้ว');}
  else toast('ยกเลิกลิงก์ไม่สำเร็จ','err');
}
async function _empShareCopy(withMsg){
  const L=_empShareCur.link;if(!L||!L.token)return;
  const e=employers.find(x=>x.id===_empShareCur.id)||{};
  const url=_shareLinkUrl(L.token);
  const txt=withMsg?`สวัสดีครับ/ค่ะ บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด\nข้อมูลเอกสารแรงงานของ ${e.name||'ท่าน'} (วันหมดอายุพาสปอร์ต วีซ่า ใบอนุญาตทำงาน รายงานตัว 90 วัน)\nกดดูได้ที่ลิงก์นี้ 👇\n${url}`:url;
  toast(await _copyText(txt)?'คัดลอกแล้ว — วางใน LINE ได้เลย':'คัดลอกไม่สำเร็จ',undefined);
}

'''

def patch(path):
    raw = open(path, 'rb').read()
    s = raw.decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    a1 = "<div style=\"font-size:12px;font-weight:700;color:var(--g7);margin-bottom:10px\">${T('empDetWorkerList')}</div>"
    a2 = "try{if(typeof _loadEmpPhase2==='function')_loadEmpPhase2(id);}catch(_e){}"
    a3 = "// Stage 54A-5: helper เติม/อ่าน field Phase 2 ของ modal นายจ้าง (ef2_*)"
    for a in (a1, a2, a3):
        n = s.count(a)
        if n != 1:
            sys.exit(f'{path}: anchor count {n} != 1 for: {a[:60]}')
    s = s.replace(a1, '<div id="empShareSec"></div>' + a1)
    s = s.replace(a2, a2 + nl + "  try{_loadEmpShare(id);}catch(_e){} // " + MARK)
    s = s.replace(a3, JS_BLOCK.replace('\n', nl) + a3)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

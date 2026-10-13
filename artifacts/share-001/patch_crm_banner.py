# Stage EMP-BANNER: ตั้งรูปพื้นหลังหน้าลิงก์แยกต่อนายจ้าง (หน้านายจ้าง → ใต้ส่วนลิงก์)
#   เก็บเป็นเอกสารนายจ้าง doc_type='share_banner' (อัปโหลดผ่าน customer-doc-upload เดิม)
#   "ใช้พื้นหลังส้มเดิม" = เปลี่ยน doc_type เป็น share_banner_off (ไม่ลบไฟล์)
#   รูปพื้นหลังไม่แสดงในรายการเอกสารนายจ้าง
import sys

MARK = 'Stage EMP-BANNER'

CSS = ('<style id="empBanner">/* ' + MARK + ' */'
       '.eh-ban{display:flex;gap:12px;align-items:center;flex-wrap:wrap;border:1px solid var(--g2);border-radius:10px;padding:10px;margin-top:10px;background:#fff}'
       '.eh-ban-prev{width:160px;height:68px;border-radius:8px;overflow:hidden;background:linear-gradient(160deg,#f27a1a,#d9560a);display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;flex:none}'
       '.eh-ban-prev img{width:100%;height:100%;object-fit:cover}'
       '</style>')

JS = r'''// ── Stage EMP-BANNER: รูปพื้นหลังหน้าลิงก์ต่อนายจ้าง ──
let _ehBanner=null;
async function _renderEmpBanner(){
  const box=document.getElementById('empBannerSec');if(!box)return;
  const b=_ehBanner;
  box.innerHTML=`<div class="eh-ban"><div class="eh-ban-prev" id="ehBanPrev">${b?'กำลังโหลดรูป…':'พื้นหลังส้มมาตรฐาน'}</div>
    <div style="flex:1;min-width:180px"><div style="font-weight:700;font-size:13px;color:var(--g9)">🖼️ พื้นหลังหน้าลิงก์ของนายจ้างนี้</div>
    <div style="font-size:11px;color:var(--g5)">ใช้รูปแนวนอน เช่น รูปสวน/โรงงาน/โลโก้ของนายจ้าง — แสดงแทนแถบสีส้มด้านบนของหน้าลิงก์</div>
    <div style="display:flex;gap:6px;margin-top:6px;flex-wrap:wrap"><label class="btn btn-p btn-sm" style="cursor:pointer">${b?'เปลี่ยนรูป':'ใส่รูปพื้นหลัง'}<input type="file" accept="image/*" style="display:none" onchange="ehBannerPick(this)"></label>${b?'<button class="btn btn-g btn-sm" onclick="ehBannerRemove()">ใช้พื้นหลังส้มเดิม</button>':''}</div></div></div>`;
  if(b&&b.has_storage){
    try{const res=await fetch(CUST_DOC_SIGN_URL,{method:'POST',mode:'cors',headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json'},
        body:JSON.stringify({document_id:Number(b.id),user_id:curUser&&curUser.id!=null?String(curUser.id):'',username:curUser&&curUser.username||''})});
      const d=await res.json();const p=document.getElementById('ehBanPrev');
      if(p&&d&&d.ok&&d.url&&_ehBanner===b)p.innerHTML=`<img src="${esc(d.url)}" alt="">`;}catch(_){}
  }
}
async function ehBannerPick(inp){
  const f=inp.files&&inp.files[0];inp.value='';if(!f||_ehEmpId==null)return;
  if(!/^image\//.test(f.type||'')){toast('กรุณาเลือกไฟล์รูป','err');return;}
  if(!(await guardSession()))return;
  showLoading('กำลังอัปโหลดพื้นหลัง...');let r=null;
  try{let data=await compressImage(f,1600,0.8);if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(f,1200,0.7);
    r=await _callEmpDocUpload({employer_id:_ehEmpId,doc_type:'share_banner',doc_name:'พื้นหลังหน้าลิงก์',file_name:f.name,file_type:'image/jpeg',data_url:data,doc_expiry:null});}
  catch(e){r={ok:false,error:(e&&e.message)||'error'};}
  finally{hideLoading();}
  if(r&&r.ok){toast('ตั้งพื้นหลังแล้ว — เปิดหน้าลิงก์ใหม่เพื่อดู');try{logAudit('employer.share_banner.set','employer',_ehEmpId,{source:'empHub'});}catch(_){}}
  else toast('อัปโหลดไม่สำเร็จ: '+_ehErrMsg(r&&r.error),'err');
  await _loadEmpDocHub(_ehEmpId);
}
async function ehBannerRemove(){
  const b=_ehBanner;if(!b||_ehEmpId==null)return;
  if(!confirm('กลับไปใช้พื้นหลังสีส้มเดิม?'))return;
  try{await _delReqRpc('app_update_document_metadata',{p_document_id:String(b.id),p_doc_name:b.doc_name||'พื้นหลังหน้าลิงก์',p_doc_type:'share_banner_off',p_source:b.source||null,p_doc_expiry:null,p_doc_status:null,p_doc_note:null});
    toast('กลับไปใช้พื้นหลังส้มแล้ว');try{logAudit('employer.share_banner.clear','employer',_ehEmpId,{doc_id:b.id});}catch(_){}}
  catch(e){toast('ไม่สำเร็จ: '+((e&&e.message)||''),'err');}
  await _loadEmpDocHub(_ehEmpId);
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
    if 'Stage EMP-HUB' not in s:
        sys.exit(f'{path}: ต้องมี Stage EMP-HUB ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<style id="hideCaseModule">', CSS + nl + '<style id="hideCaseModule">', path)
    i = s.index('function _empHubHtml(e,empc){')
    a = '<div id="empShareSec"></div>'
    k = s.index(a, i)
    s = s[:k] + a + '<div id="empBannerSec"></div>' + s[k + len(a):]
    s = rep(s, '  _ehDocs=Array.isArray(docs)?docs:[];' + nl + '  _renderEmpDocHub();',
            "  {const _all=Array.isArray(docs)?docs:[];_ehBanner=_all.find(d=>d.doc_type==='share_banner')||null;_ehDocs=_all.filter(d=>!/^share_banner/.test(String(d.doc_type||'')));} // Stage EMP-BANNER" + nl +
            '  _renderEmpDocHub();_renderEmpBanner();', path)
    s = rep(s, 'async function _loadEmpDocHub(empId){', JS.replace('\n', nl) + 'async function _loadEmpDocHub(empId){', path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

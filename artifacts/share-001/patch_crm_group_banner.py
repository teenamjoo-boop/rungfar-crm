# Stage SHARE-GROUP-BANNER (CRM): รูปพื้นหลังหน้าลิงก์รวมของกลุ่ม
#   หน้าต่าง "🔗 ลิงก์รวมของกลุ่ม" → ส่วน "พื้นหลังหน้าลิงก์ของกลุ่มนี้" (ใส่รูป / เปลี่ยนรูป / ใช้พื้นหลังเดิม)
#   เก็บเป็นเอกสาร owner_type='group' doc_type='share_banner' ผ่าน customer-doc-upload (cdu5 ขึ้นไป)
#   "ใช้พื้นหลังเดิม" = เปลี่ยน doc_type เป็น share_banner_off (ไม่ลบไฟล์)
#   ต้องรัน SQL 20261013_group_share_banner.sql ก่อน (ไม่รัน = แจ้งว่ายังไม่ได้รัน SQL ไม่พัง)
import sys

MARK = 'Stage SHARE-GROUP-BANNER'

JS = r'''// ── Stage SHARE-GROUP-BANNER: รูปพื้นหลังหน้าลิงก์ของกลุ่ม ──
let _grpBan={gid:null,doc:undefined};   // undefined = กำลังโหลด · null = ไม่มี · 'missing' = ยังไม่รัน SQL · 'error'
async function _loadGrpBanner(gid){
  _grpBan={gid,doc:undefined};_renderGrpBanner();
  const r=await _shareRpc('app_get_group_banner',{p_group_id:gid});
  if(_grpBan.gid!==gid)return;
  _grpBan.doc=r.status==='missing'?'missing':(r.status==='ok'?((Array.isArray(r.data)?r.data[0]:null)||null):'error');
  _renderGrpBanner();
}
async function _renderGrpBanner(){
  const box=document.getElementById('grpBannerSec');if(!box)return;
  const gid=_grpBan.gid,b=_grpBan.doc;
  const head='<div style="font-weight:700;font-size:13px;color:var(--g9);margin-top:14px">🖼️ พื้นหลังหน้าลิงก์ของกลุ่มนี้</div>';
  if(b===undefined){box.innerHTML=head+'<div class="sh-na">กำลังโหลด…</div>';return;}
  if(b==='missing'){box.innerHTML=head+'<div style="font-size:12px;color:#b91c1c">ต้องรัน SQL 20261013_group_share_banner บนฐานข้อมูลนี้ก่อน</div>';return;}
  if(b==='error'){box.innerHTML=head+`<div style="font-size:12px;color:#b91c1c">โหลดไม่สำเร็จ</div><button class="btn btn-g btn-sm" style="margin-top:6px" onclick="_loadGrpBanner(${Number(gid)})">ลองใหม่</button>`;return;}
  box.innerHTML=head+`<div class="eh-ban"><div class="eh-ban-prev" id="grpBanPrev">${b?'กำลังโหลดรูป…':'ยังไม่ได้ใส่รูป'}</div>
    <div style="flex:1;min-width:180px"><div style="font-size:11px;color:var(--g5)">ใช้รูปแนวนอน เช่น รูปสวน/ไร่ของกลุ่ม — แสดงแทนแถบสีส้มด้านบนของหน้าลิงก์รวม${b?'':'<br>ตอนนี้ใช้รูปพื้นหลังของนายจ้างในกลุ่ม (ถ้ามี) หรือสีส้มมาตรฐาน'}</div>
    <div style="display:flex;gap:6px;margin-top:6px;flex-wrap:wrap"><label class="btn btn-p btn-sm" style="cursor:pointer">${b?'เปลี่ยนรูป':'ใส่รูปพื้นหลัง'}<input type="file" accept="image/*" style="display:none" onchange="grpBannerPick(this)"></label>${b?'<button class="btn btn-g btn-sm" onclick="grpBannerRemove()">ไม่ใช้รูปนี้</button>':''}</div></div></div>`;
  if(b&&b.has_storage){
    try{const res=await fetch(CUST_DOC_SIGN_URL,{method:'POST',mode:'cors',headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json'},
        body:JSON.stringify({document_id:Number(b.id),user_id:curUser&&curUser.id!=null?String(curUser.id):'',username:curUser&&curUser.username||''})});
      const d=await res.json();const p=document.getElementById('grpBanPrev');
      if(p&&d&&d.ok&&d.url&&_grpBan.doc===b)p.innerHTML=`<img src="${esc(d.url)}" alt="">`;}catch(_){}
  }
}
function _grpBanErr(code){return({owner_type_not_supported:'ต้องอัปเดตฟังก์ชัน customer-doc-upload บน Supabase ก่อน',invalid_owner_type:'ต้องอัปเดตฟังก์ชัน customer-doc-upload บน Supabase ก่อน',db_error:'บันทึกไม่ได้ — ต้องรัน SQL 20261013 ก่อน',group_not_found:'ไม่พบกลุ่มนี้'})[code]||_ehErrMsg(code);}
async function grpBannerPick(inp){
  const f=inp.files&&inp.files[0];inp.value='';const gid=_grpBan.gid;if(!f||gid==null)return;
  if(!/^image\//.test(f.type||'')){toast('กรุณาเลือกไฟล์รูป','err');return;}
  if(!(await guardSession()))return;
  showLoading('กำลังอัปโหลดพื้นหลัง...');let r=null;
  try{let data=await compressImage(f,1600,0.8);if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(f,1200,0.7);
    const res=await fetch(CUST_DOC_UPLOAD_URL,{method:'POST',mode:'cors',headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json'},
      body:JSON.stringify({user_id:curUser&&curUser.id!=null?String(curUser.id):'',username:curUser&&curUser.username||'',owner_type:'group',owner_id:gid,doc_type:'share_banner',doc_name:'พื้นหลังหน้าลิงก์กลุ่ม',file_name:f.name,file_type:'image/jpeg',file_size:approxBytesFromDataURL(data),data_url:data,doc_expiry:null})});
    r=await res.json();}
  catch(e){r={ok:false,error:(e&&e.message)||'error'};}
  finally{hideLoading();}
  if(r&&r.ok){toast('ตั้งพื้นหลังของกลุ่มแล้ว — เปิดหน้าลิงก์ใหม่เพื่อดู');try{logAudit('group.share_banner.set','group',gid,{source:'grpShare'});}catch(_){}}
  else toast('อัปโหลดไม่สำเร็จ: '+_grpBanErr(r&&r.error),'err');
  await _loadGrpBanner(gid);
}
async function grpBannerRemove(){
  const b=_grpBan.doc,gid=_grpBan.gid;if(!b||typeof b!=='object'||gid==null)return;
  if(!confirm('ไม่ใช้รูปพื้นหลังนี้กับลิงก์ของกลุ่ม?\n(หน้าลิงก์จะใช้รูปของนายจ้างในกลุ่ม หรือสีส้มเดิม — ไฟล์รูปไม่ถูกลบ)'))return;
  try{await _delReqRpc('app_update_document_metadata',{p_document_id:String(b.id),p_doc_name:b.doc_name||'พื้นหลังหน้าลิงก์กลุ่ม',p_doc_type:'share_banner_off',p_source:b.source||null,p_doc_expiry:null,p_doc_status:null,p_doc_note:null});
    toast('เลิกใช้รูปพื้นหลังของกลุ่มแล้ว');try{logAudit('group.share_banner.clear','group',gid,{doc_id:b.id});}catch(_){}}
  catch(e){toast('ไม่สำเร็จ: '+((e&&e.message)||''),'err');}
  await _loadGrpBanner(gid);
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
    if 'Stage SHARE-GROUP' not in s or 'Stage EMP-BANNER' not in s:
        sys.exit(path + ': ต้องมี SHARE-GROUP และ EMP-BANNER ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<div class="mbody" id="grpShareBody"></div></div>`;',
            '<div class="mbody"><div id="grpShareBody"></div><div id="grpBannerSec"></div></div></div>`;', path)
    s = rep(s, '  _loadGrpShare(gid);' + nl + '}' + nl + 'async function _loadGrpShare(gid){',
            '  _loadGrpShare(gid);_loadGrpBanner(gid); // ' + MARK + nl + '}' + nl + 'async function _loadGrpShare(gid){', path)
    s = rep(s, 'function _empGroupHint(empc){', JS.replace('\n', nl) + 'function _empGroupHint(empc){', path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

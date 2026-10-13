# Stage SHARE-GROUP (CRM): ลิงก์รวม + QR ของ "กลุ่มงาน" (เช่น สวนยาง ที่มีหลายนายจ้าง)
#   - หน้า "จัดการกลุ่ม": ปุ่ม 🔗 ลิงก์/QR ต่อกลุ่ม → หน้าต่างสร้าง/คัดลอก/เปิด/QR/สร้างใหม่/ยกเลิก
#   - หน้านายจ้าง: ถ้าแรงงานของนายจ้างอยู่ในกลุ่ม มีแถบบอก + ปุ่มเปิดลิงก์รวมของกลุ่ม
#   - QR: แยกฟังก์ชันวาด (_shareQrDraw) ให้ใช้ได้ทั้งลิงก์นายจ้างและลิงก์กลุ่ม
#   ต้องรัน SQL 20261012_group_share_links.sql ก่อน (ไม่รัน = แจ้งว่ายังไม่ได้รัน SQL ไม่พัง)
import sys

MARK = 'Stage SHARE-GROUP'

CSS = ('<style id="grpShare">/* ' + MARK + ' */'
       '.eh-grp{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:10px;background:#eef6ff;border:1px solid #cfe3fb;border-radius:10px;padding:8px 12px;font-size:12px;color:#1e3a5f}'
       '.gs-emps{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 12px}'
       '.gs-emp{background:var(--g0);border:1px solid var(--g2);border-radius:20px;padding:3px 10px;font-size:12px}'
       '</style>')

JS = r'''// ── Stage SHARE-GROUP: ลิงก์รวมของกลุ่มงาน ──
let _grpShareCur={id:null,link:null};
function _grpOfId(id){return(groups||[]).find(g=>g.id===id)||{};}
function _grpEmpSummary(gid){
  const m=new Map();(customers||[]).filter(c=>c.group_id===gid).forEach(c=>{const k=c.employer_id||0;m.set(k,(m.get(k)||0)+1);});
  return[...m.entries()].map(([k,n])=>({id:k,name:k?empN(k):'ไม่มีนายจ้าง',n}));
}
function openGrpShare(gid){
  let m=document.getElementById('grpShareModal');
  if(!m){m=document.createElement('div');m.id='grpShareModal';m.className='mo';m.onclick=function(ev){if(ev.target===this)this.style.display='none';};document.body.appendChild(m);}
  m.innerHTML=`<div class="mb" style="max-width:560px" onclick="event.stopPropagation()"><div class="mh"><div class="mt">🔗 ลิงก์รวมของกลุ่ม: ${esc(_grpOfId(gid).name||'')}</div><button class="xbtn" onclick="document.getElementById('grpShareModal').style.display='none'">×</button></div><div class="mbody" id="grpShareBody"></div></div>`;
  m.style.display='flex';
  _loadGrpShare(gid);
}
async function _loadGrpShare(gid){
  _grpShareCur={id:gid,link:'loading'};_renderGrpShare();
  const r=await _shareRpc('app_get_group_share_link',{p_group_id:gid});
  if(_grpShareCur.id!==gid)return;
  if(r.status==='missing')_grpShareCur.link='missing';
  else if(r.status!=='ok')_grpShareCur.link='error';
  else{const row=Array.isArray(r.data)?r.data[0]:null;_grpShareCur.link=row||null;}
  _renderGrpShare();
}
function _renderGrpShare(){
  const box=document.getElementById('grpShareBody');if(!box)return;
  const gid=_grpShareCur.id,L=_grpShareCur.link,emps=_grpEmpSummary(gid);
  const total=emps.reduce((a,x)=>a+x.n,0);
  let html=`<div style="font-size:12px;color:var(--g6)">ลิงก์นี้แสดงแรงงานทุกคนที่อยู่ในกลุ่มนี้ (${total} คน) รวมทุกนายจ้างไว้หน้าเดียว — นายจ้างกดกรองดูเฉพาะของตัวเองได้</div>
    <div class="gs-emps">${emps.length?emps.map(x=>`<span class="gs-emp">🏢 ${esc(x.name)} · ${x.n} คน</span>`).join(''):'<span class="sh-na">ยังไม่มีแรงงานในกลุ่มนี้</span>'}</div>`;
  if(L==='loading')html+='<div class="sh-na">กำลังโหลด…</div>';
  else if(L==='missing')html+='<div style="font-size:12px;color:#b91c1c">ยังไม่ได้รัน SQL 20261012_group_share_links บนฐานข้อมูลนี้</div>';
  else if(L==='error')html+=`<div style="font-size:12px;color:#b91c1c">โหลดลิงก์ไม่สำเร็จ</div><button class="btn btn-g btn-sm" style="margin-top:6px" onclick="_loadGrpShare(${gid})">ลองใหม่</button>`;
  else if(!L)html+=`<button class="btn btn-p btn-sm" onclick="_grpShareCreate(false)">สร้างลิงก์รวมของกลุ่ม</button>`;
  else{
    const url=_shareLinkUrl(L.token);
    const seen=L.view_count?`เปิดดูแล้ว ${L.view_count} ครั้ง${L.last_viewed_at?' · ล่าสุด '+new Date(L.last_viewed_at).toLocaleString('th-TH',{dateStyle:'medium',timeStyle:'short'}):''}`:'ยังไม่มีคนเปิดดู';
    html+=`<div style="display:flex;gap:6px;flex-wrap:wrap">
        <button class="btn btn-p btn-sm" onclick="_grpShareCopy(true)">คัดลอกข้อความส่ง LINE</button>
        <button class="btn btn-g btn-sm" onclick="_grpShareCopy(false)">คัดลอกลิงก์</button>
        <button class="btn btn-g btn-sm" onclick="window.open(_shareLinkUrl(_grpShareCur.link.token),'_blank','noopener')">เปิดดู</button>
        <button class="btn btn-g btn-sm" onclick="_grpShareQr()">QR โค้ด</button></div>
      <div style="margin-top:8px;font-size:11px;font-family:var(--mono);color:var(--g6);background:var(--g1);border-radius:8px;padding:6px 8px;word-break:break-all">${esc(url)}</div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:6px;flex-wrap:wrap">
        <span style="font-size:11px;color:var(--g5)">สร้างโดย ${esc(L.created_by_code||'—')} · ${L.created_at?new Date(L.created_at).toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'2-digit'}):''} · ${seen}</span>
        <span style="display:flex;gap:6px"><button class="btn btn-g btn-xs" onclick="_grpShareCreate(true)">สร้างลิงก์ใหม่</button><button class="btn btn-g btn-xs" style="color:#b91c1c" onclick="_grpShareRevoke()">ยกเลิกลิงก์</button></span></div>`;
  }
  box.innerHTML=html;
}
async function _grpShareCreate(rotate){
  const gid=_grpShareCur.id;if(gid==null)return;
  if(rotate&&!confirm('สร้างลิงก์ใหม่?\nลิงก์/QR เดิมของกลุ่มที่ส่งไปแล้วจะเปิดไม่ได้ ต้องส่งอันใหม่ให้อีกครั้ง'))return;
  const r=await _shareRpc('app_create_group_share_link',{p_group_id:gid,p_rotate:!!rotate});
  if(r.status==='ok'){const row=Array.isArray(r.data)?r.data[0]:null;_grpShareCur.link=row||null;_renderGrpShare();toast(rotate?'สร้างลิงก์ใหม่แล้ว':'สร้างลิงก์แล้ว');}
  else if(r.status==='missing'){_grpShareCur.link='missing';_renderGrpShare();}
  else toast(r.status==='unauthorized'?'ไม่มีสิทธิ์ — กรุณาเข้าสู่ระบบใหม่':'สร้างลิงก์ไม่สำเร็จ','err');
}
async function _grpShareRevoke(){
  const gid=_grpShareCur.id;if(gid==null)return;
  if(!confirm('ยกเลิกลิงก์รวมของกลุ่มนี้?\nคนที่มีลิงก์/QR เดิมจะเปิดไม่ได้อีก'))return;
  const r=await _shareRpc('app_revoke_group_share_link',{p_group_id:gid});
  if(r.status==='ok'){_grpShareCur.link=null;_renderGrpShare();toast('ยกเลิกลิงก์แล้ว');}
  else toast('ยกเลิกลิงก์ไม่สำเร็จ','err');
}
async function _grpShareCopy(withMsg){
  const L=_grpShareCur.link;if(!L||!L.token)return;
  const g=_grpOfId(_grpShareCur.id);const url=_shareLinkUrl(L.token);
  const txt=withMsg?`สวัสดีครับ/ค่ะ บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด\nข้อมูลเอกสารแรงงานกลุ่ม ${g.name||''} (วันหมดอายุพาสปอร์ต วีซ่า ใบอนุญาตทำงาน รายงานตัว 90 วัน)\nกดดูได้ที่ลิงก์นี้ 👇\n${url}`:url;
  toast(await _copyText(txt)?'คัดลอกแล้ว — วางใน LINE ได้เลย':'คัดลอกไม่สำเร็จ',undefined);
}
function _grpShareQr(){
  const L=_grpShareCur.link;if(!L||!L.token)return;
  _shareQrDraw(_shareLinkUrl(L.token),String(_grpOfId(_grpShareCur.id).name||''),'สแกนดูสถานะเอกสารแรงงานของกลุ่ม');
}
function _empGroupHint(empc){
  const ids=[...new Set((empc||[]).map(c=>c.group_id).filter(v=>v!=null))];
  if(!ids.length)return'';
  return`<div class="eh-grp">👥 แรงงานของนายจ้างนี้อยู่ในกลุ่ม ${ids.map(id=>`<b>${esc(_grpOfId(id).name||('#'+id))}</b> <button class="btn btn-g btn-xs" onclick="openGrpShare(${id})">ลิงก์รวมของกลุ่ม / QR</button>`).join(' ')}</div>`;
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
    if 'Stage SHARE-SHORT-QR' not in s or 'Stage EMP-BANNER' not in s:
        sys.exit(path + ': ต้องมี SHARE-SHORT-QR และ EMP-BANNER ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<style id="hideCaseModule">', CSS + nl + '<style id="hideCaseModule">', path)
    # QR: แยกฟังก์ชันวาดให้ใช้ร่วมกัน
    old = nl.join(["function _empShareQr(){",
                   "  const L=_empShareCur.link;if(!L||!L.token)return;",
                   "  if(typeof qrcode!=='function'){toast('สร้าง QR ไม่ได้','err');return;}",
                   "  const e=employers.find(x=>x.id===_empShareCur.id)||{};",
                   "  const url=_shareLinkUrl(L.token);"])
    new = nl.join(["function _empShareQr(){const L=_empShareCur.link;if(!L||!L.token)return;const e=employers.find(x=>x.id===_empShareCur.id)||{};_shareQrDraw(_shareLinkUrl(L.token),String(e.name||''),'สแกนดูสถานะเอกสารแรงงาน');} // " + MARK,
                   "let _qrLastUrl='';",
                   "async function _shareQrCopy(){const ok=await _copyText(_qrLastUrl);toast(ok?'คัดลอกลิงก์แล้ว':'คัดลอกไม่สำเร็จ',ok?undefined:'err');}",
                   "function _shareQrDraw(url,nmIn,subIn){",
                   "  _qrLastUrl=url;",
                   "  if(typeof qrcode!=='function'){toast('สร้าง QR ไม่ได้','err');return;}"])
    s = rep(s, old, new, path)
    s = rep(s, "const nm=String(e.name||'');let fs=44;", "const nm=String(nmIn||'');let fs=44;", path)
    s = rep(s, "x.fillText('สแกนดูสถานะเอกสารแรงงาน',S/2,S+80);", "x.fillText(subIn||'สแกนดูสถานะเอกสารแรงงาน',S/2,S+80);", path)
    s = rep(s, 'ดาวน์โหลดรูป QR</a><button class="btn btn-g btn-sm" onclick="_empShareCopy(false)">',
            'ดาวน์โหลดรูป QR</a><button class="btn btn-g btn-sm" onclick="_shareQrCopy()">', path)
    s = rep(s, "<div class=\"mt\">QR โค้ดลิงก์นายจ้าง</div>", "<div class=\"mt\">QR โค้ดลิงก์ — ${esc(nm)}</div>", path)
    # ฟังก์ชันกลุ่ม
    s = rep(s, 'function renderGroups(){', JS.replace('\n', nl) + 'function renderGroups(){', path)
    s = rep(s, '<button class="bic" onclick="openEditGrp(${g.id})" style="font-size:12px">✏️</button>',
            '<button class="btn btn-g btn-sm" style="font-size:11px;padding:4px 10px" onclick="openGrpShare(${g.id})">🔗 ลิงก์/QR</button>'
            '<button class="bic" onclick="openEditGrp(${g.id})" style="font-size:12px">✏️</button>', path)
    # หน้านายจ้าง: แถบบอกกลุ่ม
    s = rep(s, '<div id="empShareSec"></div><div id="empBannerSec"></div>',
            '<div id="empShareSec"></div>${_empGroupHint(empc)}<div id="empBannerSec"></div>', path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

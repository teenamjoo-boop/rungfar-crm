# Stage LINE-DOC-ALERT — CRM: การ์ด "แจ้งเตือนเข้า LINE กลุ่มนายจ้าง" ในหน้า ตั้งค่า (admin) + modal ดูตัวอย่าง
# ใช้ได้กับทั้ง rungfar_crm_17.html และ rungfar_crm_17.STAGING.local.html (ไม่แตะบรรทัดตั้งค่าโปรเจกต์)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT' in t: print('already'); sys.exit(0)
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
# 1) วางกล่องต่อท้ายหน้า ตั้งค่า แล้วโหลดข้อมูล
rep("+'</div>'+notifyHtml+readiness;\n}",
    "+'</div>'+notifyHtml+(curUser&&curUser.role==='admin'?'<div id=\"lineAlertBox\" style=\"margin-top:22px\"></div>':'')+readiness;\n  if(curUser&&curUser.role==='admin')loadLineAlert(); // Stage LINE-DOC-ALERT\n}")
# 2) modal ดูตัวอย่างข้อความ
rep('<div class="mo" id="payProofModal"', '''<!-- MODAL: ดูตัวอย่างข้อความแจ้งเตือน LINE (Stage LINE-DOC-ALERT) -->
<div class="mo" id="lineAlertPvModal" style="display:none" onclick="if(event.target===this)this.style.display='none'">
<div class="mb mb-sm" onclick="event.stopPropagation()" style="max-width:520px">
  <div class="mh"><div class="mt" id="lineAlertPvTitle">ตัวอย่างข้อความ</div><button class="xbtn" onclick="document.getElementById('lineAlertPvModal').style.display='none'">×</button></div>
  <div class="mbody"><div id="lineAlertPvBody" style="white-space:pre-wrap;font-size:13px;line-height:1.6;background:#f6f7f9;border:1px solid var(--g2);border-radius:var(--rl);padding:12px 14px;max-height:60vh;overflow-y:auto"></div></div>
  <div class="mfoo"><button class="btn btn-g" onclick="document.getElementById('lineAlertPvModal').style.display='none'">ปิด</button></div>
</div></div>

<div class="mo" id="payProofModal"''')
# 3) โค้ด
rep("// ── Stage ALERT-SETTINGS-DB: ค่าแจ้งเตือนล่วงหน้าเก็บในฐานข้อมูล (app_alert_settings) ──",
r"""// ── Stage LINE-DOC-ALERT: แจ้งเตือนเอกสารใกล้หมดอายุ เข้ากลุ่ม LINE ของนายจ้าง (admin) ──
//   กลุ่ม LINE ที่บอทมีตังอยู่ → ผูกกับนายจ้าง/กลุ่ม → เปิดแจ้งเตือน · ส่งทุกวัน 09:00 น. (pg_cron → Edge Function line-doc-alert)
//   เอกสาร 1 ชิ้นเตือนครั้งเดียว · ใช้วันแจ้งเตือนล่วงหน้าด้านบน · ข้อความสร้างที่ฐานข้อมูล (ตัวอย่าง = ข้อความจริง)
let _lineAlert=null;
function _laShareBase(){return (typeof SHARE_SITE_URL==='string'&&SHARE_SITE_URL)?SHARE_SITE_URL.replace(/\/+$/,''):'https://rungfa.com';}
async function loadLineAlert(){
  const box=document.getElementById('lineAlertBox');if(!box)return;
  if(!_lineAlert)box.innerHTML=_laCard('<div style="font-size:12px;color:var(--g5)">กำลังโหลด…</div>');
  const r=await _shareRpc('app_line_alert_groups',{});
  if(r.status==='missing'){box.innerHTML=_laCard('<div style="font-size:12px;color:#92400e">ยังไม่ได้รัน SQL แจ้งเตือน LINE (20261022c_line_doc_alert.sql)</div>');return;}
  if(r.status!=='ok'){box.innerHTML=_laCard('<div style="font-size:12px;color:var(--r)">โหลดรายชื่อกลุ่ม LINE ไม่สำเร็จ</div>');return;}
  _lineAlert=Array.isArray(r.data)?r.data:[];
  renderLineAlert();
}
function _laCard(inner){
  return `<div style="background:#fff;border:1px solid var(--g2);border-radius:var(--rl);padding:16px 18px">
    <div style="font-size:15px;font-weight:800;color:var(--g9);margin-bottom:3px">แจ้งเตือนเอกสารเข้า LINE กลุ่มนายจ้าง</div>
    <div style="font-size:12px;color:var(--g5);margin-bottom:12px;line-height:1.6">บอทมีตังส่งให้ทุกวัน 09:00 น. เฉพาะกลุ่มที่เปิดไว้ และมีเอกสารเข้าช่วงแจ้งเตือนด้านบน · เอกสาร 1 ชิ้นเตือนครั้งเดียว (ต่ออายุแล้วจะเตือนรอบใหม่) · ไม่มีรายการ = ไม่ส่ง · กลุ่มจะขึ้นที่นี่เมื่อเชิญบอทมีตังเข้ากลุ่ม</div>${inner}</div>`;
}
function renderLineAlert(){
  const box=document.getElementById('lineAlertBox');if(!box)return;
  const L=_lineAlert||[];
  const emps=(employers||[]).slice().sort((a,b)=>String(a.name||'').localeCompare(String(b.name||''),'th'));
  const grps=(groups||[]).slice().sort((a,b)=>String(a.name||'').localeCompare(String(b.name||''),'th'));
  const fdt=s=>{if(!s)return'';const d=new Date(s);return isNaN(d)?'':d.toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'2-digit'});};
  const rows=L.map((g,i)=>{
    const cur=g.employer_id?('e:'+g.employer_id):g.group_id?('g:'+g.group_id):'';
    const opts=`<option value="">— ยังไม่ผูก —</option>`+
      (emps.length?`<optgroup label="นายจ้าง">${emps.map(e=>`<option value="e:${e.id}"${cur==='e:'+e.id?' selected':''}>${esc(e.name||'-')}</option>`).join('')}</optgroup>`:'')+
      (grps.length?`<optgroup label="กลุ่ม (หลายนายจ้าง)">${grps.map(x=>`<option value="g:${x.id}"${cur==='g:'+x.id?' selected':''}>${esc(x.name||'-')}</option>`).join('')}</optgroup>`:'');
    const bound=!!cur;
    const st=!bound?'<span style="color:var(--g5)">ยังไม่ผูกกับนายจ้าง</span>'
      :`<span style="color:${g.enabled?'#15803d':'var(--g5)'};font-weight:700">${g.enabled?'● เปิดแจ้งเตือน':'○ ปิดอยู่'}</span> · รอเตือน <b>${Number(g.pending)||0}</b> รายการ${g.last_sent?' · ส่งล่าสุด '+fdt(g.last_sent):''}`;
    return `<div style="border:1.5px solid var(--g2);border-radius:var(--rl);padding:12px 14px;margin-bottom:9px">
      <div style="display:flex;justify-content:space-between;gap:10px;align-items:baseline;flex-wrap:wrap"><div style="font-size:13.5px;font-weight:700">💬 ${esc(g.name||'-')}</div><div style="font-size:11.5px;color:var(--g5)">${g.joined_at?'บอทเข้ากลุ่ม '+fdt(g.joined_at):''}</div></div>
      <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px">
        <select id="laSel${i}" onchange="laSave(${i})" style="flex:1;min-width:180px;border:1.5px solid var(--g2);border-radius:var(--r);padding:7px 9px;font-size:13px;background:#fff;color:var(--g9)">${opts}</select>
        <label style="display:flex;align-items:center;gap:6px;font-size:13px;font-weight:600;cursor:${bound?'pointer':'not-allowed'};opacity:${bound?1:.5}"><input type="checkbox" id="laOn${i}" ${g.enabled?'checked':''} ${bound?'':'disabled'} onchange="laSave(${i})"> เปิดแจ้งเตือน</label>
      </div>
      <div style="font-size:12px;margin-top:8px">${st}</div>
      ${bound?`<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:9px">
        <button class="btn btn-g btn-sm" onclick="laPreview(${i})">👀 ดูตัวอย่างข้อความ</button>
        ${g.enabled&&Number(g.pending)?`<button class="btn btn-p btn-sm" onclick="laSendNow(${i})">📤 ส่งตอนนี้</button>`:''}
        ${Number(g.pending)?`<button class="btn btn-g btn-sm" onclick="laSkip(${i})">ข้ามรายการที่ค้างอยู่</button>`:''}
      </div>`:''}
    </div>`;}).join('');
  box.innerHTML=_laCard(rows||'<div style="font-size:12.5px;color:var(--g5);padding:10px 0">ยังไม่มีกลุ่ม LINE — เชิญบอทมีตังเข้ากลุ่มนายจ้างก่อน แล้วกดรีเฟรชหน้านี้</div>');
}
async function laSave(i){
  const g=(_lineAlert||[])[i];if(!g)return;
  const v=(document.getElementById('laSel'+i)||{}).value||'';
  const on=!!(document.getElementById('laOn'+i)||{}).checked&&!!v;
  const r=await _shareRpc('app_line_alert_save',{p_line_group_id:g.line_group_id,p_employer_id:v.startsWith('e:')?Number(v.slice(2)):null,p_group_id:v.startsWith('g:')?Number(v.slice(2)):null,p_enabled:on});
  const d=r.status==='ok'?r.data:null;
  if(!d||!d.ok){toast('บันทึกไม่สำเร็จ'+(d&&d.error?' ('+d.error+')':''),'err');}
  else toast(!v?'เลิกผูกกลุ่มแล้ว':on?'เปิดแจ้งเตือนแล้ว — ส่งรอบถัดไป 09:00 น.':'บันทึกแล้ว (ยังปิดแจ้งเตือนอยู่)');
  await loadLineAlert();
}
async function laPreview(i){
  const g=(_lineAlert||[])[i];if(!g)return;
  const r=await _shareRpc('app_line_alert_preview',{p_line_group_id:g.line_group_id,p_share_base:_laShareBase()});
  if(r.status!=='ok'||!r.data){toast('โหลดตัวอย่างไม่สำเร็จ','err');return;}
  const parts=Array.isArray(r.data.parts)?r.data.parts:[];
  document.getElementById('lineAlertPvTitle').textContent='ตัวอย่างข้อความ · '+(g.name||'');
  document.getElementById('lineAlertPvBody').textContent=parts.length?parts.join('\n\n— ข้อความถัดไป —\n\n'):'ตอนนี้ไม่มีเอกสารที่ต้องเตือน (หรือเตือนไปแล้วทั้งหมด) — วันนี้จะไม่ส่งข้อความเข้ากลุ่มนี้';
  document.getElementById('lineAlertPvModal').style.display='flex';
}
async function laSendNow(i){
  const g=(_lineAlert||[])[i];if(!g)return;
  if(!confirm('ส่งแจ้งเตือน '+(Number(g.pending)||0)+' รายการ เข้ากลุ่ม "'+(g.name||'')+'" ตอนนี้?'))return;
  const r=await _shareRpc('app_line_alert_send_now',{p_line_group_id:g.line_group_id});
  const d=r.status==='ok'?r.data:null;
  if(!d||!d.ok){toast('ส่งไม่สำเร็จ'+(d&&d.error?' ('+d.error+')':''),'err');return;}
  toast('กำลังส่งเข้ากลุ่ม LINE…');setTimeout(loadLineAlert,4000);
}
async function laSkip(i){
  const g=(_lineAlert||[])[i];if(!g)return;
  if(!confirm('ข้าม '+(Number(g.pending)||0)+' รายการที่ค้างอยู่ของกลุ่ม "'+(g.name||'')+'"?\nรายการเหล่านี้จะไม่ถูกส่งเข้ากลุ่ม (เอกสารที่เข้าช่วงเตือนหลังจากนี้ยังเตือนตามปกติ)'))return;
  const r=await _shareRpc('app_line_alert_skip',{p_line_group_id:g.line_group_id});
  const d=r.status==='ok'?r.data:null;
  if(!d||!d.ok){toast('ไม่สำเร็จ','err');return;}
  toast('ข้ามแล้ว '+(d.skipped||0)+' รายการ');await loadLineAlert();
}
// ── Stage ALERT-SETTINGS-DB: ค่าแจ้งเตือนล่วงหน้าเก็บในฐานข้อมูล (app_alert_settings) ──""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

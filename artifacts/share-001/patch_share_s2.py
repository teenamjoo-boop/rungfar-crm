# Stage SHARE-S2: หน้าลิงก์นายจ้าง
#  - การ์ดวันเอกสารขนาดเท่ากันทุกใบ (หัวข้อ+ป้ายวัน / วันที่+ปุ่มดูเอกสาร / แถบเวลา)
#  - ข้อมูลส่วนตัวครบขึ้น (ชื่อไทย/อังกฤษ ประเภท วันเกิด เลขต่างด้าว ใบอนุญาตเลขที่ เลขคำขอ)
#  - ส่วน "เอกสารทั้งหมด" ของแรงงาน (ต้องใช้ employer-share-view เวอร์ชัน S2 ที่ส่ง files มา)
import sys

MARK = 'Stage SHARE-S2'

CSS = '''/* Stage SHARE-S2: การ์ดเท่ากัน + รายการเอกสารทั้งหมด */
.docs{display:grid;gap:9px}
.dc{margin-bottom:0;display:flex;flex-direction:column;min-height:104px}
.dc .r1{display:flex;justify-content:space-between;align-items:center;gap:8px}
.dc .r2{display:flex;justify-content:space-between;align-items:center;gap:8px;margin:4px 0 8px;min-height:34px}
.dc .r1 .pill{margin-top:0}
.dc .bar{margin-top:auto}
.dc.na .bar i{width:0!important}
.nofile{font-size:12px;color:var(--mute)}
.files{background:var(--card);border:1px solid var(--line);border-radius:14px;margin:0 16px 4px;overflow:hidden}
.files .fr{display:flex;align-items:center;gap:10px;width:100%;text-align:left;padding:10px 14px;border-top:1px solid var(--line);background:none}
.files .fr:first-child{border-top:0}
.files .fr:hover{background:#faf6f0}
.files .ic{font-size:20px;flex:none}
.files .fm{flex:1;min-width:0}
.files .fm b{display:block;font-size:14px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.files .fm small{display:block;font-size:12px;color:var(--mute)}
.files .go{font-size:13px;font-weight:600;color:var(--brand-d);background:var(--brand-soft);padding:5px 11px;border-radius:99px;flex:none}
.files .none{padding:14px;color:var(--mute);font-size:13px;text-align:center}
@media (min-width:900px){.docs{grid-template-columns:1fr 1fr;grid-auto-rows:1fr}}
'''

JS = r'''// Stage SHARE-S2: ชื่อประเภทเอกสาร (ใช้เมื่อไฟล์ไม่มีชื่อ)
const TYPE_L={passport_photo:'พาสปอร์ต',passport:'พาสปอร์ต',ci:'CI',visa:'วีซ่า',wp:'ใบอนุญาตทำงาน',work_permit:'ใบอนุญาตทำงาน',
  medical:'ใบรับรองแพทย์',insurance:'ประกันสุขภาพ',identity_card:'ใบอัตลักษณ์',tm47:'ใบรับแจ้ง 90 วัน',contract:'สัญญาจ้าง',
  photo:'รูปถ่าย',profile_photo:'รูปถ่าย',pow:'หนังสือมอบอำนาจ',employer_card:'บัตรนายจ้าง',other:'เอกสาร'};
function openW(id){
  const w=DATA.workers.find(x=>Number(x.id)===id); if(!w) return;
  const cards=DOCS.filter(doc=>!(doc.hideEmpty && !w.dates[doc.k])).map(doc=>{
    const s=st(doc,w.dates[doc.k]);
    const pct = s.d===null?0:Math.max(3,Math.min(100, s.d/doc.span*100));
    const docId = doc.doc && w.docs ? w.docs[doc.k] : null;
    return `<div class="dc ${s.c}">
      <div class="r1"><span class="lb">${esc(doc.l)}</span><span class="pill p-${s.c}">${s.t}</span></div>
      <div class="r2"><span class="dd">${w.dates[doc.k]?fdt(w.dates[doc.k]):'—'}</span>${docId?`<button class="view" onclick="openDoc(this,${Number(docId)},'${esc(doc.short)}')">ดูเอกสาร</button>`:(doc.doc?'<span class="nofile">ยังไม่มีไฟล์</span>':'')}</div>
      <div class="bar"><i style="width:${s.c==='bad'?100:pct}%"></i></div>
    </div>`;}).join('');
  const files=Array.isArray(w.files)?w.files:[];
  const fileRows=files.map(f=>{
    const tl=TYPE_L[f.type]||'';
    const nm=f.name||tl||'เอกสาร';
    const sub=[f.name&&tl&&f.name!==tl?tl:'', f.date?'อัปโหลด '+fdt(f.date):'', f.expiry?'หมดอายุ '+fdt(f.expiry):''].filter(Boolean).join(' · ');
    return `<button class="fr" data-id="${Number(f.id)}" data-n="${esc(nm)}" onclick="openFile(this)"><span class="ic">${f.pdf?'📄':'🖼️'}</span><span class="fm"><b>${esc(nm)}</b>${sub?`<small>${esc(sub)}</small>`:''}</span><span class="go">เปิดดู</span></button>`;}).join('');
  const kv=[['ชื่อ (ภาษาไทย)',w.name_th],['ชื่อ (อังกฤษ)',w.name_en],['ประเภท',w.category],['สัญชาติ',w.nationality],
    ['วันเกิด',w.dob?fdt(w.dob):''],['เลขพาสปอร์ต',w.passport_no],['เลขประจำตัวคนต่างด้าว',w.alien_id],
    ['ใบอนุญาตทำงานเลขที่',w.license_no],['เลขคำขอ',w.request_no],['นายจ้าง',DATA.employer.name]]
    .map(([k,v])=>`<div><span>${k}</span><b>${esc(v||'—')}</b></div>`).join('');
  document.getElementById('dtIn').innerHTML=`
    <div class="dhd">
      <button class="back" onclick="history.back()">‹ กลับไปรายชื่อ</button>
      <div class="dperson">
        ${avatar(w, w.photo?`onclick="openPhoto(${Number(w.id)})"`:'')}
        <div><h2>${esc(dispName(w))}</h2>${w.name_th&&w.name_en?`<div class="en">${esc(w.name_en)}</div>`:''}
        <div class="meta">${esc([w.category, w.nationality, DATA.employer.name].filter(Boolean).join(' · '))}</div></div>
      </div>
    </div>
    <div class="sec" style="margin:16px 18px 0">กำหนดวันเอกสาร</div>
    <div class="docs">${cards}</div>
    <div class="sec" style="margin:4px 18px 8px">เอกสารทั้งหมด (${files.length})</div>
    <div class="files">${fileRows||'<div class="none">ยังไม่มีไฟล์เอกสาร</div>'}</div>
    <div class="sec" style="margin:14px 18px 8px">ข้อมูลส่วนตัว</div>
    <div class="kv">${kv}</div>`;
  const dt=document.getElementById('dt'); dt.classList.add('open'); document.getElementById('dtbg').classList.add('on'); dt.scrollTop=0; dt.setAttribute('aria-hidden','false');
  history.pushState({v:'w'},'');
}
function openFile(el){ openDoc(el.querySelector('.go'), Number(el.dataset.id), el.dataset.n||'เอกสาร'); }
'''


def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARK in s:
        print(path, ': already patched — skip'); return
    a = '</style>'
    assert s.count(a) == 1, 'style count'
    s = s.replace(a, CSS + a)
    i = s.index('function openW(id){'); j = s.index('function closeW(){')
    s = s[:i] + JS + s[j:]
    a = ".filter(t=>!q||[t.w.name_th,t.w.name_en,t.w.passport_no].join(' ')"
    assert s.count(a) == 1
    s = s.replace(a, ".filter(t=>!q||[t.w.name_th,t.w.name_en,t.w.passport_no,t.w.license_no,t.w.alien_id].join(' ')")
    open(path, 'w', encoding='utf-8').write(s)
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

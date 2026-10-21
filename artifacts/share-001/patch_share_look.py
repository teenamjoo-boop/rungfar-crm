import sys
P=sys.argv[1]; s=open(P,encoding='utf-8').read()
def rep(a,b,n=1):
    global s
    assert s.count(a)==n,(P,a[:80],s.count(a)); s=s.replace(a,b)
# ---- ฟอนต์ Prompt (ชุดเดียวกับเว็บขนส่ง/CRM) ----
rep("family=IBM+Plex+Sans+Thai:wght@400;500;600;700","family=Prompt:wght@300;400;500;600")
rep("--font:'IBM Plex Sans Thai',system-ui,sans-serif;","--font:'Prompt',system-ui,sans-serif;")
s=s.replace("font-weight:700","font-weight:600")
# ---- ไอคอนสถิติบนหัว ----
SV=lambda d:f'<svg viewBox="0 0 24 24" aria-hidden="true">{d}</svg>'
I_USERS='<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19a5.5 5.5 0 0 1 11 0"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 14.2A4.5 4.5 0 0 1 21 18.5"/>'
I_CLOCK='<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'
I_ALERT='<path d="M12 4 2.8 19.5h18.4Z"/><path d="M12 10v4.2M12 17h.01"/>'
I_SEARCH='<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>'
rep('<button class="stat s-all on" data-f="all"><b id="nAll">','<button class="stat s-all on" data-f="all"><i class="si">'+SV(I_USERS)+'</i><b id="nAll">')
rep('<button class="stat s-warn" data-f="warn"><b id="nWarn">','<button class="stat s-warn" data-f="warn"><i class="si">'+SV(I_CLOCK)+'</i><b id="nWarn">')
rep('<button class="stat s-bad" data-f="bad"><b id="nBad">','<button class="stat s-bad" data-f="bad"><i class="si">'+SV(I_ALERT)+'</i><b id="nBad">')
rep('<label class="search" id="searchBox" hidden>🔍<input','<label class="search" id="searchBox" hidden><span class="sic">'+SV(I_SEARCH)+'</span><input')
# ---- ชุดไอคอน + ตัวช่วย ----
rep("const DOCS = [","""// Stage SHARE-LOOK: ไอคอนเส้น + กรอบสี (แบบเดียวกับเว็บขนส่ง)
const ICO={
  users:'"""+I_USERS+"""',clock:'"""+I_CLOCK+"""',alert:'"""+I_ALERT+"""',
  check:'<circle cx="12" cy="12" r="8.5"/><path d="m8.2 12.3 2.6 2.6 5-5.2"/>',
  list:'<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2"/><circle cx="4.5" cy="12" r="1.2"/><circle cx="4.5" cy="18" r="1.2"/>',
  calendar:'<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  folder:'<path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4.2l2 2.2H19a1.5 1.5 0 0 1 1.5 1.5v8.3A1.5 1.5 0 0 1 19 19.5H5A1.5 1.5 0 0 1 3.5 18Z"/>',
  user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  passport:'<rect x="5" y="3" width="14" height="18" rx="2"/><circle cx="12" cy="10.5" r="3"/><path d="M9 17h6"/>',
  visa:'<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10.5h18M7 14.5h4"/>',
  wp:'<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M5.8 16a2.8 2.8 0 0 1 5.4 0M14 10h4M14 13.5h3"/>',
  d90:'<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4M9 15l2 2 4-4"/>',
  mou:'<path d="M7 3h7l4 4v14H7Z"/><path d="M14 3v4h4M9.5 12h6M9.5 15.5h4"/>',
  flag:'<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',tag:'<path d="M3.5 12.5V5a1.5 1.5 0 0 1 1.5-1.5h7.5L21 12l-8.5 8.5Z"/><circle cx="8" cy="8" r="1.3"/>',
  globe:'<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.6 2.5 14.4 0 17M12 3.5c-2.5 2.6-2.5 14.4 0 17"/>',
  cake:'<path d="M4 20h16v-7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2Z"/><path d="M4 15.5c2 1.2 4 1.2 6 0s4-1.2 6 0 3 1 4 0M12 11V7.5M12 5.5v.01"/>',
  idc:'<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 10h4M7 14h7"/>',hash:'<path d="M9 4 7 20M17 4l-2 16M4 9h16M3 15h16"/>',
  building:'<path d="M4 21V5.5A1.5 1.5 0 0 1 5.5 4h8A1.5 1.5 0 0 1 15 5.5V21M15 10h3.5A1.5 1.5 0 0 1 20 11.5V21M3 21h18M8 8h3M8 12h3M8 16h3"/>'
};
const svg=(n,c)=>`<svg class="ico${c?' '+c:''}" viewBox="0 0 24 24" aria-hidden="true">${ICO[n]||''}</svg>`;
const chipi=(n,c)=>`<i class="chipi c-${c}">${svg(n)}</i>`;
const hh=(n,c,t)=>`<span class="ht">${chipi(n,c)}<span>${t}</span></span>`;
const DOC_IC={passport:['passport','indigo'],visa:['visa','purple'],wp:['wp','teal'],d90:['d90','cyan'],mou:['mou','amber']};
const DOCS = [""")
# ---- รายชื่อ ----
rep("""L.innerHTML=empChips()+`<div class="sec">${head}</div>`+rows.map""","""L.innerHTML=empChips()+`<div class="sec">${hh(filter==='bad'?'alert':filter==='warn'?'clock':'list',filter==='bad'?'rose':filter==='warn'?'amber':'orange',head)}</div>`+rows.map""")
rep("""${x?`<span class="pill p-${x.s.c}">${x.s.c==='ok'?'✓ เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:'<span class="pill p-na">ยังไม่มีวันที่เอกสาร</span>'}""",
    """${x?`<span class="pill p-${x.s.c}">${svg(x.s.c==='ok'?'check':x.s.c==='bad'?'alert':'clock')}${x.s.c==='ok'?'เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:`<span class="pill p-na">${svg('calendar')}ยังไม่มีวันที่เอกสาร</span>`}""")
# ---- รายละเอียด ----
rep("""      <div class="r1"><span class="lb">${esc(doc.l)}</span><span class="pill p-${s.c}">${s.t}</span></div>""",
    """      <div class="r1"><span class="lb">${chipi(...(DOC_IC[doc.k]||['mou','amber']))}<span>${esc(doc.l)}</span></span><span class="pill p-${s.c}">${s.t}</span></div>""")
rep("""<div class="sec" style="margin:16px 18px 0">กำหนดวันเอกสาร</div>""","""<div class="sec" style="margin:16px 18px 0">${hh('calendar','blue','กำหนดวันเอกสาร')}</div>""")
rep("""<div class="sec" style="margin:4px 18px 8px">เอกสารทั้งหมด (${files.length})</div>""","""<div class="sec" style="margin:4px 18px 8px">${hh('folder','amber','เอกสารทั้งหมด ('+files.length+')')}</div>""")
rep("""<div class="sec" style="margin:14px 18px 8px">ข้อมูลส่วนตัว</div>""","""<div class="sec" style="margin:14px 18px 8px">${hh('user','teal','ข้อมูลส่วนตัว')}</div>""")
rep("""  const kv=[...(w.status?[['สถานะงาน',w.status]]:[]),['ชื่อ (ภาษาไทย)',w.name_th],['ชื่อ (อังกฤษ)',w.name_en],['ประเภท',w.category],['สัญชาติ',w.nationality],
    ['วันเกิด',w.dob?fdt(w.dob):''],['เลขพาสปอร์ต',w.passport_no],['เลขประจำตัวคนต่างด้าว',w.alien_id],
    ['ใบอนุญาตทำงานเลขที่',w.license_no],['เลขคำขอ',w.request_no],['นายจ้าง',w.employer||DATA.employer.name]]
    .map(([k,v])=>`<div><span>${k}</span><b>${esc(v||'—')}</b></div>`).join('');""",
"""  const kv=[...(w.status?[['สถานะงาน',w.status,'flag']]:[]),['ชื่อ (ภาษาไทย)',w.name_th,'user'],['ชื่อ (อังกฤษ)',w.name_en,'user'],['ประเภท',w.category,'tag'],['สัญชาติ',w.nationality,'globe'],
    ['วันเกิด',w.dob?fdt(w.dob):'','cake'],['เลขพาสปอร์ต',w.passport_no,'passport'],['เลขประจำตัวคนต่างด้าว',w.alien_id,'idc'],
    ['ใบอนุญาตทำงานเลขที่',w.license_no,'wp'],['เลขคำขอ',w.request_no,'hash'],['นายจ้าง',w.employer||DATA.employer.name,'building']]
    .map(([k,v,ic])=>`<div><span>${svg(ic,'kvi')}${k}</span><b>${esc(v||'—')}</b></div>`).join('');""")
# ---- CSS ----
rep("/* Stage SHARE-TWEAK */","""/* Stage SHARE-LOOK: ไอคอนสี */
.ico{width:16px;height:16px;flex:none;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round;vertical-align:-3px}
.chipi{width:30px;height:30px;border-radius:9px;display:inline-grid;place-items:center;flex:none;background:var(--cbg,#f1ede7);color:var(--cfg,#6b6259)}
.chipi .ico{width:17px;height:17px;vertical-align:0}
.c-orange{--cfg:#e0620b;--cbg:#fff0e3} .c-green{--cfg:#17804a;--cbg:#e2f4e9} .c-blue{--cfg:#1d64b0;--cbg:#e6f0fb}
.c-purple{--cfg:#6a4a9c;--cbg:#efe8f8} .c-teal{--cfg:#0f7a70;--cbg:#dcf3ef} .c-rose{--cfg:#c4314b;--cbg:#fde7eb}
.c-amber{--cfg:#b26b00;--cbg:#fdf1d8} .c-indigo{--cfg:#4b47c9;--cbg:#ebeafd} .c-cyan{--cfg:#0b7895;--cbg:#ddf2f8}
.sec .ht{display:inline-flex;align-items:center;gap:8px;color:var(--ink);font-size:14px;font-weight:600}
.sec .ht .chipi{width:28px;height:28px;border-radius:8px}
.sec .ht .chipi .ico{width:15px;height:15px}
.stat{position:relative}
.stat .si{display:grid;place-items:center;width:28px;height:28px;border-radius:8px;background:rgba(255,255,255,.2);margin-bottom:5px}
.stat .si svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.stat.on .si{background:var(--brand-soft);color:var(--brand)}
.stat.on.s-warn .si{background:var(--warn-soft);color:var(--warn)} .stat.on.s-bad .si{background:var(--bad-soft);color:var(--bad)}
.search .sic{display:grid;place-items:center;color:var(--mute)}
.search .sic svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round}
.pill .ico{width:13px;height:13px;vertical-align:-2px;stroke-width:2.2}
.dc .lb{display:flex;align-items:center;gap:8px;color:var(--ink);font-weight:500;min-width:0}
.dc .lb>span{overflow:hidden;text-overflow:ellipsis}
.dc .lb .chipi{width:28px;height:28px;border-radius:8px}
.dc .lb .chipi .ico{width:16px;height:16px}
.dc .r2{padding-left:36px}
.dc .bar{margin-left:36px}
.kv span{display:inline-flex;align-items:center;gap:7px}
.kv .kvi{width:15px;height:15px;color:#b3a99c;vertical-align:0}
/* Stage SHARE-TWEAK */""")
open(P,'w',encoding='utf-8').write(s); print('ok',P)

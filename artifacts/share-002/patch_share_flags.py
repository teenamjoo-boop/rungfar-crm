# Stage SHARE-FLAGS — หน้าลิงก์นายจ้าง: ธงชาติ + สถานะเอกสารรายคนแบบเห็นทันที
#   * ธงชาติ (SVG — Windows ไม่แสดงอีโมจิธง) มุมรูปแรงงาน · ในหน้ารายละเอียด
#   * ชิปกรองสัญชาติ (ธง + จำนวน) เมื่อมีมากกว่า 1 สัญชาติ
#   * แถบเอกสาร 4 ช่องใต้ชื่อ: พาสปอร์ต / วีซ่า / ใบอนุญาต / 90 วัน (เขียว ปกติ · ส้ม ใกล้ · แดง เลย · เทา ไม่มีข้อมูล)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage SHARE-FLAGS' in t: print('already'); sys.exit(0)
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("</style>","""/* Stage SHARE-FLAGS */
.avw{position:relative;flex:none}
.flg{position:absolute;right:-5px;bottom:-4px;width:20px;height:20px;border-radius:50%;overflow:hidden;border:2px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.25);background:#fff;display:block}
.flg svg{width:100%;height:100%;display:block}
.dperson .flg{width:26px;height:26px;right:-6px;bottom:-5px}
.fi{display:inline-block;width:16px;height:11px;border-radius:2px;overflow:hidden;vertical-align:-1px;margin-right:4px;box-shadow:0 0 0 1px rgba(0,0,0,.08)}
.fi svg{width:100%;height:100%;display:block}
.nchips{display:flex;gap:6px;flex-wrap:wrap;margin:2px 2px 10px}
.nchip{display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:600;padding:5px 12px 5px 6px;border-radius:99px;background:var(--card);border:1px solid var(--line);color:var(--ink)}
.nchip .fi{width:22px;height:22px;border-radius:50%;margin:0;vertical-align:0}
.nchip small{font-weight:500;color:var(--mute);font-size:12px}
.nchip.on{background:var(--ink);border-color:var(--ink);color:#fff}.nchip.on small{color:rgba(255,255,255,.75)}
.nchip.all{padding-left:12px}
#list .nchips{grid-column:1/-1}
.dstrip{display:flex;gap:3px;margin-top:6px;flex-wrap:nowrap;overflow:hidden}
.dstrip span{display:inline-flex;align-items:center;gap:4px;font-size:10.5px;line-height:1;padding:4px 6px;border-radius:6px;white-space:nowrap;background:#f6f3ee;color:var(--mute);font-weight:500}
.dstrip span i{width:6px;height:6px;border-radius:50%;background:#cfc8bd;flex:none}
.dstrip .ok i{background:var(--ok)} .dstrip .warn{background:var(--warn-soft);color:var(--warn)} .dstrip .warn i{background:var(--warn)}
.dstrip .bad{background:var(--bad-soft);color:var(--bad)} .dstrip .bad i{background:var(--bad)}
</style>""")
rep("const COLORS=['#d9730d','#2e7d6b','#7b5ea7','#b5485d','#3b6fb6','#8a6d1f'];","""const COLORS=['#d9730d','#2e7d6b','#7b5ea7','#b5485d','#3b6fb6','#8a6d1f'];
// Stage SHARE-FLAGS: ธงชาติ SVG (viewBox 30x20)
const FLAGS={
  la:'<rect width="30" height="20" fill="#ce1126"/><rect y="5" width="30" height="10" fill="#002868"/><circle cx="15" cy="10" r="4" fill="#fff"/>',
  mm:'<rect width="30" height="6.7" fill="#fecb00"/><rect y="6.7" width="30" height="6.6" fill="#34b233"/><rect y="13.3" width="30" height="6.7" fill="#ea2839"/><polygon fill="#fff" points="15.0,3.4 16.6,8.3 21.8,8.4 17.7,11.5 19.2,16.4 15.0,13.4 10.8,16.4 12.3,11.5 8.2,8.4 13.4,8.3"/>',
  kh:'<rect width="30" height="20" fill="#032ea1"/><rect y="5" width="30" height="10" fill="#e00025"/><path fill="#fff" d="M9 13.6h12v-1H9zM10 12.6h10V11h-.8V9.6h-.7v1.4h-1V8.8h-.7V7.2h-.6V6h-.4v1.2h-.6v1.6h-.7V11h-1V9.6h-.7V11H10z"/>',
  vn:'<rect width="30" height="20" fill="#da251d"/><polygon fill="#ff0" points="15.0,4.3 16.4,8.4 20.7,8.4 17.2,11.0 18.5,15.2 15.0,12.6 11.5,15.2 12.8,11.0 9.3,8.4 13.6,8.4"/>',
  th:'<rect width="30" height="20" fill="#a51931"/><rect y="3.3" width="30" height="13.4" fill="#f4f5f8"/><rect y="6.7" width="30" height="6.6" fill="#2d2a4a"/>'};
const natKey=n=>{n=String(n||'').toLowerCase();return /ลาว|lao/.test(n)?'la':/เมียนมา|พม่า|myan|burm/.test(n)?'mm':/กัมพูชา|เขมร|camb|khmer/.test(n)?'kh':/เวียดนาม|viet/.test(n)?'vn':/ไทย|thai/.test(n)?'th':'';};
const flagSvg=n=>{const k=natKey(n);return k?`<svg viewBox="0 0 30 20" preserveAspectRatio="xMidYMid slice" aria-hidden="true">${FLAGS[k]}</svg>`:'';};
const flagInline=n=>{const s=flagSvg(n);return s?`<i class="fi">${s}</i>`:'';};
let natF='';
function setNatF(n){ natF=n||''; render(); }
function natChips(){
  if(!DATA) return '';
  const m=new Map(); DATA.workers.forEach(w=>{const n=(w.nationality||'').trim(); if(n) m.set(n,(m.get(n)||0)+1);});
  if(m.size<2) return '';
  const arr=[...m.entries()].sort((a,b)=>b[1]-a[1]);
  return '<div class="nchips"><button class="nchip all'+(natF?'':' on')+'" onclick="setNatF(\\'\\')">ทุกสัญชาติ <small>'+DATA.workers.length+'</small></button>'+
    arr.map(([n,c])=>`<button class="nchip${n===natF?' on':''}" data-n="${esc(n)}" onclick="setNatF(this.dataset.n)">${flagInline(n)||''}${esc(n)} <small>${c}</small></button>`).join('')+'</div>';
}
const STRIP=[['passport','พาส'],['visa','วีซ่า'],['wp','ใบอนุญาต'],['d90','90 วัน']];
function docStrip(w){
  return '<div class="dstrip">'+STRIP.map(([k,l])=>{const doc=DOCS.find(d=>d.k===k);const s=st(doc,w.dates&&w.dates[k]);
    return `<span class="${s.c}" title="${esc(doc.short)} · ${esc(s.t)}"><i></i>${l}</span>`;}).join('')+'</div>';
}""")
rep("""  return `<div class="av" style="background:${bg}" ${extra}>${esc(initials(w))}${img}</div>`;""","""  const fl=flagSvg(w.nationality);
  return `<div class="avw"><div class="av" style="background:${bg}" ${extra}>${esc(initials(w))}${img}</div>${fl?`<i class="flg" title="${esc(w.nationality||'')}">${fl}</i>`:''}</div>`;""")
rep("""    .filter(t=>!empF||t.w.employer===empF)""","""    .filter(t=>!empF||t.w.employer===empF)
    .filter(t=>!natF||(t.w.nationality||'').trim()===natF)""")
rep("""  if(!rows.length){ L.innerHTML=empChips()+'""","""  if(!rows.length){ L.innerHTML=empChips()+natChips()+'""")
rep("""  L.innerHTML=empChips()+`<div class="sec">""","""  L.innerHTML=empChips()+natChips()+`<div class="sec">""")
rep("""        ${x?`<span class="pill p-${x.s.c}">${svg(x.s.c==='ok'?'check':x.s.c==='bad'?'alert':'clock')}${x.s.c==='ok'?'เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:`<span class="pill p-na">${svg('calendar')}ยังไม่มีวันที่เอกสาร</span>`}
      </div>""","""        ${x?`<span class="pill p-${x.s.c}">${svg(x.s.c==='ok'?'check':x.s.c==='bad'?'alert':'clock')}${x.s.c==='ok'?'เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:`<span class="pill p-na">${svg('calendar')}ยังไม่มีวันที่เอกสาร</span>`}
        ${x?docStrip(w):''}
      </div>""")
rep("""        <div class="meta">${esc([w.category, w.nationality, w.employer||DATA.employer.name].filter(Boolean).join(' · '))}</div></div>""","""        <div class="meta">${w.nationality?flagInline(w.nationality):''}${esc([w.category, w.nationality, w.employer||DATA.employer.name].filter(Boolean).join(' · '))}</div></div>""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

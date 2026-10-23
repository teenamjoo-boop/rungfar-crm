# Stage DASH-V2 — หน้าหลัก CRM แบบ "วันนี้ต้องทำอะไร"
#   * การ์ดสรุป 4 ใบ: หมดอายุแล้ว / ใกล้หมดอายุ / รายงานตัว 90 วัน / เอกสารค้าง (ช่วงวันอ่านจากหน้าตั้งค่าแจ้งเตือน)
#   * "ต้องทำก่อน": เรียงตามความด่วน · ป้ายวันสี (แดง/ส้ม/เขียว) · ป้าย "แจ้งนายจ้างทาง LINE แล้ว"
#   * "แยกตามนายจ้าง": นายจ้างไหนมีเรื่องต้องทำกี่รายการ · บอกว่าเปิดแจ้งเตือน LINE อยู่ไหม
#   * ตัดการ์ดผู้รับผิดชอบ / บริการยอดนิยม / นายจ้างแรงงานมากสุด / การ์ด 30 วันแบบเดิม
#   แท็บอื่น (ต่ออายุ / 90 วัน / เอกสารค้าง / งานที่ต้องทำ / ขาดงาน / ยังไม่เช็คเอาท์) เหมือนเดิมทุกอย่าง
import sys,re
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage DASH-V2' in t: print('already'); sys.exit(0)
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)

# ---------- CSS ----------
rep(".dc{background:#fff;border:1px solid var(--g2);border-radius:16px;padding:16px 18px;box-shadow:var(--s1);transition:box-shadow .15s}",
""".dc{background:#fff;border:1px solid var(--g2);border-radius:16px;padding:16px 18px;box-shadow:var(--s1);transition:box-shadow .15s}
/* Stage DASH-V2 */
.dx-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-bottom:12px}
.dx-k{background:#fff;border:1px solid var(--g2);border-radius:16px;padding:15px 16px;box-shadow:var(--s1);cursor:pointer;transition:transform .15s,box-shadow .15s;min-width:0;position:relative;overflow:hidden}
.dx-k:hover{transform:translateY(-2px);box-shadow:0 6px 18px rgba(0,0,0,.07)}
.dx-k .kh{display:flex;align-items:center;gap:9px;font-size:13px;color:var(--g7);font-weight:600}
.dx-k b{display:block;font-size:30px;font-weight:700;line-height:1.15;margin-top:8px;letter-spacing:-.01em}
.dx-k small{display:block;font-size:12px;color:var(--g5);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dx-k.zero b{color:var(--g4)!important}
.dx-ic{width:34px;height:34px;border-radius:10px;display:grid;place-items:center;flex:none;border:1.5px solid}
.dx-ic svg{width:19px;height:19px}
.dx-mini{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}
.dx-mini span{background:#fff;border:1px solid var(--g2);border-radius:99px;padding:5px 12px;font-size:12.5px;color:var(--g7);cursor:pointer}
.dx-mini span b{color:var(--g9);font-weight:700;margin-right:3px}
.dx-cols{display:grid;grid-template-columns:minmax(0,1.6fr) minmax(0,1fr);gap:14px;margin-bottom:16px;align-items:start}
.dx-h{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}
.dx-h .t{display:flex;align-items:center;gap:9px;font-size:15px;font-weight:700;color:var(--g9)}
.dx-h a{font-size:12.5px;color:var(--p);cursor:pointer;font-weight:600;white-space:nowrap}
.dx-row{display:flex;align-items:center;gap:11px;padding:10px 4px;border-top:1px solid var(--g1);cursor:pointer;border-radius:10px}
.dx-row:first-of-type{border-top:0}
.dx-row:hover{background:var(--g0)}
.dx-row .adot{width:38px;height:38px;flex:none}
.dx-mid{flex:1;min-width:0}
.dx-nm{font-size:13.5px;font-weight:700;color:var(--g9);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dx-sub{font-size:11.5px;color:var(--g5);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.dx-doc{display:inline-flex;align-items:center;gap:5px;font-size:12px;color:var(--g7);margin-top:3px}
.dx-doc i{width:18px;height:18px;border-radius:6px;display:inline-grid;place-items:center;border:1px solid;flex:none}
.dx-doc i svg{width:12px;height:12px}
.dx-r{text-align:right;flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:4px}
.dx-dt{font-size:12.5px;font-weight:700;color:var(--g9)}
.dx-chip{font-size:11.5px;font-weight:700;padding:2px 9px;border-radius:99px;white-space:nowrap}
.dx-line{display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:600;color:#06A94D;background:#E7F8EE;border-radius:99px;padding:1px 8px;white-space:nowrap}
.dx-line svg{width:11px;height:11px}
.dx-emp{display:flex;align-items:center;gap:8px;padding:9px 4px;border-top:1px solid var(--g1);cursor:pointer;border-radius:10px}
.dx-emp:first-of-type{border-top:0}
.dx-emp:hover{background:var(--g0)}
.dx-emp .n{flex:1;min-width:0;font-size:13px;font-weight:600;color:var(--g9);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dx-pills{display:flex;gap:4px;flex:none}
.dx-pills span{font-size:11px;font-weight:700;border-radius:99px;padding:1px 7px}
.dx-empty{text-align:center;color:var(--g5);font-size:13px;padding:22px 0}
.dx-ok{display:flex;align-items:center;gap:8px;background:#E8F7EE;color:#15803D;border-radius:12px;padding:12px 14px;font-size:13.5px;font-weight:600}
@media(max-width:900px){.dx-cols{grid-template-columns:1fr}}
@media(max-width:768px){.dx-kpis{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.dx-k{padding:13px 12px}.dx-k b{font-size:26px}}""")

# ---------- summary (แท็บ "ทั้งหมด") ----------
i=t.index("  const summaryHTML=`"); j=t.index("\n  let content;")
t=t[:i]+r"""  // Stage DASH-V2: หน้าหลักแบบ "วันนี้ต้องทำอะไร"
  const summaryHTML=dashV2HTML({total,docPending,todoEntries,grpRows,natD,natC,natMax});"""+t[j:]

# ---------- functions ----------
rep("// Stage 16: แบนเนอร์ข้อมูลพนักงานบนหน้าแดชบอร์ด",
r"""// ── Stage DASH-V2: หน้าหลักแบบ "วันนี้ต้องทำอะไร" ──
const DX_IC={
  alert:'<path d="M12 4 2.8 19.5h18.4L12 4Z"/><path d="M12 10v4.5M12 17.2v.1"/>',
  clock:'<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  d90:'<rect x="4" y="5.5" width="16" height="14" rx="1.8"/><path d="M4 10h16M8.5 3.5v4M15.5 3.5v4"/><path d="M9 14.5l2 2 4-4"/>',
  doc:'<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14 3.5v4h4M9 12h6M9 15.5h4"/>',
  list:'<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2"/><circle cx="4.5" cy="12" r="1.2"/><circle cx="4.5" cy="18" r="1.2"/>',
  emp:'<path d="M4 20V8l8-4 8 4v12"/><path d="M9 20v-5h6v5M8 10h.01M12 10h.01M16 10h.01"/>',
  passport:'<rect x="6" y="3.5" width="12" height="17" rx="1.8"/><circle cx="12" cy="10.5" r="3"/><path d="M9.5 16.5h5"/>',
  visa:'<rect x="3.5" y="6" width="17" height="12" rx="1.8"/><path d="M3.5 10h17"/><path d="M7 14.5h4M14.5 14.5h2.5"/>',
  wp:'<rect x="3.5" y="5.5" width="17" height="13" rx="1.8"/><circle cx="9" cy="11" r="2"/><path d="M6 15.5c.6-1.6 1.7-2.3 3-2.3s2.4.7 3 2.3M14 10h3.5M14 13h3.5"/>',
  mou:'<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14 3.5v4h4M9 12h6M9 15.5h4"/>',
  check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',
};
const DX_COL={red:['#C62828','#FDE8E8','#F6C9C9'],orange:['#E0620B','#FFF0E3','#FFD9BF'],blue:['#1D64B0','#E6F0FB','#C9DDF5'],amber:['#B26B00','#FDF1D8','#F3DCA8'],
  purple:['#6A4A9C','#EFE8F8','#DDD0F1'],green:['#17804A','#E2F4E9','#BFE3CC'],teal:['#0F7A70','#DCF3EF','#B5E3DB']};
const DX_KIND={passport:['พาสปอร์ต','blue'],visa:['วีซ่า','purple'],wp:['ใบอนุญาตทำงาน','green'],d90:['รายงานตัว 90 วัน','orange'],mou:['MOU','teal']};
const dxSvg=(k,c)=>`<svg viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${DX_IC[k]||''}</svg>`;
const dxIc=(k,col)=>{const c=DX_COL[col];return `<span class="dx-ic" style="background:${c[1]};border-color:${c[2]}">${dxSvg(k,c[0])}</span>`;};
const dxChip=d=>{const[bg,fg]=d<0||d<=7?['#FDE8E8','#C62828']:d<=30?['#FFF1DE','#B45309']:['#E5F4EA','#1F8A4C'];
  return `<span class="dx-chip" style="background:${bg};color:${fg}">${d<0?'เลย '+(-d)+' วัน':d===0?'วันนี้':'อีก '+d+' วัน'}</span>`;};
const dxFd=s=>{try{const x=new Date(_ceDate(s));return x.toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'2-digit'});}catch(_){return String(s||'');}};
// สถานะแจ้งเตือน LINE (โหลดครั้งละไม่เกิน 1 นาที) — ไม่มี SQL / เรียกไม่ได้ → ไม่แสดงป้าย
let _dxLine=null,_dxLineAt=0,_dxLineBusy=false;
async function dxLoadLine(){
  if(_dxLineBusy||Date.now()-_dxLineAt<60000||typeof _shareRpc!=='function'||!curUser)return;
  _dxLineBusy=true;
  try{const r=await _shareRpc('app_line_alert_status',{});_dxLineAt=Date.now();
    if(r.status==='ok'&&r.data){const sent=new Set();(r.data.sent||[]).forEach(x=>sent.add(x[0]+'|'+x[1]+'|'+String(x[2]).slice(0,10)));
      _dxLine={sent,emp:new Set(r.data.employers||[]),grp:new Set(r.data.groups||[])};
      if(curView==='dash'&&dashFilter==='all')renderDash();}}
  catch(_){}finally{_dxLineBusy=false;}
}
const _dxIso=s=>{try{const x=new Date(_ceDate(s));return x.getFullYear()+'-'+String(x.getMonth()+1).padStart(2,'0')+'-'+String(x.getDate()).padStart(2,'0');}catch(_){return'';}};
function dxItems(){
  const out=[];
  (customers||[]).forEach(c=>{
    [['passport',c.exp_passport,settings.passport],['visa',c.exp_visa,settings.visa],['wp',c.exp_wp,settings.wp],['d90',c.next_90,settings.next90],['mou',c.exp_mou,settings.mou]].forEach(([k,dt,w])=>{
      if(!dt)return;const d=du(dt);if(d===null||d>w)return;
      out.push({c,k,dt,d,line:!!(_dxLine&&_dxLine.sent.has(c.id+'|'+k+'|'+_dxIso(dt)))});});
  });
  return out.sort((a,b)=>a.d-b.d);
}
function dashV2HTML(o){
  const items=dxItems();
  const over=items.filter(x=>x.d<0&&x.k!=='d90'), soon=items.filter(x=>x.d>=0&&x.k!=='d90'), d90=items.filter(x=>x.k==='d90');
  const d90over=d90.filter(x=>x.d<0).length;
  const ppl=a=>new Set(a.map(x=>x.c.id)).size;
  const wmax=Math.max(settings.passport||0,settings.visa||0,settings.wp||0,settings.mou||0);
  const k=(cls,ic,col,label,n,sub,go)=>`<div class="dx-k${n?'':' zero'}" onclick="${go}"><div class="kh">${dxIc(ic,col)}<span>${label}</span></div><b style="color:${DX_COL[col][0]}">${n}</b><small>${sub}</small></div>`;
  const kpis=`<div class="dx-kpis">
    ${k('','alert','red','หมดอายุแล้ว',over.length,over.length?ppl(over)+' คน · ยังไม่ได้ต่อ':'ไม่มีเอกสารหมดอายุ',"dashGo('renew')")}
    ${k('','clock','orange','ใกล้หมดอายุ',soon.length,soon.length?ppl(soon)+' คน · ภายใน '+wmax+' วัน':'ภายใน '+wmax+' วัน',"dashGo('renew')")}
    ${k('','d90','blue','รายงานตัว 90 วัน',d90.length,(d90.length?ppl(d90)+' คน · ':'')+'ภายใน '+settings.next90+' วัน'+(d90over?' · เลย '+d90over:''),"dashGo('90')")}
    ${k('','doc','amber','เอกสารค้าง',o.docPending.length,'ใบแพทย์ / ประกัน / เล่ม / ค่าบัตร',"dashGo('docs')")}
  </div>
  <div class="dx-mini"><span onclick="gv('customers')"><b>${o.total}</b>แรงงานทั้งหมด</span><span onclick="gv('employers')"><b>${employers.length}</b>นายจ้าง</span><span onclick="dashGo('todo')"><b>${o.todoEntries.length}</b>นัดหมาย / คิว / รับเล่ม</span>${_dxLine?`<span onclick="gv('settings')"><b>${_dxLine.emp.size+_dxLine.grp.size}</b>เปิดแจ้งเตือน LINE</span>`:''}</div>`;
  // ต้องทำก่อน
  const top=items.slice(0,12);
  const row=x=>{const kd=DX_KIND[x.k],col=DX_COL[kd[1]];
    return `<div class="dx-row" onclick="openDetail(${x.c.id})">${dashCustAvatar(x.c,x.d<=7?'adot-r':x.d<=30?'adot-o':'adot-g')}
      <div class="dx-mid"><div class="dx-nm">${esc(x.c.name||x.c.name_th||'-')}</div><div class="dx-sub">${x.c.employer_id?esc(empN(x.c.employer_id)):T('dashNoBoss')}</div>
        <div class="dx-doc"><i style="background:${col[1]};border-color:${col[2]}">${dxSvg(x.k==='mou'?'mou':x.k,col[0])}</i>${kd[0]}</div></div>
      <div class="dx-r"><span class="dx-dt">${dxFd(x.dt)}</span>${dxChip(x.d)}${x.line?`<span class="dx-line">${dxSvg('check','#06A94D')}แจ้งนายจ้างทาง LINE แล้ว</span>`:''}</div></div>`;};
  const urgent=`<div class="dc"><div class="dx-h"><div class="t">${dxIc('list','orange')}ต้องทำก่อน</div>${items.length>top.length?`<a onclick="dashGo('renew')">ดูทั้งหมด ${items.length} รายการ ›</a>`:''}</div>
    ${top.length?top.map(row).join(''):`<div class="dx-ok">${dxSvg('check','#15803D').replace('<svg','<svg width="18" height="18"')}ไม่มีเอกสารที่ต้องต่อในช่วงเวลาแจ้งเตือน</div>`}</div>`;
  // แยกตามนายจ้าง
  const em={};items.forEach(x=>{const id=x.c.employer_id||0;const e=em[id]=em[id]||{id,over:0,soon:0,d90:0,n:0};e.n++;if(x.k==='d90')e.d90++;else if(x.d<0)e.over++;else e.soon++;});
  const emps=Object.values(em).sort((a,b)=>b.over-a.over||b.n-a.n).slice(0,8);
  const pill=(n,bg,fg,l)=>n?`<span style="background:${bg};color:${fg}" title="${l}">${n}</span>`:'';
  const empBox=`<div class="dc"><div class="dx-h"><div class="t">${dxIc('emp','teal')}แยกตามนายจ้าง</div><a onclick="gv('employers')">นายจ้างทั้งหมด ›</a></div>
    ${emps.length?emps.map(e=>`<div class="dx-emp" onclick="${e.id?`openEmpDet(${e.id})`:`dashGo('renew')`}"><span class="n">${e.id?esc(empN(e.id)):T('dashNoBoss')}</span>
      ${_dxLine&&e.id&&_dxLine.emp.has(e.id)?`<span class="dx-line" title="เปิดแจ้งเตือนเข้า LINE กลุ่มนายจ้างอยู่">${dxSvg('check','#06A94D')}LINE</span>`:''}
      <span class="dx-pills">${pill(e.over,'#FDE8E8','#C62828','หมดอายุแล้ว')}${pill(e.soon,'#FFF1DE','#B45309','ใกล้หมดอายุ')}${pill(e.d90,'#E6F0FB','#1D64B0','รายงานตัว 90 วัน')}</span></div>`).join('')
      +`<div style="display:flex;gap:10px;flex-wrap:wrap;font-size:11px;color:var(--g5);margin-top:8px"><span><b style="color:#C62828">●</b> หมดอายุแล้ว</span><span><b style="color:#B45309">●</b> ใกล้หมด</span><span><b style="color:#1D64B0">●</b> 90 วัน</span></div>`
      :'<div class="dx-empty">ไม่มีนายจ้างที่มีเอกสารต้องต่อ</div>'}</div>`;
  // ภาพรวม (สัญชาติ · กลุ่ม)
  const nat=`<div class="dc"><div class="dct">${T('dashByNat')}</div><div class="bc">${o.natD.map((d,i)=>`<div class="bc-b"><div class="bc-v" style="color:${o.natC[i]}">${d.v||''}</div><div class="bc-f" style="height:${Math.round(d.v/o.natMax*60)}px;background:${o.natC[i]}"></div><div class="bc-l">${d.l}</div></div>`).join('')}</div></div>`;
  const grp=o.grpRows.length?`<div class="dc"><div class="dct">${T('dashSummGrp')}</div><div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:6px">${o.grpRows.map(({g,cnt})=>`<div onclick="gv('customers',{grp:${g.id},title:${esc(JSON.stringify(g.name))}})" style="padding:8px 14px;background:var(--g0);border:1px solid var(--g2);border-radius:var(--r);cursor:pointer"><b>${esc(g.name)}</b> <span style="color:var(--p);font-weight:700;margin-left:4px">${cnt}</span></div>`).join('')}</div></div>`:'';
  setTimeout(dxLoadLine,0);
  return kpis+`<div class="dx-cols">${urgent}${empBox}</div><div class="dg3">${nat}${grp||'<div></div>'}</div>`;
}

// Stage 16: แบนเนอร์ข้อมูลพนักงานบนหน้าแดชบอร์ด""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

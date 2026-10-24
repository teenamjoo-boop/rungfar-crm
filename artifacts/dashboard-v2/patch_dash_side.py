# Stage DASH-SIDE — หน้าหลัก: ย้าย "แยกตามสัญชาติ" + "สรุปตามกลุ่มงาน" ไปคอลัมน์ขวา ใต้ "แยกตามนายจ้าง"
#   * สัญชาติ: แถวแนวนอน ธงชาติ (SVG) + แถบสีตามสีธง + จำนวน + % · กดแถว = ไปหน้าลูกค้ากรองสัญชาตินั้น
#   * กลุ่มงาน: รายการแบบเดียวกับนายจ้าง · กด = ดูแรงงานในกลุ่ม
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage DASH-SIDE' in t: print('already'); sys.exit(0)
assert 'Stage DASH-TABS-TRIM' in t, 'run patch_dash_tabs.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep(""".dx-cols{display:grid;grid-template-columns:minmax(0,1.6fr) minmax(0,1fr);gap:14px;margin-bottom:16px;align-items:start}""",""".dx-cols{display:grid;grid-template-columns:minmax(0,1.6fr) minmax(0,1fr);gap:14px;margin-bottom:16px;align-items:start}
/* Stage DASH-SIDE */
.dx-side{display:flex;flex-direction:column;gap:14px;min-width:0}
.dx-h .s{font-size:12px;color:var(--g5);font-weight:500}
.dx-nat{display:grid;grid-template-columns:24px minmax(64px,auto) 1fr 30px 38px;align-items:center;gap:9px;padding:8px 4px;border-top:1px solid var(--g1);cursor:pointer;border-radius:10px}
.dx-nat:hover,.dx-grp:hover{background:var(--g0)}
.dx-nat .fl{width:24px;height:24px;border-radius:50%;overflow:hidden;box-shadow:0 0 0 1px rgba(0,0,0,.08);display:block}
.dx-nat .fl svg{width:100%;height:100%;display:block}
.dx-nat .fl.none{background:var(--g1)}
.dx-nat .n{font-size:13px;font-weight:600;color:var(--g9);white-space:nowrap}
.dx-nat .br{height:8px;border-radius:99px;background:var(--g1);overflow:hidden}
.dx-nat .br i{display:block;height:100%;border-radius:99px}
.dx-nat b{font-size:14px;text-align:right;font-family:var(--mono)}
.dx-nat small{font-size:11.5px;color:var(--g5);text-align:right}
.dx-grp{display:flex;align-items:center;gap:9px;padding:9px 4px;border-top:1px solid var(--g1);cursor:pointer;border-radius:10px}
.dx-grp .n{flex:1;min-width:0;font-size:13px;font-weight:600;color:var(--g9);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dx-grp .c{font-size:12.5px;font-weight:700;color:var(--p);background:var(--pp);border-radius:99px;padding:1px 10px}""")
rep("""  check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',
};""","""  check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  globe:'<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.6 2.5 14.4 0 17M12 3.5c-2.5 2.6-2.5 14.4 0 17"/>',
  folder:'<path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4.2l2 2.2H19a1.5 1.5 0 0 1 1.5 1.5v8.3A1.5 1.5 0 0 1 19 19.5H5A1.5 1.5 0 0 1 3.5 18Z"/>',
};
// Stage DASH-SIDE: ธงชาติ (SVG 30x20) + สีตามธง
const DX_NAT={
  la:['ลาว','#2F5BC4','<rect width="30" height="20" fill="#ce1126"/><rect y="5" width="30" height="10" fill="#002868"/><circle cx="15" cy="10" r="4" fill="#fff"/>'],
  mm:['เมียนมา','#2E9E4F','<rect width="30" height="6.7" fill="#fecb00"/><rect y="6.7" width="30" height="6.6" fill="#34b233"/><rect y="13.3" width="30" height="6.7" fill="#ea2839"/><polygon fill="#fff" points="15.0,3.4 16.6,8.3 21.8,8.4 17.7,11.5 19.2,16.4 15.0,13.4 10.8,16.4 12.3,11.5 8.2,8.4 13.4,8.3"/>'],
  kh:['กัมพูชา','#D7263D','<rect width="30" height="20" fill="#032ea1"/><rect y="5" width="30" height="10" fill="#e00025"/><path fill="#fff" d="M9 13.6h12v-1H9zM10 12.6h10V11h-.8V9.6h-.7v1.4h-1V8.8h-.7V7.2h-.6V6h-.4v1.2h-.6v1.6h-.7V11h-1V9.6h-.7V11H10z"/>'],
  vn:['เวียดนาม','#E8A317','<rect width="30" height="20" fill="#da251d"/><polygon fill="#ff0" points="15.0,4.3 16.4,8.4 20.7,8.4 17.2,11.0 18.5,15.2 15.0,12.6 11.5,15.2 12.8,11.0 9.3,8.4 13.6,8.4"/>'],
  th:['ไทย','#6A4A9C','<rect width="30" height="20" fill="#a51931"/><rect y="3.3" width="30" height="13.4" fill="#f4f5f8"/><rect y="6.7" width="30" height="6.6" fill="#2d2a4a"/>']};
const dxNatKey=n=>{n=String(n||'').toLowerCase();return /ลาว|lao/.test(n)?'la':/เมียนมา|พม่า|myan|burm/.test(n)?'mm':/กัมพูชา|เขมร|camb|khmer/.test(n)?'kh':/เวียดนาม|viet/.test(n)?'vn':/ไทย|thai/.test(n)?'th':'';};
function dxNatGo(name){gv('customers');setTimeout(()=>{const s=document.getElementById('qnat');if(!s)return;const o=[...s.options].find(x=>x.value===name||x.textContent.includes(name));if(o){s.value=o.value;doFilter();}},0);}""")
a=t.index("  const nat=`<div class=\"dc\"><div class=\"dct\">${T('dashByNat')}</div>")
b=t.index("  setTimeout(dxLoadLine,0);",a)
t=t[:a]+r"""  // Stage DASH-SIDE: สัญชาติ (ธง + แถบสีตามธง) · กลุ่มงาน — อยู่คอลัมน์ขวา
  const nm={};customers.forEach(c=>{const k=dxNatKey(c.nationality)||'_';nm[k]=(nm[k]||0)+1;});
  const nTot=customers.length||1;const nRows=Object.entries(nm).sort((a,b)=>b[1]-a[1]);const nMax=Math.max(1,...nRows.map(r=>r[1]));
  const nat=`<div class="dc"><div class="dx-h"><div class="t">${dxIc('globe','blue')}แยกตามสัญชาติ</div><span class="s">${customers.length} คน</span></div>
    ${nRows.length?nRows.map(([k,v])=>{const N=DX_NAT[k];const lbl=N?N[0]:'อื่นๆ / ไม่ระบุ';const col=N?N[1]:'#9CA3AF';
      return `<div class="dx-nat" onclick="${N?`dxNatGo('${N[0]}')`:`gv('customers')`}"><span class="fl${N?'':' none'}">${N?`<svg viewBox="0 0 30 20" preserveAspectRatio="xMidYMid slice" aria-hidden="true">${N[2]}</svg>`:''}</span><span class="n">${lbl}</span><span class="br"><i style="width:${Math.max(4,Math.round(v/nMax*100))}%;background:${col}"></i></span><b style="color:${col}">${v}</b><small>${Math.round(v/nTot*100)}%</small></div>`;}).join('')
      :'<div class="dx-empty">ยังไม่มีแรงงาน</div>'}</div>`;
  const grp=o.grpRows.length?`<div class="dc"><div class="dx-h"><div class="t">${dxIc('folder','amber')}สรุปตามกลุ่มงาน</div><a onclick="gv('groups')">จัดการกลุ่ม ›</a></div>
    ${o.grpRows.map(({g,cnt})=>`<div class="dx-grp" onclick="gv('customers',{grp:${g.id},title:${esc(JSON.stringify(g.name))}})"><span class="n">${esc(g.name)}</span><span class="c">${cnt} คน</span></div>`).join('')}</div>`:'';
"""+t[b:]
rep("""  return kpis+`<div class="dx-cols">${urgent}${empBox}</div><div class="dg3">${nat}${grp||'<div></div>'}</div>`;""","""  return kpis+`<div class="dx-cols">${urgent}<div class="dx-side">${empBox}${nat}${grp}</div></div>`;""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

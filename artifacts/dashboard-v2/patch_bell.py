# Stage NOTIFY-BELL — แทนแถบเหลือง "มี N รายการที่ต้องดำเนินการ" ด้วยกระดิ่งมุมขวาบน
#   * ตัวเลขแดง = จำนวนเอกสารที่ถึงช่วงแจ้งเตือน (รวมที่หมดอายุแล้ว) ตามหน้าตั้งค่าแจ้งเตือน
#   * กดแล้วเปิดแผงรายการย่อ: หมดอายุแล้ว / ใกล้หมดอายุ / รายงานตัว 90 วัน · กดชื่อ = เปิดข้อมูลแรงงาน
#   ต้องใช้กับ Stage DASH-V2 (dxItems / DX_* )
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage NOTIFY-BELL' in t: print('already'); sys.exit(0)
assert 'Stage DASH-V2' in t, 'run patch_dash.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep(".abanner{background:#FFFBEB;",""".nb-btn{position:relative}
.nb-btn .nb-cnt{position:absolute;top:-6px;right:-7px;min-width:17px;height:17px;padding:0 4px;border-radius:99px;background:#DC2626;color:#fff;font-size:10.5px;font-weight:700;line-height:17px;text-align:center;display:none;box-shadow:0 0 0 2px #fff}
.nb-btn.has{color:#E0620B;border-color:#FFD9BF;background:#FFF0E3}
.nb-pan{position:fixed;top:60px;right:16px;width:380px;max-width:calc(100vw - 24px);max-height:min(72vh,620px);background:#fff;border:1px solid var(--g2);border-radius:16px;box-shadow:0 16px 40px rgba(0,0,0,.16);z-index:300;display:none;flex-direction:column;overflow:hidden}
.nb-pan.on{display:flex}
.nb-hd{display:flex;align-items:center;justify-content:space-between;padding:13px 16px;border-bottom:1px solid var(--g1)}
.nb-hd b{font-size:15px;color:var(--g9)}
.nb-hd span{font-size:12px;color:var(--g5)}
.nb-bd{overflow-y:auto;padding:4px 8px 8px}
.nb-sec{font-size:11.5px;font-weight:700;color:var(--g5);padding:10px 8px 4px;display:flex;align-items:center;gap:6px}
.nb-sec i{width:7px;height:7px;border-radius:99px;display:inline-block}
.nb-it{display:flex;align-items:center;gap:10px;padding:8px;border-radius:10px;cursor:pointer}
.nb-it:hover{background:var(--g0)}
.nb-it .nb-ic{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;border:1.5px solid;flex:none}
.nb-it .nb-ic svg{width:16px;height:16px}
.nb-it .m{flex:1;min-width:0}
.nb-it .n{font-size:13px;font-weight:700;color:var(--g9);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nb-it .s{font-size:11.5px;color:var(--g5);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nb-it .r{text-align:right;flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:3px}
.nb-it .r .d{font-size:11.5px;font-weight:700;color:var(--g8)}
.nb-ft{display:flex;gap:8px;padding:10px 12px;border-top:1px solid var(--g1)}
.nb-ft button{flex:1}
.nb-empty{text-align:center;color:var(--g5);font-size:13px;padding:30px 10px}
@media(max-width:760px){.nb-pan{top:56px;right:12px;left:12px;width:auto;max-height:75vh}}
.abanner{background:#FFFBEB;""")
rep("""      <button class="theme-btn" id="themeBtnApp" onclick="toggleTheme()\"""","""      <button class="theme-btn nb-btn" id="nbBtn" onclick="nbToggle(event)" aria-label="แจ้งเตือนเอกสาร" title="แจ้งเตือนเอกสาร"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z"/><path d="M10 20.5a2 2 0 0 0 4 0"/></svg><span class="nb-cnt" id="nbCnt"></span></button>
      <button class="theme-btn" id="themeBtnApp" onclick="toggleTheme()\"""")
rep("""  <div class="abanner" id="abanner"></div>""","""  <div class="abanner" id="abanner"></div>
  <div class="nb-pan" id="nbPan" onclick="event.stopPropagation()"></div>""")
rep("""  const ab=document.getElementById('abanner');
  if(al.length>0){""","""  // Stage NOTIFY-BELL: แถบเหลืองย้ายไปเป็นกระดิ่งมุมขวาบน
  nbUpdate();
  const ab=document.getElementById('abanner');
  if(false){""")
rep("""      if(curView==='dash'&&dashFilter==='all')renderDash();}}""","""      if(curView==='dash'&&dashFilter==='all')renderDash();else nbUpdate();}}""")
rep("""// Stage 16: แบนเนอร์ข้อมูลพนักงานบนหน้าแดชบอร์ด""",r"""// ── Stage NOTIFY-BELL: กระดิ่งแจ้งเตือนเอกสาร ──
function nbUpdate(){
  const b=document.getElementById('nbBtn'),c=document.getElementById('nbCnt');if(!b||!c)return;
  let n=0;try{n=dxItems().length;}catch(_){}
  c.textContent=n>99?'99+':String(n);c.style.display=n?'block':'none';b.classList.toggle('has',!!n);
  b.title=n?('เอกสารที่ต้องดำเนินการ '+n+' รายการ'):'ไม่มีเอกสารที่ต้องดำเนินการ';
  const pan=document.getElementById('nbPan');if(pan&&pan.classList.contains('on'))nbRender();
}
function nbRender(){
  const pan=document.getElementById('nbPan');if(!pan)return;
  const items=dxItems();
  const over=items.filter(x=>x.d<0&&x.k!=='d90'),soon=items.filter(x=>x.d>=0&&x.k!=='d90'),d90=items.filter(x=>x.k==='d90');
  const it=x=>{const kd=DX_KIND[x.k],col=DX_COL[kd[1]];
    return `<div class="nb-it" onclick="nbClose();openDetail(${x.c.id})"><span class="nb-ic" style="background:${col[1]};border-color:${col[2]}">${dxSvg(x.k,col[0])}</span>
      <div class="m"><div class="n">${esc(x.c.name||x.c.name_th||'-')}</div><div class="s">${kd[0]} · ${x.c.employer_id?esc(empN(x.c.employer_id)):T('dashNoBoss')}</div></div>
      <div class="r"><span class="d">${dxFd(x.dt)}</span>${dxChip(x.d)}${x.line?`<span class="dx-line">${dxSvg('check','#06A94D')}LINE แล้ว</span>`:''}</div></div>`;};
  const sec=(lbl,col,arr)=>arr.length?`<div class="nb-sec"><i style="background:${col}"></i>${lbl} · ${arr.length}</div>${arr.map(it).join('')}`:'';
  pan.innerHTML=`<div class="nb-hd"><b>แจ้งเตือนเอกสาร</b><span>${items.length} รายการ</span></div>
    <div class="nb-bd">${items.length?sec('หมดอายุแล้ว','#C62828',over)+sec('ใกล้หมดอายุ','#E0620B',soon)+sec('รายงานตัว 90 วัน','#1D64B0',d90)
      :'<div class="nb-empty">ไม่มีเอกสารที่ต้องดำเนินการ</div>'}</div>
    <div class="nb-ft"><button class="btn btn-p btn-sm" onclick="nbClose();dashGo('renew')">ดูทั้งหมดในหน้าหลัก</button>${curUser&&curUser.role==='admin'?`<button class="btn btn-g btn-sm" onclick="nbClose();gv('settings')">ตั้งค่าแจ้งเตือน</button>`:''}</div>`;
}
function nbToggle(ev){if(ev)ev.stopPropagation();const pan=document.getElementById('nbPan');if(!pan)return;
  if(pan.classList.contains('on')){nbClose();return;}
  nbRender();pan.classList.add('on');try{dxLoadLine();}catch(_){}}
function nbClose(){const pan=document.getElementById('nbPan');if(pan)pan.classList.remove('on');}
document.addEventListener('click',e=>{const pan=document.getElementById('nbPan');if(pan&&pan.classList.contains('on')&&!e.target.closest('#nbBtn'))nbClose();});
document.addEventListener('keydown',e=>{if(e.key==='Escape')nbClose();});

// Stage 16: แบนเนอร์ข้อมูลพนักงานบนหน้าแดชบอร์ด""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

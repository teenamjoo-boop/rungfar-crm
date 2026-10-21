# Stage SHARE-TWEAK3 (2026-10-17) — ต่อจาก SHARE-TWEAK2
#  - กรอบโลโก้/ชื่อนายจ้าง: ใสมาก เห็นพื้นหลังชัด ไม่เบลอ
#  - ตัวดู PDF:
#      * คอม (เมาส์ + จอกว้าง): ใช้ตัวดู PDF ของเบราว์เซอร์เอง (แบบเปิดใน Chrome — มีบันทึก/พิมพ์/หมุน/ซูม ในตัว)
#      * มือถือ: แถบเครื่องมือแบบ Chrome — หน้า x/y · ย่อ/ขยาย · พอดีหน้า · หมุน · บันทึก · พิมพ์
import sys,io
path=sys.argv[1]
s=io.open(path,encoding='utf-8',newline='').read()
NL='\r\n' if s.count('\r\n')>s.count('\n')//2 else '\n'
def rep(old,new,count=1):
    global s
    old=old.replace('\n',NL); new=new.replace('\n',NL)
    n=s.count(old)
    if n!=count: raise SystemExit(f'anchor x{n} (want {count}): {old[:90]!r}')
    s=s.replace(old,new)
if 'Stage SHARE-TWEAK3' in s: raise SystemExit('already patched')
if 'Stage SHARE-TWEAK2' not in s: raise SystemExit('needs SHARE-TWEAK2 first')

IC={
 'fit':'<svg viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
 'rot':'<svg viewBox="0 0 24 24"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg>',
 'dl':'<svg viewBox="0 0 24 24"><path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></svg>',
 'pr':'<svg viewBox="0 0 24 24"><path d="M7 9V3h10v6"/><rect x="3" y="9" width="18" height="8" rx="2"/><path d="M7 14h10v7H7z"/></svg>',
}
# 1) แถบเครื่องมือ PDF (มือถือ) แทนปุ่มซูมลอยด้านล่าง
rep("""  <div class="pdfz" id="pdfz"><button onclick="zoomPdf(-1)" aria-label="ย่อ">−</button><span id="pdfzv">100%</span><button onclick="zoomPdf(1)" aria-label="ขยาย">+</button></div>""",
f"""  <div class="pdft" id="pdft">
    <span class="pg" id="pdfPg">1 / 1</span>
    <span class="zg"><button onclick="zoomPdf(-1)" aria-label="ย่อ">−</button><span id="pdfzv">100%</span><button onclick="zoomPdf(1)" aria-label="ขยาย">+</button></span>
    <button class="ib" onclick="fitPdf()" aria-label="พอดีหน้า" title="พอดีหน้า">{IC['fit']}</button>
    <button class="ib" onclick="rotPdf()" aria-label="หมุน" title="หมุน">{IC['rot']}</button>
    <span class="sp"></span>
    <button class="ib tx" onclick="savePdf()" aria-label="บันทึก">{IC['dl']}<span>บันทึก</span></button>
    <button class="ib tx" onclick="printPdf()" aria-label="พิมพ์">{IC['pr']}<span>พิมพ์</span></button>
  </div>""")

# 2) ปุ่มดาวน์โหลด: รองรับไฟล์ที่เป็น data URL (เอกสารเก่า) + ตั้งชื่อไฟล์
rep("function setDl(u){ const a=document.getElementById('ivDl'); if(!a) return; if(u){ a.href=u; a.hidden=false; } else { a.removeAttribute('href'); a.hidden=true; } }",
    "function setDl(u, name){ const a=document.getElementById('ivDl'); if(!a) return; if(u){ a.href=u; a.hidden=false; if(/^data:/.test(u)) a.download=(name||'เอกสาร').replace(/[\\\\/:*?\"<>|]+/g,' ')+'.pdf'; else a.removeAttribute('download'); } else { a.removeAttribute('href'); a.removeAttribute('download'); a.hidden=true; } }")

# 3) pdfStop: ล้าง blob/โหมดตัวดูของเบราว์เซอร์/ตัวติดตามหน้า
rep("""  document.getElementById('iv').classList.remove('pdfon');
  document.getElementById('ivImg').classList.remove('pdf');
  if(!v) return;""",
"""  document.getElementById('iv').classList.remove('pdfon','pdfnat');
  const _bx=document.getElementById('ivImg'); _bx.classList.remove('pdf','nat'); _bx.onscroll=null;
  if(!v) return;
  if(v.blob){ try{ URL.revokeObjectURL(v.blob); }catch(_){} }""")

# 4) showPdf: คอม → ตัวดูของเบราว์เซอร์ · มือถือ → PDF.js + แถบเครื่องมือ
rep("""  const my = PDFV = {zoom:1, pages:[], vis:new Set(), io:null, load:null, doc:null};
  try{""",
"""  const my = PDFV = {zoom:1, rot:0, pages:[], vis:new Set(), io:null, load:null, doc:null, src, label};
  if(PDF_NATIVE()){   // Stage SHARE-TWEAK3: คอม — ใช้ตัวดู PDF ของเบราว์เซอร์ (บันทึก/พิมพ์/หมุน ในตัว)
    try{
      const buf = await (await fetch(src)).arrayBuffer();
      if(PDFV!==my) return;
      my.blob = URL.createObjectURL(new Blob([buf],{type:'application/pdf'}));
      box.classList.remove('pdf'); box.classList.add('nat');
      box.innerHTML = `<iframe class="pdfnat" title="${esc(label)}" src="${my.blob}#view=FitH"></iframe>`;
      document.getElementById('iv').classList.add('pdfnat');
      return;
    }catch(_){ if(PDFV!==my) return; box.classList.remove('nat'); box.classList.add('pdf'); }
  }
  try{""")
rep("""    document.getElementById('iv').classList.add('pdfon');
    pdfLayout(my);""",
"""    document.getElementById('iv').classList.add('pdfon');
    pdfLayout(my);
    box.onscroll = () => pdfPgNow(my);   // Stage SHARE-TWEAK3: หน้าปัจจุบัน
    pdfPgNow(my);""")

# 5) วาดหน้าแบบหมุนได้
rep("    const v0=pg.page.getViewport({scale:1});\n    if(Math.abs(v0.height/v0.width - pg.ratio)>0.001)",
    "    const v0=pg.page.getViewport({scale:1, rotation:my.rot});\n    if(Math.abs(v0.height/v0.width - pg.ratio)>0.001)")
rep("    const vp=pg.page.getViewport({scale});", "    const vp=pg.page.getViewport({scale, rotation:my.rot});")

# 6) ฟังก์ชันใหม่
rep("let _pdfRz=0;", """// ── Stage SHARE-TWEAK3: แถบเครื่องมือ PDF ──
const PDF_NATIVE = () => { try{ return matchMedia('(pointer:fine) and (min-width:900px)').matches && !/\\bLine\\//i.test(navigator.userAgent); }catch(_){ return false; } };
function pdfPgNow(my){
  if(PDFV!==my||!my.pages.length) return;
  const box=document.getElementById('ivImg'), y=box.scrollTop+box.clientHeight*0.35;
  let n=1; for(const pg of my.pages){ if(pg.el.offsetTop<=y) n=pg.n; else break; }
  const el=document.getElementById('pdfPg'); if(el) el.textContent=n+' / '+my.pages.length;
}
function fitPdf(){
  const my=PDFV; if(!my||!my.pages.length) return;
  const box=document.getElementById('ivImg'), cur=my.pages[0];
  const fitPage=Math.max(0.25, Math.min(1, (box.clientHeight-20)/((box.clientWidth-16)*cur.ratio)));
  my.zoom = Math.abs(my.zoom-1)<0.001 ? fitPage : 1;
  pdfLayout(my); my.vis.forEach(pg=>pdfDraw(my,pg)); pdfPgNow(my);
}
function rotPdf(){
  const my=PDFV; if(!my||!my.pages.length) return;
  my.rot=(my.rot+90)%360;
  my.pages.forEach(pg=>{ pg.done=0; if(pg.page){ const v=pg.page.getViewport({scale:1, rotation:my.rot}); pg.ratio=v.height/v.width; } else pg.ratio=1/pg.ratio; });
  pdfLayout(my); my.vis.forEach(pg=>pdfDraw(my,pg)); pdfPgNow(my);
}
function savePdf(){
  const a=document.getElementById('ivDl');
  if(a&&a.href&&!a.hidden){ a.click(); return; }
  toast('ไฟล์นี้บันทึกไม่ได้');
}
async function printPdf(){
  const my=PDFV; if(!my||!my.doc) return;
  if(/\\bLine\\//i.test(navigator.userAgent)){ toast('แอป LINE พิมพ์ไม่ได้ — กด "บันทึก" หรือเปิดลิงก์ใน Chrome/Safari'); return; }
  toast('กำลังเตรียมพิมพ์…');
  try{
    const out=document.getElementById('pdfPrint')||document.body.appendChild(Object.assign(document.createElement('div'),{id:'pdfPrint'}));
    out.innerHTML='';
    for(let n=1;n<=my.doc.numPages;n++){
      const page=await my.doc.getPage(n); if(PDFV!==my) return;
      const v0=page.getViewport({scale:1, rotation:my.rot});
      const scale=Math.min(1600/v0.width, Math.sqrt(14e6/(v0.width*v0.height)));
      const vp=page.getViewport({scale, rotation:my.rot});
      const cv=document.createElement('canvas'); cv.width=Math.floor(vp.width); cv.height=Math.floor(vp.height);
      await page.render({canvasContext:cv.getContext('2d'), viewport:vp}).promise;
      const im=new Image(); im.src=cv.toDataURL('image/jpeg',0.92); out.appendChild(im);
    }
    await Promise.all([...out.querySelectorAll('img')].map(i=>i.decode().catch(()=>{})));
    document.body.classList.add('pdfprint');
    const done=()=>{ document.body.classList.remove('pdfprint'); out.innerHTML=''; window.removeEventListener('afterprint',done); };
    window.addEventListener('afterprint',done);
    setTimeout(()=>{ window.print(); setTimeout(()=>{ if(!matchMedia('print').matches) done(); },1500); },60);
  }catch(_){ toast('เตรียมพิมพ์ไม่สำเร็จ — กด "บันทึก" แล้วพิมพ์จากไฟล์'); }
}
let _pdfRz=0;""")

# 7) openDoc: ปุ่มดาวน์โหลดใช้ได้กับไฟล์ data URL ด้วย
rep("    if(isPdf){ showPdf(label, src, dlUrl(d.url)); return; }",
    "    if(isPdf){ showPdf(label, src, dlUrl(d.url)||(/^data:application\\/pdf/.test(src||'')?src:null)); setDl(dlUrl(d.url)||(/^data:application\\/pdf/.test(src||'')?src:null), label); return; }")

# 8) CSS
rep("</style>","""/* Stage SHARE-TWEAK3 */
.hd .logo,.hdglass{background:rgba(255,255,255,.16);border:0;border-radius:12px;-webkit-backdrop-filter:none;backdrop-filter:none} /* = .stat (ใกล้ครบกำหนด) */
.hdglass{padding:9px 10px}
.hd.has-bg .hdglass,.hd.has-bg .logo{text-shadow:none}
.iv.pdfon .pdfz{display:none}
.iv .img{order:2}.pdft{order:1;display:none;align-items:center;gap:4px;padding:6px 10px;background:#323639;color:#fff;border-top:1px solid rgba(255,255,255,.08);box-shadow:0 2px 6px rgba(0,0,0,.35);flex:none;overflow-x:auto}
.iv.pdfon .pdft{display:flex}
.pdft .pg{font-size:13px;min-width:46px;text-align:center;background:rgba(0,0,0,.35);padding:4px 8px;border-radius:6px;white-space:nowrap}
.pdft .zg{display:flex;align-items:center;gap:2px;margin-left:4px}
.pdft .zg button,.pdft .ib{color:#fff;height:34px;min-width:34px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;gap:4px;font-size:18px;line-height:1;padding:0 6px;flex:none}
.pdft .zg button:active,.pdft .ib:active{background:rgba(255,255,255,.16)}
.pdft #pdfzv{font-size:12.5px;min-width:44px;text-align:center}
.pdft .ib svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.pdft .ib.tx{font-size:12.5px;background:rgba(255,255,255,.1);padding:0 9px}
.pdft .sp{flex:1}
.iv.pdfon .bar2 a.dl{display:none}
.iv .img.nat{display:block;padding:0;overflow:hidden}
.iv .img.nat iframe{display:block;width:100%;height:100%;border:0;background:#525659}
#pdfPrint{display:none}
@media print{
  body.pdfprint>*:not(#pdfPrint){display:none!important}
  body.pdfprint #pdfPrint{display:block!important}
  #pdfPrint img{display:block;width:100%;height:auto;break-after:page;page-break-after:always}
  @page{margin:8mm}
}
</style>""")
io.open(path,'w',encoding='utf-8',newline='').write(s)
print('patched',path)

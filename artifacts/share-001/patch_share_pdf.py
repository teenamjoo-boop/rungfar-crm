# Stage SHARE-PDF: เปิดไฟล์ PDF ในหน้าต่างดูเอกสารบนหน้าเดิม (เหมือนรูปภาพ) — ไม่เด้งไปหน้าใหม่บนมือถือ
#  - วาดทีละหน้าด้วย PDF.js (pdfjs-dist 4.10.38 legacy build จาก jsDelivr — โหลดเฉพาะตอนเปิด PDF ครั้งแรก)
#  - เลื่อนดูหลายหน้า · ปุ่มซูม − / + · ปุ่ม "ดาวน์โหลด" (ทั้ง PDF และรูป)
#  - วาดเฉพาะหน้าที่กำลังจะเห็น (ไฟล์หลายหน้าไม่หนักเครื่อง) · isEvalSupported:false
#  - โหลด PDF.js ไม่ได้ → แสดงปุ่ม "เปิดไฟล์ PDF" แบบเดิมแทน
import sys

MARK = 'Stage SHARE-PDF'

CSS = '''/* Stage SHARE-PDF: ดู PDF ในหน้าเดิม */
#ivT{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
.iv .bar2 .ivr{display:flex;gap:8px;flex:none;align-items:center}
.iv .bar2 a.dl{color:#fff;background:var(--brand);padding:6px 14px;border-radius:99px;font-weight:600;text-decoration:none}
.iv .img.pdf{display:block;padding:8px 8px 84px;overflow:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}
.pdfp{position:relative;margin:0 auto 10px;background:#fff;border-radius:4px;box-shadow:0 2px 12px rgba(0,0,0,.4)}
.pdfp canvas{display:block;width:100%;height:100%;border-radius:4px}
.pdfp .pn{position:absolute;right:6px;bottom:6px;font-size:11px;color:#555;background:rgba(255,255,255,.88);padding:1px 7px;border-radius:99px}
.pdfmsg{color:#ddd;text-align:center;padding:48px 16px;line-height:1.8;font-size:14px}
.pdfmsg a{display:inline-block;margin-top:12px;color:#fff;background:var(--brand);padding:9px 20px;border-radius:99px;font-weight:600;text-decoration:none}
.pdfz{position:absolute;left:50%;bottom:calc(16px + env(safe-area-inset-bottom));transform:translateX(-50%);display:none;align-items:center;gap:4px;background:rgba(28,24,20,.92);border-radius:99px;padding:4px;color:#fff;box-shadow:0 4px 16px rgba(0,0,0,.4)}
.iv.pdfon .pdfz{display:flex}
.pdfz button{width:42px;height:38px;border-radius:99px;color:#fff;font-size:20px;line-height:1;background:rgba(255,255,255,.12)}
.pdfz span{min-width:54px;text-align:center;font-size:13px}
'''

JS = r'''// Stage SHARE-PDF: เปิด PDF ในหน้าต่างดูเอกสาร (วาดด้วย PDF.js) — ไม่เด้งไปหน้าใหม่
const PDFJS_URL='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.min.mjs';
const PDFJS_WORKER='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/legacy/build/pdf.worker.min.mjs';
let _pdfLibP=null, PDFV=null;
function pdfLib(){
  if(!_pdfLibP){ _pdfLibP=import(PDFJS_URL).then(m=>{ m.GlobalWorkerOptions.workerSrc=PDFJS_WORKER; return m; }); _pdfLibP.catch(()=>{ _pdfLibP=null; }); }
  return _pdfLibP;
}
const dlUrl = u => /^https:\/\//.test(u||'') ? u+(u.includes('?')?'&':'?')+'download=' : null;
function setDl(u){ const a=document.getElementById('ivDl'); if(!a) return; if(u){ a.href=u; a.hidden=false; } else { a.removeAttribute('href'); a.hidden=true; } }
function pdfStop(){
  const v=PDFV; PDFV=null;
  document.getElementById('iv').classList.remove('pdfon');
  document.getElementById('ivImg').classList.remove('pdf');
  if(!v) return;
  try{ v.io&&v.io.disconnect(); }catch(_){}
  v.pages.forEach(p=>{ try{ p.task&&p.task.cancel(); }catch(_){} });
  try{ v.load&&v.load.destroy(); }catch(_){}
}
async function showPdf(label, src, dl){
  pdfStop();
  showViewer(label, '<div class="pdfmsg">กำลังโหลดเอกสาร…</div>');
  setDl(dl);
  const box=document.getElementById('ivImg'); box.classList.add('pdf');
  const my = PDFV = {zoom:1, pages:[], vis:new Set(), io:null, load:null, doc:null};
  try{
    const lib = await pdfLib();
    if(PDFV!==my) return;
    const opt = {isEvalSupported:false};
    if(/^data:/.test(src)) opt.data = new Uint8Array(await (await fetch(src)).arrayBuffer()); else opt.url = src;
    my.load = lib.getDocument(opt);
    const doc = await my.load.promise;
    if(PDFV!==my){ try{ doc.destroy(); }catch(_){} return; }
    my.doc = doc;
    const p1 = await doc.getPage(1);
    const v1 = p1.getViewport({scale:1});
    box.innerHTML='';
    for(let n=1;n<=doc.numPages;n++){
      const el=document.createElement('div'); el.className='pdfp'; el.dataset.n=n;
      el.innerHTML=`<span class="pn">${n} / ${doc.numPages}</span>`;
      box.appendChild(el);
      my.pages.push({n, el, ratio:v1.height/v1.width, page:n===1?p1:null, done:0, task:null});
    }
    document.getElementById('iv').classList.add('pdfon');
    pdfLayout(my);
    my.io = new IntersectionObserver(es=>{ es.forEach(e=>{ const pg=my.pages[Number(e.target.dataset.n)-1]; if(e.isIntersecting){ my.vis.add(pg); pdfDraw(my,pg); } else my.vis.delete(pg); }); }, {root:box, rootMargin:'700px 0px'});
    my.pages.forEach(pg=>my.io.observe(pg.el));
  }catch(e){
    if(PDFV!==my) return;
    document.getElementById('iv').classList.remove('pdfon'); box.classList.remove('pdf');
    box.innerHTML = /^https:\/\//.test(src)
      ? `<div class="pdfmsg">แสดงไฟล์ในหน้านี้ไม่ได้<br><a href="${esc(src)}" target="_blank" rel="noopener">เปิดไฟล์ PDF</a></div>`
      : '<div class="pdfmsg">ไม่สามารถแสดงไฟล์นี้ได้</div>';
  }
}
function pdfCssW(my){ const box=document.getElementById('ivImg'); return Math.max(200, (box.clientWidth-16)*my.zoom); }
function pdfLayout(my){
  const w=pdfCssW(my);
  my.pages.forEach(pg=>{ pg.el.style.width=w+'px'; pg.el.style.height=Math.round(w*pg.ratio)+'px'; });
  document.getElementById('pdfzv').textContent=Math.round(my.zoom*100)+'%';
}
async function pdfDraw(my, pg){
  const w=pdfCssW(my);
  if(pg.done===w || pg.busy===w) return;
  pg.busy=w;
  try{
    if(!pg.page) pg.page = await my.doc.getPage(pg.n);
    if(PDFV!==my) return;
    const v0=pg.page.getViewport({scale:1});
    if(Math.abs(v0.height/v0.width - pg.ratio)>0.001){ pg.ratio=v0.height/v0.width; pg.el.style.height=Math.round(w*pg.ratio)+'px'; }
    const dpr=Math.min(window.devicePixelRatio||1, 2);
    const scale=Math.min(w*dpr/v0.width, Math.sqrt(14e6/(v0.width*v0.height)));   // จำกัดขนาด canvas (iOS)
    const vp=pg.page.getViewport({scale});
    const cv=document.createElement('canvas'); cv.width=Math.floor(vp.width); cv.height=Math.floor(vp.height);
    if(pg.task){ try{ pg.task.cancel(); }catch(_){} }
    pg.task = pg.page.render({canvasContext:cv.getContext('2d'), viewport:vp});
    await pg.task.promise;
    if(PDFV!==my || pg.busy!==w) return;
    const old=pg.el.querySelector('canvas'); if(old) old.remove();
    pg.el.insertBefore(cv, pg.el.firstChild);
    pg.done=w;
  }catch(_){ /* ยกเลิก/วาดไม่สำเร็จ — ลองใหม่เมื่อเลื่อนมาอีกครั้ง */ }
  finally{ if(pg.busy===w) pg.busy=0; }
}
function zoomPdf(dir){
  const my=PDFV; if(!my||!my.pages.length) return;
  const steps=[0.5,0.75,1,1.25,1.5,2,2.5,3];
  let i=steps.findIndex(s=>s>=my.zoom-0.001); if(i<0) i=steps.length-1;
  const z=steps[Math.max(0,Math.min(steps.length-1,i+dir))]; if(z===my.zoom) return;
  const box=document.getElementById('ivImg');
  const fy=(box.scrollTop+box.clientHeight/2)/Math.max(1,box.scrollHeight), fx=(box.scrollLeft+box.clientWidth/2)/Math.max(1,box.scrollWidth);
  my.zoom=z; pdfLayout(my);
  box.scrollTop=fy*box.scrollHeight-box.clientHeight/2; box.scrollLeft=fx*box.scrollWidth-box.clientWidth/2;
  my.vis.forEach(pg=>pdfDraw(my,pg));
}
let _pdfRz=0;
window.addEventListener('resize',()=>{ clearTimeout(_pdfRz); _pdfRz=setTimeout(()=>{ const my=PDFV; if(my&&my.pages.length){ pdfLayout(my); my.vis.forEach(pg=>pdfDraw(my,pg)); } },200); });
'''

OPEN_OLD = '''    if(isPdf){
      if(src.startsWith('data:')){ const b=await (await fetch(src)).blob(); src=URL.createObjectURL(b); }
      window.open(src,'_blank','noopener');
      return;
    }
    showViewer(label, `<img src="${esc(src)}" alt="" onerror="this.replaceWith('ไม่สามารถแสดงไฟล์นี้ได้')">`);'''
OPEN_NEW = '''    if(isPdf){ showPdf(label, src, dlUrl(d.url)); return; }   // Stage SHARE-PDF: เปิดในหน้าเดิม
    pdfStop();
    showViewer(label, `<img src="${esc(src)}" alt="" onerror="this.replaceWith('ไม่สามารถแสดงไฟล์นี้ได้')">`);
    setDl(dlUrl(d.url));'''


def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:90]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHARE-FAST' not in s:
        sys.exit(path + ': ต้องมี SHARE-FAST ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    s = rep(s, '</style>', CSS + '</style>', path)
    s = rep(s, '<div class="bar2"><span id="ivT"></span><button onclick="history.back()">ปิด</button></div>\n  <div class="img" id="ivImg"></div>\n</div>',
            '<div class="bar2"><span id="ivT"></span><span class="ivr"><a class="dl" id="ivDl" target="_blank" rel="noopener" hidden>ดาวน์โหลด</a><button onclick="history.back()">ปิด</button></span></div>\n'
            '  <div class="img" id="ivImg"></div>\n'
            '  <div class="pdfz" id="pdfz"><button onclick="zoomPdf(-1)" aria-label="ย่อ">−</button><span id="pdfzv">100%</span><button onclick="zoomPdf(1)" aria-label="ขยาย">+</button></div>\n</div>', path)
    s = rep(s, OPEN_OLD, OPEN_NEW, path)
    # โหลด PDF.js ล่วงหน้าเมื่อแตะไฟล์ที่รู้ว่าเป็น PDF
    s = rep(s, '<button class="fr" data-id="${Number(f.id)}" data-n="${esc(nm)}" onclick="openFile(this)">',
            '<button class="fr" data-id="${Number(f.id)}" data-n="${esc(nm)}" data-pdf="${f.pdf?1:0}" onclick="openFile(this)">', path)
    s = rep(s, "function openFile(el){ openDoc(",
            "function openFile(el){ if(el.dataset.pdf==='1') pdfLib().catch(()=>{}); openDoc(", path)
    s = rep(s, "function closeImg(){ document.getElementById('iv').classList.remove('open'); document.getElementById('ivImg').innerHTML=''; }",
            "function closeImg(){ pdfStop(); setDl(null); document.getElementById('iv').classList.remove('open'); document.getElementById('ivImg').innerHTML=''; }", path)
    s = rep(s, 'function showViewer(title, html){', JS + 'function showViewer(title, html){', path)
    open(path, 'wb').write(s.replace('\n', nl).encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

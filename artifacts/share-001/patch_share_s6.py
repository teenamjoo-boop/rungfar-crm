# Stage SHARE-S6: รายการ "เอกสารทั้งหมด" — ไอคอนแทนอิโมจิ + รูปตัวอย่างจริงของไฟล์รูป (PDF แสดงไอคอน PDF)
#   รูปตัวอย่างโหลดตอนเปิดหน้าแรงงาน (employer-share-view S6: { t|c, worker_id })
import sys
MARK = 'Stage SHARE-S6'
CSS = """/* Stage SHARE-S6 */
.files .ic{width:44px;height:54px;border-radius:8px;border:1px solid var(--line);background:#faf7f2;display:grid;place-items:center;overflow:hidden;flex:none;font-size:0}
.files .ic img{width:100%;height:100%;object-fit:cover;display:block}
.files .ic svg{width:28px;height:28px}
"""
ICONS = r"""// Stage SHARE-S6: ไอคอนไฟล์ + รูปตัวอย่างเอกสาร
const ICON_PDF='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 2h8l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z" fill="#fff" stroke="#d64545" stroke-width="1.5"/><path d="M14 2v5h5" fill="none" stroke="#d64545" stroke-width="1.5"/><rect x="3" y="12" width="14" height="7" rx="1.5" fill="#d64545"/><text x="10" y="17.6" font-size="5.4" font-weight="700" fill="#fff" text-anchor="middle" font-family="Arial,sans-serif">PDF</text></svg>';
const ICON_IMG='<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="#d9730d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5" fill="#fff4e8"/><circle cx="9" cy="9.5" r="1.8"/><path d="M21 16l-5-5-8 8"/></svg>';
const THUMBS={};
async function loadThumbs(w){
  if(!(w.files||[]).some(f=>!f.pdf)) return;
  let c=THUMBS[w.id];
  if(!c||Date.now()-c.t>10*60e3){
    try{ const d=await api({...AUTH, worker_id:Number(w.id)}); if(!d||!d.ok) return; c=THUMBS[w.id]={t:Date.now(),m:d.thumbs||{}}; }catch(_){ return; }
  }
  document.querySelectorAll('.files .ic[data-fid]').forEach(el=>{
    const u=c.m[el.dataset.fid]; if(!u||!/^https:\/\//.test(u)) return;
    const im=new Image(); im.alt=''; im.decoding='async'; im.onload=()=>{ el.innerHTML=''; el.appendChild(im); }; im.src=u;
  });
}
"""
def rep(s, o, n, path):
    if s.count(o) != 1: sys.exit(path + ': anchor ' + o[:60])
    return s.replace(o, n)
def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARK in s: print(path, ': already patched — skip'); return
    s = rep(s, '</style>', CSS + '</style>', path)
    s = rep(s, """<span class="ic">${f.pdf?'📄':'🖼️'}</span>""", """<span class="ic" data-fid="${Number(f.id)}">${f.pdf?ICON_PDF:ICON_IMG}</span>""", path)
    s = rep(s, "function openFile(el){", ICONS + "function openFile(el){", path)
    s = rep(s, "  history.pushState({v:'w'},'');\n}\n", "  history.pushState({v:'w'},'');\n  loadThumbs(w);\n}\n", path)
    open(path, 'w', encoding='utf-8').write(s); print(path, ': patched')
for p in sys.argv[1:]: patch(p)

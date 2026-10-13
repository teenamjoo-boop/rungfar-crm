# Stage SHARE-S5: ปุ่ม "กลับไปรายชื่อ" เป็นแถบขาว · ปัดจอไปทางขวาเพื่อกลับไปรายชื่อ (มือถือ)
import sys
MARK = 'Stage SHARE-S5'
CSS = """/* Stage SHARE-S5 */
.back{background:rgba(255,255,255,.95);color:var(--brand-d);font-weight:600;padding:7px 15px 7px 11px;border-radius:99px;box-shadow:0 2px 8px rgba(0,0,0,.14);width:max-content}
.back:active{transform:scale(.97)}
"""
JS = """// Stage SHARE-S5: ปัดขวาเพื่อกลับไปรายชื่อ
(function(){
  const dt=document.getElementById('dt'); if(!dt) return;
  let x0=null,y0=0,dx=0,drag=false;
  dt.addEventListener('touchstart',e=>{ if(!dt.classList.contains('open')||e.touches.length!==1) return; x0=e.touches[0].clientX; y0=e.touches[0].clientY; dx=0; drag=false; },{passive:true});
  dt.addEventListener('touchmove',e=>{
    if(x0===null) return; const t=e.touches[0], mx=t.clientX-x0, my=t.clientY-y0;
    if(!drag){ if(mx>12 && Math.abs(mx)>Math.abs(my)*1.3){ drag=true; dt.style.transition='none'; } else if(Math.abs(my)>12 || mx<-12){ x0=null; return; } else return; }
    dx=Math.max(0,mx); dt.style.transform='translateX('+dx+'px)';
  },{passive:true});
  const end=()=>{
    if(x0===null) return; x0=null; if(!drag) return; drag=false; dt.style.transition='';
    if(dx>Math.min(110,dt.offsetWidth*0.28)){ dt.style.transform='translateX(100%)'; history.back(); setTimeout(()=>{dt.style.transform='';},320); }
    else dt.style.transform='';
  };
  dt.addEventListener('touchend',end); dt.addEventListener('touchcancel',end);
})();
"""
def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARK in s: print(path, ': already patched — skip'); return
    if s.count('</style>') != 1 or s.count('\nload();\n') != 1: sys.exit(path + ': anchor')
    s = s.replace('</style>', CSS + '</style>').replace('\nload();\n', '\n' + JS + 'load();\n')
    open(path, 'w', encoding='utf-8').write(s); print(path, ': patched')
for p in sys.argv[1:]: patch(p)

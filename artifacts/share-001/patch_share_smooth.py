# Stage SHARE-SMOOTH: หน้าลิงก์ไม่กระตุก
#  - จำรูปย่อแรงงาน + รูปพื้นหลังไว้ในเครื่อง (ลิงก์รูปจาก Supabase เปลี่ยนทุกครั้ง เบราว์เซอร์จำเองไม่ได้)
#    → เปิดลิงก์ซ้ำ รูปขึ้นพร้อมรายชื่อทันที (เก็บ 3 วัน เหมือนข้อมูล · ลิงก์ถูกยกเลิก = ลบทิ้ง)
#  - รูปที่ต้องโหลดใหม่ค่อย ๆ จางเข้า (ไม่โผล่ทีละรูปแบบกระตุก) · พื้นหลังจางเข้าแทนการเปลี่ยนสีทันที
#  - ข้อมูลใหม่เหมือนข้อมูลที่จำไว้ → ไม่วาดรายชื่อใหม่ (ไม่กระพริบ)
import sys

MARK = 'Stage SHARE-SMOOTH'

CSS = '''/* Stage SHARE-SMOOTH */
.hd{position:relative;overflow:hidden}
.hd>:not(.hdbg){position:relative}
.hdbg{position:absolute;inset:0;background-size:cover;background-position:center;opacity:0;transition:opacity .4s ease;pointer-events:none}
.hdbg::after{content:'';position:absolute;inset:0;background:linear-gradient(180deg,rgba(20,10,0,.10) 0%,rgba(20,10,0,.42) 100%)}
.hdbg.on{opacity:1}
.av img.fade{opacity:0;transition:opacity .3s ease}
.av img.fade.on{opacity:1}
'''

JS = r'''// ── Stage SHARE-SMOOTH: จำรูปย่อไว้ในเครื่อง → เปิดซ้ำรูปขึ้นทันที ไม่กระพริบ ──
const IMG_KEY = AUTH ? 'rf_share_img_v1:'+(AUTH.c||String(AUTH.t).slice(0,16)) : '';
const IMG_MAX = 80;
let IMGC = (()=>{ try{ const c=JSON.parse(localStorage.getItem(IMG_KEY)||'null'); return c&&c.m&&Date.now()-c.at<CACHE_MAX ? c.m : {}; }catch(_){ return {}; } })();
let _imgcT=0;
function imgcSave(){ clearTimeout(_imgcT); _imgcT=setTimeout(()=>{ try{ localStorage.setItem(IMG_KEY, JSON.stringify({at:Date.now(), m:IMGC})); }catch(_){} }, 500); }
function imgcDrop(){ IMGC={}; try{ localStorage.removeItem(IMG_KEY); }catch(_){} }
const thumbOf = u => (u && IMGC[_base(u)]) || null;
// ย่อรูปที่โหลดแล้ว (ต้องโหลดแบบ crossOrigin) เก็บเป็น JPEG เล็ก ๆ — w×h = ครอปเต็มกรอบ, h=0 = คงสัดส่วน
function rememberImg(im, u, w, h, q){
  try{
    const k=_base(u); if(!k||IMGC[k]||!im.naturalWidth) return;
    if(h && Object.keys(IMGC).length>=IMG_MAX) return;
    const iw=im.naturalWidth, ih=im.naturalHeight;
    const c=document.createElement('canvas');
    if(h){
      c.width=w; c.height=h;
      const s=Math.max(w/iw, h/ih), sw=w/s, sh=h/s;
      c.getContext('2d').drawImage(im, (iw-sw)/2, (ih-sh)/2, sw, sh, 0, 0, w, h);
    } else {
      const s=Math.min(1, w/iw); c.width=Math.round(iw*s); c.height=Math.round(ih*s);
      c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
    }
    IMGC[k]=c.toDataURL('image/jpeg', q); imgcSave();
  }catch(_){ /* รูปไม่อนุญาต CORS — ข้าม */ }
}
function avLoaded(im){ im.classList.add('on'); if(im.crossOrigin) rememberImg(im, im.src, 120, 144, 0.8); }
function avErr(im){ if(im.crossOrigin){ const s=im.src; im.removeAttribute('crossorigin'); im.src=s; } else im.remove(); }
// พื้นหลังแถบบน: จางเข้า · มีรูปที่จำไว้ = ใช้เลย ไม่โหลดใหม่
function setBanner(bn, fresh){
  const hd=document.querySelector('.hd'); if(!hd) return;
  let L=hd.querySelector('.hdbg'); if(!L){ L=document.createElement('div'); L.className='hdbg'; hd.insertBefore(L, hd.firstChild); }
  const ok = bn && /^https:\/\//.test(bn);
  const k = ok ? _base(bn) : '';
  if(!k){ hd.dataset.bk=''; L.classList.remove('on'); hd.classList.remove('has-bg'); return; }
  const css = s => `url("${String(s).replace(/["\\\n\r]/g,'')}")`;
  const show = s => { L.style.backgroundImage=css(s); hd.classList.add('has-bg'); requestAnimationFrame(()=>L.classList.add('on')); };
  if(hd.dataset.bk===k) return;
  hd.dataset.bk=k;
  const th = IMGC[k];
  if(th){ show(th); return; }              // รูปที่จำไว้ (กว้าง 1100px) — ไม่ต้องโหลดใหม่
  if(!fresh) return;
  // โหลดครั้งเดียวแบบ CORS → ย่อเก็บ → แสดงรูปที่ย่อ (ไม่โหลดซ้ำ 2 รอบ)
  const im=new Image(); im.crossOrigin='anonymous'; im.decoding='async';
  im.onload=()=>{ if(hd.dataset.bk!==k) return; rememberImg(im, bn, 1100, 0, 0.72); show(IMGC[k]||bn); };
  im.onerror=()=>{ if(hd.dataset.bk!==k) return; show(bn); };   // ไม่อนุญาต CORS → แสดงตรง ๆ
  im.src=bn;
}
// ลายเซ็นข้อมูล (ไม่นับเวลาที่ดึง และ token ของลิงก์รูป) — เหมือนเดิม = ไม่ต้องวาดใหม่
const dataSig = d => JSON.stringify(d, (k,v)=> k==='generated_at' ? undefined : (typeof v==='string' && /^https:\/\//.test(v) ? _base(v) : v));
let DATA_SIG='';
function updFoot(){ if(DATA) document.getElementById('upd').textContent=`ข้อมูล ณ ${new Date(DATA.generated_at).toLocaleString('th-TH',{dateStyle:'medium',timeStyle:'short'})} · บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด`; }
'''

# applyData: ข้อมูลเก่า → เก็บลิงก์รูปที่มีรูปย่อไว้ (ใช้รูปย่อแสดง)
OLD_STRIP = """  if(Date.now()-at > URL_TTL){
    d.workers.forEach(w=>{ if(w.photo&&/^https:/.test(w.photo)) w.photo=null; });
    if(d.employer) d.employer.banner=null;
  }"""
NEW_STRIP = """  const fresh = Date.now()-at <= URL_TTL;   // Stage SHARE-SMOOTH
  if(!fresh){
    d.workers.forEach(w=>{ if(w.photo&&/^https:/.test(w.photo)&&!thumbOf(w.photo)) w.photo=null; });
    if(d.employer&&d.employer.banner&&!IMGC[_base(d.employer.banner)]) d.employer.banner=null;
  }"""

NEW_BG = """  setBanner(d.employer&&d.employer.banner, fresh);   // Stage SHARE-SMOOTH: จางเข้า + รูปที่จำไว้"""

OLD_TAIL = """  document.getElementById('stats').hidden=false;
  document.getElementById('searchBox').hidden=DATA.workers.length<6;
  render();
}"""
NEW_TAIL = """  document.getElementById('stats').hidden=false;
  document.getElementById('searchBox').hidden=DATA.workers.length<6;
  const sig=dataSig(d);
  if(sig===DATA_SIG && document.querySelector('#list .w')){ updFoot(); return; }   // ข้อมูลเหมือนเดิม — ไม่วาดใหม่
  DATA_SIG=sig;
  render();
}"""

OLD_AV = """  const img = w.photo ? `<img src="${esc(w.photo)}" alt=""${eager?'':' loading="lazy"'} onerror="this.remove()">` : '';"""
NEW_AV = """  const th = thumbOf(w.photo);   // Stage SHARE-SMOOTH: มีรูปย่อในเครื่อง = ขึ้นทันที
  const img = !w.photo ? '' : th
    ? `<img src="${th}" alt="">`
    : `<img class="fade" src="${esc(w.photo)}" alt="" crossorigin="anonymous"${eager?'':' loading="lazy"'} onload="avLoaded(this)" onerror="avErr(this)">`;"""

OLD_INVALID = "const hd=document.querySelector('.hd'); if(hd){ hd.classList.remove('has-bg'); hd.style.backgroundImage=''; hd.dataset.bg=''; }"
NEW_INVALID = "setBanner(null, true); imgcDrop(); DATA_SIG='';"


def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:90]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHARE-FAST' not in s or 'Stage SHARE-PDF' not in s:
        sys.exit(path + ': ต้องมี SHARE-FAST และ SHARE-PDF ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    s = rep(s, '</style>', CSS + '</style>', path)
    s = rep(s, OLD_STRIP, NEW_STRIP, path)
    a = "  const hd=document.querySelector('.hd');\n  if(hd){\n    const bn=d.employer&&d.employer.banner;\n"
    b = "  // ใช้ค่าแจ้งเตือนล่วงหน้าจาก CRM (ตั้งค่าแจ้งเตือน) ถ้ามี\n"
    if s.count(a) != 1: sys.exit(path + ': banner block not found')
    i = s.index(a); j = s.index(b, i)
    if 'hd.dataset.bg=css' not in s[i:j] or j - i > 600: sys.exit(path + ': banner block unexpected')
    s = s[:i] + NEW_BG + '\n' + s[j:]
    s = rep(s, OLD_TAIL, NEW_TAIL, path)
    s = rep(s, OLD_AV, NEW_AV, path)
    s = rep(s, OLD_INVALID, NEW_INVALID, path)
    s = rep(s, 'async function load(){', JS + 'async function load(){', path)
    open(path, 'wb').write(s.replace('\n', nl).encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

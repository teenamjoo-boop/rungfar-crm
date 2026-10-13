# Stage SHARE-FAST: หน้าลิงก์นายจ้าง/กลุ่ม โหลดเร็วขึ้น
#  - เริ่มขอข้อมูลตั้งแต่ <head> (ไม่รอ HTML/ฟอนต์โหลดเสร็จ) + preconnect ไป Supabase
#  - ส่งแบบ text/plain → ไม่มี CORS preflight (ลดไป 1 รอบ) — ฟังก์ชันอ่าน body ด้วย req.json() เหมือนเดิม
#  - เปิดลิงก์ซ้ำ: แสดงข้อมูลที่จำไว้ในเครื่องทันที แล้วอัปเดตเป็นข้อมูลล่าสุดเมื่อโหลดเสร็จ (เก็บ 3 วัน, ลิงก์ถูกยกเลิก = ลบทิ้ง)
#  - รูปแรงงาน 12 คนแรกโหลดทันที (ไม่ lazy) · แตะชื่อแรงงาน = เริ่มโหลดรูปตัวอย่างเอกสารก่อนหน้ารายละเอียดเปิด
import re
import sys

MARK = 'Stage SHARE-FAST'

HEAD = r'''<script>/* Stage SHARE-FAST: เริ่มขอข้อมูลทันทีที่เปิดหน้า */
(function(){try{
  var FN='__FN__';
  var q=new URLSearchParams(location.search),h=new URLSearchParams(location.hash.slice(1));
  var t=(q.get('t')||h.get('t')||'').trim().toLowerCase();
  var m=location.pathname.match(/\/s\/([0-9A-Za-z]{6,16})\/?$/);
  var c=String(q.get('c')||h.get('c')||(m?m[1]:'')).trim();
  var b=/^[0-9a-f]{64}$/.test(t)?{t:t}:(/^[0-9A-Za-z]{6,16}$/.test(c)?{c:c}:null);
  if(!b)return;
  window.__RF_EARLY={k:JSON.stringify(b),p:fetch(FN,{method:'POST',headers:{'Content-Type':'text/plain;charset=UTF-8'},body:JSON.stringify(b)})
    .then(function(r){return r.json();}).catch(function(){return null;})};
}catch(e){}})();
</script>
'''

LOAD_NEW = r'''// Stage SHARE-FAST: จำข้อมูลล่าสุดไว้ในเครื่อง → เปิดลิงก์ซ้ำแสดงได้ทันที
const CACHE_KEY = AUTH ? 'rf_share_v1:'+(AUTH.c||String(AUTH.t).slice(0,16)) : '';
const CACHE_MAX = 3*864e5, URL_TTL = 12*60e3;   // ลิงก์รูปชั่วคราวอายุ 15 นาที → ใช้ซ้ำได้ไม่เกิน 12 นาที
const _base = u => String(u||'').split('?')[0];
function cacheRead(){ try{ const c=JSON.parse(localStorage.getItem(CACHE_KEY)||'null'); return c&&c.d&&c.d.ok&&Date.now()-c.at<CACHE_MAX?c:null; }catch(_){ return null; } }
function cacheWrite(d){ try{ localStorage.setItem(CACHE_KEY, JSON.stringify({at:Date.now(), d})); }catch(_){} }
function cacheDrop(){ try{ localStorage.removeItem(CACHE_KEY); }catch(_){} }
let DATA_AT = 0;   // เวลาที่ได้ลิงก์รูปชุดที่แสดงอยู่ (ใช้ซ้ำเพื่อไม่ให้รูปกระพริบ/โหลดใหม่)

function applyData(d, at){
  // ข้อมูลเก่าในเครื่อง: ตัดลิงก์รูปที่หมดอายุแล้วทิ้ง (แสดงตัวอักษรย่อแทนจนกว่าข้อมูลใหม่มา)
  if(Date.now()-at > URL_TTL){
    d.workers.forEach(w=>{ if(w.photo&&/^https:/.test(w.photo)) w.photo=null; });
    if(d.employer) d.employer.banner=null;
  }
  // ข้อมูลใหม่มาแทนข้อมูลในเครื่อง: รูปไฟล์เดิมที่ลิงก์ยังไม่หมดอายุ → ใช้ลิงก์เดิม (ไม่โหลดซ้ำ ไม่กระพริบ)
  if(DATA && at>DATA_AT && Date.now()-DATA_AT < URL_TTL){
    const prev=new Map(DATA.workers.map(w=>[Number(w.id), w.photo]));
    d.workers.forEach(w=>{ const p=prev.get(Number(w.id)); if(p&&w.photo&&_base(p)===_base(w.photo)) w.photo=p; });
    const pb=DATA.employer&&DATA.employer.banner;
    if(pb&&d.employer&&d.employer.banner&&_base(pb)===_base(d.employer.banner)) d.employer.banner=pb;
    at=DATA_AT;
  }
  DATA=d; DATA_AT=at;
  // Stage SHARE-S3: พื้นหลังแถบบนของนายจ้าง/กลุ่ม (ถ้าตั้งไว้ใน CRM)
  const hd=document.querySelector('.hd');
  if(hd){
    const bn=d.employer&&d.employer.banner;
    const css=bn&&/^https:\/\//.test(bn)?`linear-gradient(180deg,rgba(20,10,0,.10) 0%,rgba(20,10,0,.42) 100%),url("${String(bn).replace(/["\\\n\r]/g,'')}")`:'';
    if((hd.dataset.bg||'')!==css){ hd.classList.toggle('has-bg',!!css); hd.style.backgroundImage=css; hd.dataset.bg=css; }
  }
  // ใช้ค่าแจ้งเตือนล่วงหน้าจาก CRM (ตั้งค่าแจ้งเตือน) ถ้ามี
  if(d.alerts){ const key={passport:'passport',visa:'visa',wp:'wp',d90:'next90',mou:'mou'}; DOCS.forEach(doc=>{ const v=Number(d.alerts[key[doc.k]]); if(v>0) doc.warn=v; }); }
  document.getElementById('stats').hidden=false;
  document.getElementById('searchBox').hidden=DATA.workers.length<6;
  render();
}

async function load(){
  if(!AUTH){ showMessage('ลิงก์ไม่ถูกต้อง','กรุณาเปิดจากลิงก์ที่บริษัทส่งให้ทาง LINE หรือติดต่อบริษัท'); return; }
  const cached=cacheRead();
  if(cached){ try{ applyData(cached.d, cached.at); }catch(_){ DATA=null; } }
  let d=null;
  const E=window.__RF_EARLY;
  if(E && E.k===JSON.stringify(AUTH)){ try{ d=await E.p; }catch(_){ d=null; } }
  if(!d){ try{ d = await api({...AUTH}); }catch(_){ d={ok:false,error:'network'}; } }
  if(!d.ok){
    if(d.error==='invalid'){ cacheDrop(); DATA=null; document.getElementById('stats').hidden=true; document.getElementById('searchBox').hidden=true; document.getElementById('upd').textContent=''; const hd=document.querySelector('.hd'); if(hd){ hd.classList.remove('has-bg'); hd.style.backgroundImage=''; hd.dataset.bg=''; } document.title='ข้อมูลแรงงาน · รุ่งฟ้า'; showMessage('ลิงก์นี้ใช้ไม่ได้แล้ว','ลิงก์อาจถูกยกเลิกหรือเปลี่ยนใหม่ กรุณาติดต่อบริษัทเพื่อขอลิงก์ล่าสุด'); }
    else if(DATA) toast('อัปเดตข้อมูลล่าสุดไม่สำเร็จ — แสดงข้อมูลที่บันทึกไว้');
    else showMessage('โหลดข้อมูลไม่สำเร็จ','กรุณาลองใหม่อีกครั้งในอีกสักครู่');
    return;
  }
  cacheWrite(JSON.parse(JSON.stringify(d)));
  applyData(d, Date.now());
}
'''

THUMBS_NEW = r'''const THUMBP={};   // Stage SHARE-FAST: เก็บ promise → แตะชื่อแล้วเริ่มโหลดได้ก่อนหน้ารายละเอียดเปิด
function thumbsFor(w){
  const c=THUMBP[w.id]; if(c&&Date.now()-c.t<10*60e3) return c.p;
  const p=api({...AUTH, worker_id:Number(w.id)}).then(d=>d&&d.ok?(d.thumbs||{}):null).catch(()=>null);
  THUMBP[w.id]={t:Date.now(),p}; p.then(m=>{ if(!m&&THUMBP[w.id]&&THUMBP[w.id].p===p) delete THUMBP[w.id]; });
  return p;
}
function preThumbs(id){ const w=DATA&&DATA.workers.find(x=>Number(x.id)===id); if(w&&(w.files||[]).some(f=>!f.pdf)) thumbsFor(w); }
async function loadThumbs(w){
  if(!(w.files||[]).some(f=>!f.pdf)) return;
  const m=await thumbsFor(w); if(!m) return;
  document.querySelectorAll('.files .ic[data-fid]').forEach(el=>{
    const u=m[el.dataset.fid]; if(!u||!/^https:\/\//.test(u)) return;
    const im=new Image(); im.alt=''; im.decoding='async'; im.onload=()=>{ el.innerHTML=''; el.appendChild(im); }; im.src=u;
  });
}
'''


def rep(s, old, new, path, cnt=1):
    n = s.count(old)
    if n != cnt:
        sys.exit(f'{path}: anchor count {n} != {cnt} for: {old[:90]}')
    return s.replace(old, new)


def cut(s, start, end, new, path):
    if s.count(start) != 1 or s.count(end) < 1:
        sys.exit(f'{path}: cut anchors not unique: {start[:60]}')
    i = s.index(start)
    j = s.index(end, i)
    return s[:i] + new + s[j:]


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHARE-GROUP' not in s or 'Stage SHARE-S6' not in s:
        sys.exit(path + ': ต้องมี SHARE-S6 และ SHARE-GROUP ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    fn = re.search(r"const FN_URL = '(https://[a-z0-9]+\.supabase\.co/functions/v1/employer-share-view)';", s)
    if not fn:
        sys.exit(path + ': หา FN_URL ไม่เจอ')
    origin = fn.group(1).split('/functions/')[0]
    # 1) <head>: preconnect + เริ่มขอข้อมูลทันที (ก่อน stylesheet ฟอนต์ เพื่อไม่ให้ script ถูกบล็อก)
    s = rep(s, '<meta name="referrer" content="no-referrer">\n',
            '<meta name="referrer" content="no-referrer">\n'
            f'<link rel="preconnect" href="{origin}" crossorigin>\n' + HEAD.replace('__FN__', fn.group(1)), path)
    # 2) ส่งแบบ text/plain (ไม่มี preflight)
    s = rep(s, "const res = await fetch(FN_URL,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});",
            "const res = await fetch(FN_URL,{method:'POST',headers:{'Content-Type':'text/plain;charset=UTF-8'},body:JSON.stringify(body)});   // Stage SHARE-FAST: ไม่มี preflight", path)
    # 3) load(): ใช้คำขอที่เริ่มไว้ใน <head> + แคชในเครื่อง
    s = cut(s, 'async function load(){', 'function render(){', LOAD_NEW + '\n', path)
    # 4) รูปแรงงาน 12 คนแรกไม่ lazy · แตะชื่อ = เริ่มโหลดรูปตัวอย่างเอกสาร
    s = rep(s, "function avatar(w, extra=''){", "function avatar(w, extra='', eager=false){", path)
    s = rep(s, '`<img src="${esc(w.photo)}" alt="" loading="lazy" onerror="this.remove()">`',
            '`<img src="${esc(w.photo)}" alt=""${eager?\'\':\' loading="lazy"\'} onerror="this.remove()">`', path)
    s = rep(s, "+rows.map(({w,x})=>`\n    <button class=\"w\" onclick=\"openW(${Number(w.id)})\">\n      ${avatar(w)}",
            "+rows.map(({w,x},i)=>`\n    <button class=\"w\" onclick=\"openW(${Number(w.id)})\" onpointerdown=\"preThumbs(${Number(w.id)})\">\n      ${avatar(w,'',i<12)}", path)
    s = rep(s, "${avatar(w, w.photo?`onclick=\"openPhoto(${Number(w.id)})\"`:'')}",
            "${avatar(w, w.photo?`onclick=\"openPhoto(${Number(w.id)})\"`:'', true)}", path)
    s = cut(s, 'const THUMBS={};', 'function openFile(el){', THUMBS_NEW, path)
    s = s.replace('// ---------- ตั้งค่า ----------', '// ---------- ตั้งค่า ---------- (' + MARK + ')', 1)
    open(path, 'wb').write(s.replace('\n', nl).encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

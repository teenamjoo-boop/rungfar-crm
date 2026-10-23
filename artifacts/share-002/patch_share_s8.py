# Stage SHARE-S8 — หน้าลิงก์นายจ้าง: แบ่งกลุ่มรายชื่อ + สรุปบนหัว + ช่องทางโซเชียลบริษัท
#   * รายชื่อ (แท็บทั้งหมด) แบ่งเป็น "ต้องดำเนินการ" / "เอกสารปกติ" / "ยังไม่มีวันที่เอกสาร"
#   * บนหัว: "30 วันข้างหน้า มีเอกสารครบกำหนด n ฉบับ · m คน"
#   * แถบล่าง: ปุ่มกลม Facebook · LINE · TikTok + ปุ่มโทร  (TikTok ซ่อนไว้จนกว่าจะใส่ลิงก์ TIKTOK_URL)
import sys,re
TIKTOK_URL='https://www.tiktok.com/@rungfarungfaofficial'   # ← ใส่ลิงก์ TikTok บริษัท เช่น https://www.tiktok.com/@xxxx แล้วรันใหม่ (ต้องใช้ไฟล์ก่อนแพตช์)
LINE_URL='https://lin.ee/sRRH3us'
FB_URL='https://www.facebook.com/rungfarungfaofficial/'
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage SHARE-S8' in t: print('already'); sys.exit(0)
assert 'Stage SHARE-FLAGS' in t, 'run patch_share_flags.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("</style>","""/* Stage SHARE-S8 */
.hsum{display:flex;align-items:center;gap:7px;width:fit-content;max-width:100%;margin-top:10px;background:rgba(255,255,255,.16);border-radius:12px;padding:7px 12px;font-size:12.5px;color:#fff;line-height:1.35}
.hsum svg{width:15px;height:15px;flex:none;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.hsum b{font-size:14px}
.sec .scnt{font-weight:500;color:var(--mute);margin-left:4px}
.cta .soc{display:flex;gap:8px;flex:none;pointer-events:none}
.cta a.sb{flex:none;width:46px;height:46px;padding:0;border-radius:50%;display:grid;place-items:center;color:#fff;pointer-events:auto}
.cta a.sb svg{width:22px;height:22px}
.sb-fb{background:#1877f2}.sb-line{background:#06c755}.sb-tt{background:#111}
.cta a.sb[hidden]{display:none}
@media (max-width:420px){.cta a.sb{width:42px;height:42px}.cta .soc{gap:6px}}
</style>""")
# hero summary
rep("""    <div class="thx">ขอบคุณที่ใช้บริการ</div>""","""    <div class="hsum" id="hsum" hidden></div>
    <div class="thx">ขอบคุณที่ใช้บริการ</div>""")
# sections
rep("""  L.innerHTML=empChips()+natChips()+`<div class="sec">${hh(filter==='bad'?'alert':filter==='warn'?'clock':'list',filter==='bad'?'rose':filter==='warn'?'amber':'orange',head)}</div>`+rows.map(({w,x},i)=>`""","""  shareSum(tag);
  const card=({w,x},i)=>`""")
rep("""      <span class="chev">›</span>
    </button>`).join('');
}""","""      <span class="chev">›</span>
    </button>`;
  L.innerHTML=empChips()+natChips()+shareSections(rows,card,head);
}
// Stage SHARE-S8: แบ่งกลุ่มรายชื่อ + สรุปบนหัว
function shareSections(rows,card,head){
  let i=0; const block=(ic,col,txt,arr)=>arr.length?`<div class="sec">${hh(ic,col,txt+' <span class="scnt">'+arr.length+' คน</span>')}</div>`+arr.map(r=>card(r,i++)).join(''):'';
  if(filter!=='all') return block(filter==='bad'?'alert':'clock',filter==='bad'?'rose':'amber',head,rows);
  return block('alert','rose','ต้องดำเนินการ',rows.filter(r=>r.x&&r.x.s.c!=='ok'))
    +block('check','green','เอกสารปกติ',rows.filter(r=>r.x&&r.x.s.c==='ok'))
    +block('calendar','orange','ยังไม่มีวันที่เอกสาร',rows.filter(r=>!r.x));
}
function shareSum(tag){
  const el=document.getElementById('hsum'); if(!el) return;
  let n=0; const ppl=new Set(); let over=0;
  DATA.workers.forEach(w=>DOCS.forEach(doc=>{const d=days(w.dates&&w.dates[doc.k]); if(d===null) return; if(d<0){over++;return;} if(d<=30){n++;ppl.add(w.id);}}));
  const ic='<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>';
  el.innerHTML=ic+'<span>'+(n?`30 วันข้างหน้า ครบกำหนด <b>${n}</b> ฉบับ (${ppl.size} คน)`:'30 วันข้างหน้า ไม่มีเอกสารครบกำหนด')+(over?` · เลยกำหนด <b>${over}</b> ฉบับ`:'')+'</span>';
  el.hidden=false;
}""")
# hh(): ข้อความหัวข้อมี HTML (จำนวนคน) — ตรวจว่า hh ไม่ escape
m=re.search(r'\n  <a class="btn-fb" href="[^"]*" target="_blank" rel="noopener">(<svg.*?</svg>)[^\n]*\n',t); assert m, 'fb'
fb=m.group(1).replace('<svg ','<svg width="22" height="22" ',1)
line_svg='<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3.2c-5.3 0-9.6 3.4-9.6 7.7 0 3.8 3.4 7 8 7.6.3.1.7.2.8.5.1.2.1.6 0 .8l-.1.8c0 .2-.2.9.8.5s5.4-3.2 7.4-5.5c1.4-1.5 2.3-3 2.3-4.7 0-4.3-4.3-7.7-9.6-7.7z"/><path fill="#06c755" d="M6.6 8.6h1v3.6h2v.9h-3zM10.4 8.6h1v4.5h-1zM12.6 8.6h.9l2 2.8V8.6h1v4.5h-.9l-2-2.8v2.8h-1zM17.6 8.6h3v.9h-2v.9h2v.9h-2v.9h2v.9h-3z" transform="translate(-1.1 0) scale(.96)"/></svg>'
tt_svg='<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14.5 3h2.6c.2 1.9 1.6 3.4 3.4 3.6v2.7c-1.3 0-2.5-.4-3.5-1.1v6.4a5.6 5.6 0 1 1-5.6-5.6c.3 0 .6 0 .9.1v2.8a2.9 2.9 0 1 0 2.2 2.8z"/></svg>'
t=t.replace(m.group(0),f'''
  <span class="soc">
    <a class="sb sb-fb" href="{FB_URL}" target="_blank" rel="noopener" aria-label="Facebook รุ่งฟ้า" title="ติดตามข่าวสาร Facebook">{fb}</a>
    <a class="sb sb-line" href="{LINE_URL}" target="_blank" rel="noopener" aria-label="LINE รุ่งฟ้า" title="LINE รุ่งฟ้า">{line_svg}</a>
    <a class="sb sb-tt" href="{TIKTOK_URL or '#'}" target="_blank" rel="noopener" aria-label="TikTok รุ่งฟ้า" title="TikTok รุ่งฟ้า"{'' if TIKTOK_URL else ' hidden'}>{tt_svg}</a>
  </span>
''',1)
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

# Stage SHARE-S9 — การ์ดรายชื่อแรงงานกระชับ สูงเท่ากันทุกคน
#   * ชื่อบรรทัดเดียว (ยาวเกิน = …) · ตัดคำว่าสัญชาติออก (มีธงแล้ว) — ยังแสดงชื่ออังกฤษ/นายจ้างถ้ามี
#   * สถานะงาน (เช่น ทำพาสปอร์ต•MOU) ย้ายมาอยู่แถวเดียวกับป้ายเอกสาร บรรทัดเดียว
#   * แถบเอกสาร 4 ช่อง บรรทัดเดียวเสมอ (คนที่ไม่มีวันที่ก็แสดงเป็นสีเทา)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage SHARE-S9' in t: print('already'); sys.exit(0)
assert 'Stage SHARE-S8' in t, 'run patch_share_s8.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("</style>","""/* Stage SHARE-S9: การ์ดกระชับ */
.w{padding:10px 12px;gap:11px;margin-bottom:7px}
.w .av{width:46px;height:54px}
.w .nm{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:14.5px}
.w .en{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.35}
.w .r2{display:flex;align-items:center;gap:6px;margin-top:4px;min-width:0}
.w .r2 .pill{margin-top:0;flex:none;max-width:100%;overflow:hidden;text-overflow:ellipsis;font-size:11.5px;padding:2px 8px}
.w .r2 .wst{flex:0 1 auto;min-width:0;max-width:none;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;-webkit-line-clamp:unset;font-size:10.5px;line-height:1.5;padding:1px 8px;border-radius:99px}
.w .dstrip{flex-wrap:nowrap;overflow:hidden;margin-top:5px}
#list .w{padding:11px 13px}
@media (min-width:700px){.w .r2 .wst{font-size:11px;padding:1px 9px}}
</style>""")
rep("""        <div class="en">${w.name_th&&w.name_en?esc(w.name_en)+' · ':''}${esc(w.nationality||'')}${DATA.employer.group&&w.employer?' · '+esc(w.employer):''}</div>
        ${x?`<span class="pill p-${x.s.c}">${svg(x.s.c==='ok'?'check':x.s.c==='bad'?'alert':'clock')}${x.s.c==='ok'?'เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:`<span class="pill p-na">${svg('calendar')}ยังไม่มีวันที่เอกสาร</span>`}
        ${x?docStrip(w):''}
      </div>
      ${w.status?`<span class="wst">${esc(w.status)}</span>`:''}
      <span class="chev">›</span>""","""        ${(()=>{const en=[w.name_th&&w.name_en?w.name_en:'',natKey(w.nationality)?'':(w.nationality||''),DATA.employer.group&&w.employer?w.employer:''].filter(Boolean).join(' · ');return en?`<div class="en">${esc(en)}</div>`:'';})()}
        <div class="r2">${x?`<span class="pill p-${x.s.c}">${svg(x.s.c==='ok'?'check':x.s.c==='bad'?'alert':'clock')}${x.s.c==='ok'?'เอกสารปกติ':esc(x.doc.short)+' · '+x.s.t}</span>`:`<span class="pill p-na">${svg('calendar')}ยังไม่มีวันที่</span>`}${w.status?`<span class="wst" title="${esc(w.status)}">${esc(w.status)}</span>`:''}</div>
        ${docStrip(w)}
      </div>
      <span class="chev">›</span>""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

import sys
P=sys.argv[1]; s=open(P,encoding='utf-8').read()
def rep(a,b,n=1):
    global s
    assert s.count(a)==n,(P,a[:80],s.count(a)); s=s.replace(a,b)
rep("""    return `<div class="dc ${s.c}">
      <div class="r1"><span class="lb">${chipi(...(DOC_IC[doc.k]||['mou','amber']))}<span>${esc(doc.l)}</span></span><span class="pill p-${s.c}">${s.t}</span></div>
      <div class="r2"><span class="dd">${w.dates[doc.k]?fdt(w.dates[doc.k]):'—'}</span>${docId?`<button class="view" onclick="openDoc(this,${Number(docId)},'${esc(doc.short)}')">ดูเอกสาร</button>`:(doc.doc?'<span class="nofile">ยังไม่มีไฟล์</span>':'')}</div>
      <div class="bar"><i style="width:${s.c==='bad'?100:pct}%"></i></div>
    </div>`;}).join('');""",
"""    // Stage SHARE-LOOK2: การ์ดสี่เหลี่ยม 2 คอลัมน์ (แบบเว็บขนส่ง)
    return `<div class="dq ${s.c}">
      <div class="qh">${chipi(...(DOC_IC[doc.k]||['mou','amber']))}<span>${esc(({d90:'รายงาน 90 วัน'})[doc.k]||doc.short)}</span></div>
      <b class="qd">${w.dates[doc.k]?fdt(w.dates[doc.k]):'—'}</b>
      <span class="pill p-${s.c}">${svg(s.c==='ok'?'check':s.c==='bad'?'alert':s.c==='warn'?'clock':'calendar')}${s.t}</span>
      <div class="bar"><i style="width:${s.c==='bad'?100:pct}%"></i></div>
      ${docId?`<button class="view" onclick="openDoc(this,${Number(docId)},'${esc(doc.short)}')">ดูเอกสาร</button>`:(doc.doc?'<span class="nofile">ยังไม่มีไฟล์</span>':'<span class="nofile ph">&nbsp;</span>')}
    </div>`;}).join('');""")
rep("""<div class="docs">${cards}</div>""","""<div class="docs dq2">${cards}</div>""")
rep("/* Stage SHARE-TWEAK */","""/* Stage SHARE-LOOK2: การ์ดเอกสารสี่เหลี่ยม */
.docs.dq2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:10px 16px;grid-auto-rows:auto}
.dq{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:11px 12px;display:flex;flex-direction:column;align-items:flex-start;min-width:0}
.dq .qh{display:flex;align-items:center;gap:8px;font-size:clamp(13px,3.75vw,15px);font-weight:600;color:var(--ink);width:100%;min-width:0;line-height:1.3}
.dq .qh span{min-width:0;overflow-wrap:anywhere}
.dq .qh .chipi{width:32px;height:32px}
.dq .qh .chipi .ico{width:18px;height:18px}
.dq .qd{font-size:18px;font-weight:600;line-height:1.3;margin-top:8px}
.dq .pill{margin-top:4px}
.dq .bar{width:100%;height:5px;margin-top:9px}
.dq .view{margin-top:9px;width:100%;text-align:center;font-size:12.5px;padding:6px 8px}
.dq .nofile{margin-top:9px;width:100%;text-align:center;font-size:12px;padding:6px 0}
.dq.warn{background:#fffaf1;border-color:#f3dcae} .dq.bad{background:#fff6f6;border-color:#f3c4c4}
.dq.warn .bar i{background:var(--warn)} .dq.bad .bar i{background:var(--bad)} .dq.na .bar i{width:0!important}
@media (min-width:900px){.docs.dq2{grid-template-columns:repeat(3,minmax(0,1fr))}}
/* Stage SHARE-TWEAK */""")
open(P,'w',encoding='utf-8').write(s); print('ok',P)

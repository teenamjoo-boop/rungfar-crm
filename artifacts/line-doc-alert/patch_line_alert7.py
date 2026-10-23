# Stage LINE-DOC-ALERT-CARD6 — ตัวอย่างการ์ดใน CRM: หัวการ์ด 2:1 · กระดิ่งมุมซ้ายบน · ชื่อนายจ้าง Prompt ในกล่องใส · คำแจ้งเตือนมุมล่างขวา · "N รายการ" กลางการ์ด
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD6' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT-CARD5' in t, 'run patch_line_alert6.py first'
i=t.index("  // Stage LINE-DOC-ALERT-CARD5:"); j=t.index("  const cnt=(pi)=>",i); k=t.index("\n",j)
t=t[:i]+r"""  // Stage LINE-DOC-ALERT-CARD6: หัวการ์ด = รูป 1024×512 (ย่อแสดง 260px) ตรงกับที่ส่งเข้า LINE
  const _s=260/1024, px=v=>(v*_s).toFixed(1)+'px';
  const _sv=(path,size,stroke)=>`<svg width="${px(size)}" height="${px(size)}" viewBox="0 0 24 24" fill="none" stroke="${stroke}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
  const head=(pi)=>`<div class="laHero" style="position:relative;aspect-ratio:2/1;background:linear-gradient(135deg,#F26B1D,#F7A44A) center/cover no-repeat;font-family:Prompt,var(--font),sans-serif;overflow:hidden">
    <div class="laShade" style="position:absolute;inset:0;background:radial-gradient(circle at 92% 8%,rgba(255,255,255,.1) 0 37%,transparent 37%)"></div>
    <div style="position:absolute;left:${px(36)};top:${px(36)};width:${px(116)};height:${px(116)};box-sizing:border-box;border-radius:${px(32)};background:#FFF0E3;border:${px(3)} solid #FFD9BF;display:grid;place-items:center">${_sv(IC.bell[1],68,'#E0620B')}</div>
    <div style="position:absolute;left:${px(36)};bottom:${px(74)};max-width:calc(100% - ${px(72)});box-sizing:border-box;padding:${px(14)} ${px(28)};border-radius:${px(26)};background:rgba(255,255,255,.16);border:${px(2.5)} solid rgba(255,255,255,.5);color:#fff;font-weight:600;font-size:${px(c.target&&c.target.length>28?52:58)};line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">${esc(c.target||'-')}</div>
    <div style="position:absolute;right:${px(36)};bottom:${px(20)};color:#fff;opacity:.95;font-size:${px(36)}">แจ้งเตือนเอกสารใกล้หมดอายุ</div>
  </div>`;
  const cnt=(pi)=>`<div style="text-align:center;font-size:13.5px;font-weight:700;color:#F26B1D;margin-bottom:8px">${Number(c.count)||0} รายการ${pages.length>1?' · หน้า '+(pi+1)+'/'+pages.length:''}</div>`;"""+t[k:]
a="""${pg.map((w,wi)=>`<div style="${wi?'border-top:1px solid #f0f0f0;margin-top:9px;padding-top:9px':''}">"""
assert t.count(a)==1
t=t.replace(a,"""${pg.map((w,wi)=>`<div style="border-top:1px solid #f0f0f0;${wi?'margin-top:9px;':''}padding-top:9px">""")
a="if(sh)sh.style.background='linear-gradient(180deg,rgba(0,0,0,.18),rgba(0,0,0,.10) 45%,rgba(0,0,0,.62))';"
assert t.count(a)==1
t=t.replace(a,"if(sh)sh.style.background='linear-gradient(180deg,rgba(0,0,0,.10),rgba(0,0,0,.08) 50%,rgba(0,0,0,.55))';")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

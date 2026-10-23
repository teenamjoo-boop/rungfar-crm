# Stage LINE-DOC-ALERT-CARD5 — ตัวอย่างการ์ดใน CRM: หัวการ์ดแบบรูป (ฟอนต์ Prompt + กรอบใส แบบหน้าลิงก์นายจ้าง) ตรงกับที่ส่งเข้า LINE
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD5' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT-CARD4' in t, 'run patch_line_alert5.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
i=t.index("  const head=(pi)=>`<div class=\"laHero\""); j=t.index("\n",i)
t=t[:i]+r"""  // Stage LINE-DOC-ALERT-CARD5: หัวการ์ด = รูป 1024×720 (ย่อแสดง 260px) — ชื่อ Prompt + การ์ดตัวเลขกรอบใส + กระดิ่งมุมซ้ายบน + คำแจ้งเตือนมุมล่างขวา
  const _s=260/1024, px=v=>(v*_s).toFixed(1)+'px';
  let _minD=9999;ws.forEach(w=>(w.docs||[]).forEach(d=>{_minD=Math.min(_minD,Number(d.days)||0);}));if(_minD===9999)_minD=0;
  const _stats=[{solid:1,icon:'<circle cx="9" cy="8.5" r="3"/><path d="M3.5 19a5.5 5.5 0 0 1 11 0"/><circle cx="17" cy="9.5" r="2.4"/><path d="M15.5 14.2A4.5 4.5 0 0 1 21 18.5"/>',num:String(ws.length),label:'แรงงานต้องต่อ'},
    {solid:0,icon:'<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14 3.5v4h4M9 12h6M9 15.5h4"/>',num:String(Number(c.count)||0),label:'เอกสารใกล้หมด'},
    {solid:0,icon:'<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',num:_minD<=0?'วันนี้':_minD+' วัน',label:'เหลือน้อยสุด'}];
  const _sv=(path,size,stroke)=>`<svg width="${px(size)}" height="${px(size)}" viewBox="0 0 24 24" fill="none" stroke="${stroke}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
  const head=(pi)=>`<div class="laHero" style="position:relative;aspect-ratio:1024/720;background:linear-gradient(135deg,#F26B1D,#F7A44A) center/cover no-repeat;font-family:Prompt,var(--font),sans-serif;overflow:hidden">
    <div class="laShade" style="position:absolute;inset:0;background:radial-gradient(circle at 92% 8%,rgba(255,255,255,.1) 0 36%,transparent 36%)"></div>
    <div style="position:absolute;left:${px(40)};top:${px(40)};width:${px(104)};height:${px(104)};box-sizing:border-box;border-radius:${px(30)};background:#FFF0E3;border:${px(3)} solid #FFD9BF;display:grid;place-items:center">${_sv(IC.bell[1],60,'#E0620B')}</div>
    <div style="position:absolute;left:${px(40)};right:${px(40)};bottom:${px(92+196+34-14)};color:#fff;font-weight:600;font-size:${px(c.target&&c.target.length>34?50:62)};line-height:1.28;text-shadow:0 ${px(3)} ${px(6)} rgba(0,0,0,.28);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">${esc(c.target||'-')}</div>
    <div style="position:absolute;left:${px(40)};right:${px(40)};bottom:${px(92)};height:${px(196)};display:grid;grid-template-columns:repeat(3,1fr);gap:${px(22)}">${_stats.map(x=>`<div style="box-sizing:border-box;border-radius:${px(30)};padding:${px(22)} ${px(24)};${x.solid?'background:rgba(255,255,255,.97)':'background:rgba(255,255,255,.16);border:'+px(2.5)+' solid rgba(255,255,255,.55)'};display:flex;flex-direction:column;justify-content:flex-end;position:relative">
      <div style="position:absolute;left:${px(24)};top:${px(22)};${x.solid?'width:'+px(56)+';height:'+px(56)+';border-radius:'+px(16)+';background:#FFF0E3;display:grid;place-items:center':''}">${_sv(x.icon,x.solid?32:40,x.solid?'#E0620B':'#fff')}</div>
      <div style="font-weight:600;font-size:${px(x.num.length>4?56:68)};line-height:1.05;color:${x.solid?'#E0620B':'#fff'}">${esc(x.num)}</div>
      <div style="font-size:${px(32)};line-height:1.25;color:${x.solid?'#3F3A36':'#fff'};white-space:nowrap">${x.label}</div></div>`).join('')}</div>
    <div style="position:absolute;right:${px(40)};bottom:${px(30)};color:#fff;opacity:.92;font-size:${px(32)}">แจ้งเตือนเอกสารใกล้หมดอายุ</div>
  </div>`;"""+t[j:]
i=t.index("  const cnt=(pi)=>"); j=t.index("\n",i)
t=t[:i]+"  const cnt=(pi)=>pages.length>1?`<div style=\"text-align:right;font-size:10.5px;color:#9a9a9a;margin-bottom:6px\">หน้า ${pi+1}/${pages.length}</div>`:'';"+t[j:]
rep("""      if(d&&d.ok&&d.url)document.querySelectorAll('#lineAlertPvBody .laHero').forEach(h=>{const im=h.querySelector('.laHeroImg'),tx=h.querySelector('.laHeroTxt');
        im.style.display='block';im.style.backgroundImage=`url("${String(d.url).replace(/"/g,'%22')}")`;h.style.background='#000';
        tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 8px;background:linear-gradient(0deg,rgba(0,0,0,.7),rgba(0,0,0,0))';
        const bw=h.querySelector('.laBellW');if(bw)bw.style.display='none';const bb=h.querySelector('.laBell');if(bb)bb.style.display='block';});}catch(_){}""",
"""      if(d&&d.ok&&d.url)document.querySelectorAll('#lineAlertPvBody .laHero').forEach(h=>{
        h.style.backgroundImage=`url("${String(d.url).replace(/"/g,'%22')}")`;
        const sh=h.querySelector('.laShade');if(sh)sh.style.background='linear-gradient(180deg,rgba(0,0,0,.18),rgba(0,0,0,.10) 45%,rgba(0,0,0,.62))';});}catch(_){}""")
# แรงงานคนแรกไม่ต้องมีเส้นคั่นบน
rep("""${pg.map((w,wi)=>`<div style="border-top:1px solid #f0f0f0;${wi?'margin-top:9px;':''}padding-top:9px">""",
    """${pg.map((w,wi)=>`<div style="${wi?'border-top:1px solid #f0f0f0;margin-top:9px;padding-top:9px':''}">""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

# Stage LINE-DOC-ALERT-CARD3 — ตัวอย่างการ์ดใน CRM: กระดิ่งส้มใหญ่มุมซ้ายบน · ชื่อนายจ้างตัวไม่หนา · จำนวนรายการกลางการ์ด · วันที่ชัดขึ้น
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD3' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT-CARD2' in t, 'run patch_line_alert3.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
# ไอคอนกระดิ่งแบบกล่องสี (ส้ม/ขาว)
rep("""  const ico=(k,px)=>{const x=IC[k];if(!x)return'';""","""  // Stage LINE-DOC-ALERT-CARD3
  const bellBox=(px,bg,fg)=>`<span style="display:inline-grid;place-items:center;width:${px}px;height:${px}px;border-radius:${Math.round(px*.27)}px;background:${bg};flex:none"><svg width="${Math.round(px*.65)}" height="${Math.round(px*.65)}" viewBox="0 0 24 24" fill="none" stroke="${fg}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">${IC.bell[1]}</svg></span>`;
  const ico=(k,px)=>{const x=IC[k];if(!x)return'';""")
rep("""return `<span style="background:${bg};color:${fg};font-size:10px;font-weight:700;padding:1px 6px;border-radius:99px;white-space:nowrap">""",
    """return `<span style="background:${bg};color:${fg};font-size:11.5px;font-weight:700;padding:1px 7px;border-radius:99px;white-space:nowrap">""")
i=t.index("  const title=(pi)=>"); j=t.index("  document.getElementById('lineAlertPvBody').innerHTML=!ws.length")
t=t[:i]+"""  const title=()=>`<div style="font-size:10.5px;color:#FFE9DB">แจ้งเตือนเอกสารใกล้หมดอายุ</div><div style="font-size:15px;font-weight:400;color:#fff;line-height:1.35">${esc(c.target||'-')}</div>`;
  const head=(pi)=>`<div class="laHero" style="position:relative;background:linear-gradient(90deg,#F26B1D,#F59E3B)"><div class="laHeroImg" style="display:none;aspect-ratio:2/1;background:#ddd center/cover no-repeat"></div><div class="laBell" style="display:none;position:absolute;top:10px;left:10px">${bellBox(36,'#F26B1D','#fff')}</div><div class="laHeroTxt" style="padding:12px;display:flex;align-items:center;gap:10px"><span class="laBellW">${bellBox(36,'#fff','#F26B1D')}</span><div>${title()}</div></div></div>`;
  const cnt=(pi)=>`<div style="text-align:center;font-size:13.5px;font-weight:700;color:#F26B1D;margin-bottom:8px">${Number(c.count)||0} รายการ${pages.length>1?' · หน้า '+(pi+1)+'/'+pages.length:''}</div>`;
"""+t[j:]
rep("""      <div style="padding:10px 12px">${pg.map((w,wi)=>`<div style="${wi?'border-top:1px solid #f0f0f0;margin-top:9px;padding-top:9px':''}">""",
    """      <div style="padding:10px 12px">${cnt(pi)}${pg.map((w,wi)=>`<div style="border-top:1px solid #f0f0f0;${wi?'margin-top:9px;':''}padding-top:9px">""")
rep("""<span style="font-size:10px;color:#8a8a8a">${esc(d.date||'')}</span>""","""<span style="font-size:11.5px;font-weight:700;color:#222">${esc(d.date||'')}</span>""")
rep("""        tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 10px;background:linear-gradient(0deg,rgba(0,0,0,.7),rgba(0,0,0,0))';});}catch(_){}""",
    """        tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 10px;background:linear-gradient(0deg,rgba(0,0,0,.7),rgba(0,0,0,0))';
        const bw=h.querySelector('.laBellW');if(bw)bw.style.display='none';const bb=h.querySelector('.laBell');if(bb)bb.style.display='block';});}catch(_){}""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

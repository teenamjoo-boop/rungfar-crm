# Stage LINE-DOC-ALERT-CARD4 — ตัวอย่างการ์ดใน CRM: ไอคอนพื้นสีอ่อน+เส้นสี (แบบไอคอนในเว็บ) · กระดิ่งส้มอ่อน · คำว่าแจ้งเตือนมุมล่างขวา
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD4' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT-CARD3' in t, 'run patch_line_alert4.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
i=t.index("  const ico=(k,px)=>{const x=IC[k];if(!x)return'';"); j=t.index("\n",i)
t=t[:i]+"""  // Stage LINE-DOC-ALERT-CARD4: พื้นสีอ่อน + กรอบอ่อน + เส้นสีเข้ม (ตรงกับไอคอนที่ส่งเข้า LINE)
  const LC={bell:['#E0620B','#FFF0E3','#FFD9BF'],passport:['#1D64B0','#E6F0FB','#C9DDF5'],visa:['#6A4A9C','#EFE8F8','#DDD0F1'],wp:['#17804A','#E2F4E9','#BFE3CC'],d90:['#E0620B','#FFF0E3','#FFD9BF'],mou:['#0F7A70','#DCF3EF','#B5E3DB']};
  const ico=(k,px)=>{const x=IC[k],c=LC[k];if(!x||!c)return'';return `<span style="box-sizing:border-box;display:inline-grid;place-items:center;width:${px}px;height:${px}px;border-radius:${Math.round(px*.27)}px;background:${c[1]};border:${px>=30?2:1}px solid ${c[2]};flex:none"><svg width="${Math.round(px*.6)}" height="${Math.round(px*.6)}" viewBox="0 0 24 24" fill="none" stroke="${c[0]}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${x[1]}</svg></span>`;};"""+t[j:]
rep("""  const title=()=>`<div style="font-size:10.5px;color:#FFE9DB">แจ้งเตือนเอกสารใกล้หมดอายุ</div><div style="font-size:15px;font-weight:400;color:#fff;line-height:1.35">${esc(c.target||'-')}</div>`;""",
    """  const title=()=>`<div style="font-size:15px;font-weight:400;color:#fff;line-height:1.35">${esc(c.target||'-')}</div>`;
  const label=`<div style="font-size:10.5px;color:#FFE9DB;text-align:right;margin-top:2px">แจ้งเตือนเอกสารใกล้หมดอายุ</div>`;""")
rep("""<div class="laBell" style="display:none;position:absolute;top:10px;left:10px">${bellBox(36,'#F26B1D','#fff')}</div><div class="laHeroTxt" style="padding:12px;display:flex;align-items:center;gap:10px"><span class="laBellW">${bellBox(36,'#fff','#F26B1D')}</span><div>${title()}</div></div></div>`;""",
    """<div class="laBell" style="display:none;position:absolute;top:10px;left:10px">${ico('bell',36)}</div><div class="laHeroTxt" style="padding:12px 12px 8px"><div style="display:flex;align-items:center;gap:10px"><span class="laBellW">${ico('bell',36)}</span><div>${title()}</div></div>${label}</div></div>`;""")
rep("""tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 10px;""","""tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 8px;""")
rep("${ico(d.kind,18)}","${ico(d.kind,20)}")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

# Stage LINE-DOC-ALERT-CARD — ตัวอย่างใน CRM แสดงเป็น "การ์ด" แบบเดียวกับที่ส่งเข้า LINE (ต่อจาก patch_line_alert.py)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT' in t, 'run patch_line_alert.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep('''  <div class="mbody"><div id="lineAlertPvBody" style="white-space:pre-wrap;font-size:13px;line-height:1.6;background:#f6f7f9;border:1px solid var(--g2);border-radius:var(--rl);padding:12px 14px;max-height:60vh;overflow-y:auto"></div></div>''',
'''  <div class="mbody" style="background:#8CABD9"><div id="lineAlertPvBody" style="max-height:62vh;overflow-y:auto"></div></div>''')
rep('''<div class="mb mb-sm" onclick="event.stopPropagation()" style="max-width:520px">
  <div class="mh"><div class="mt" id="lineAlertPvTitle">ตัวอย่างข้อความ</div>''','''<div class="mb mb-sm" onclick="event.stopPropagation()" style="max-width:440px">
  <div class="mh"><div class="mt" id="lineAlertPvTitle">ตัวอย่างข้อความ</div>''')
rep('''  const parts=Array.isArray(r.data.parts)?r.data.parts:[];
  document.getElementById('lineAlertPvTitle').textContent='ตัวอย่างข้อความ · '+(g.name||'');
  document.getElementById('lineAlertPvBody').textContent=parts.length?parts.join('\\n\\n— ข้อความถัดไป —\\n\\n'):'ตอนนี้ไม่มีเอกสารที่ต้องเตือน (หรือเตือนไปแล้วทั้งหมด) — วันนี้จะไม่ส่งข้อความเข้ากลุ่มนี้';''',
'''  // Stage LINE-DOC-ALERT-CARD: แสดงเป็นการ์ดแบบเดียวกับใน LINE (การ์ดละไม่เกิน 6 คน เลื่อนดูใบถัดไปได้)
  const c=r.data.card, ws=(c&&Array.isArray(c.workers))?c.workers:[];
  document.getElementById('lineAlertPvTitle').textContent='ตัวอย่างการ์ด LINE · '+(g.name||'');
  const chip=dy=>{const[bg,fg]=dy<=7?['#FDE8E8','#C62828']:dy<=30?['#FFF1DE','#B45309']:['#E5F4EA','#1F8A4C'];return `<span style="background:${bg};color:${fg};font-size:10.5px;font-weight:700;padding:2px 8px;border-radius:99px;white-space:nowrap">${dy<=0?'วันนี้':'อีก '+dy+' วัน'}</span>`;};
  const pages=[];for(let i=0;i<ws.length;i+=6)pages.push(ws.slice(i,i+6));
  document.getElementById('lineAlertPvBody').innerHTML=!ws.length
    ?'<div style="background:#fff;border-radius:14px;padding:16px;font-size:13px;color:var(--g7)">ตอนนี้ไม่มีเอกสารที่ต้องเตือน (หรือเตือนไปแล้วทั้งหมด) — วันนี้จะไม่ส่งข้อความเข้ากลุ่มนี้</div>'
    :pages.map((pg,pi)=>`<div style="background:#fff;border-radius:16px;overflow:hidden;margin-bottom:10px;box-shadow:0 1px 3px rgba(0,0,0,.12)">
      <div style="background:#F26B1D;color:#fff;padding:14px 16px"><div style="font-size:11.5px;font-weight:700;color:#FFE9DB">🔔 แจ้งเตือนเอกสารใกล้หมดอายุ</div><div style="font-size:17px;font-weight:800;margin-top:2px">${esc(c.target||'-')}</div><div style="font-size:11px;color:#FFE9DB;margin-top:2px">${Number(c.count)||0} รายการ${pages.length>1?' · หน้า '+(pi+1)+'/'+pages.length:''} · ต่ออายุก่อนหมดเพื่อไม่ให้โดนปรับ</div></div>
      <div style="padding:12px 16px">${pg.map((w,wi)=>`<div style="${wi?'border-top:1px solid #eee;margin-top:10px;padding-top:10px':''}"><div style="font-size:13.5px;font-weight:700;color:#222">${pi*6+wi+1}. ${esc(w.name||'-')}</div>${w.employer?`<div style="font-size:11px;color:#8a8a8a">${esc(w.employer)}</div>`:''}
        ${(w.docs||[]).map(d=>`<div style="display:flex;align-items:center;gap:8px;margin-top:5px;font-size:12px"><span style="flex:5;color:#555">${esc(d.label||'')}</span><span style="flex:4;text-align:right;color:#222">${esc(d.date||'')}</span>${chip(Number(d.days)||0)}</div>`).join('')}</div>`).join('')}</div>
      <div style="padding:4px 12px 12px;display:flex;flex-direction:column;gap:7px">${c.url?`<a href="${esc(c.url)}" target="_blank" rel="noopener" style="display:block;text-align:center;background:#F26B1D;color:#fff;border-radius:8px;padding:9px;font-size:13px;font-weight:700;text-decoration:none">ดูรายละเอียดเอกสาร</a>`:'<div style="font-size:11px;color:#b45309;text-align:center">ยังไม่มีลิงก์นายจ้าง — สร้างลิงก์ก่อน ปุ่ม "ดูรายละเอียด" ถึงจะขึ้น</div>'}<div style="text-align:center;background:#f1f1f1;color:#333;border-radius:8px;padding:9px;font-size:13px;font-weight:700">โทรสอบถาม 096-823-4891</div><div style="text-align:center;font-size:10.5px;color:#9a9a9a">บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด</div></div></div>`).join('');''')
rep("// ── Stage LINE-DOC-ALERT: แจ้งเตือนเอกสารใกล้หมดอายุ เข้ากลุ่ม LINE ของนายจ้าง (admin) ──",
    "// ── Stage LINE-DOC-ALERT: แจ้งเตือนเอกสารใกล้หมดอายุ เข้ากลุ่ม LINE ของนายจ้าง (admin) ── (+ Stage LINE-DOC-ALERT-CARD: ส่งเป็นการ์ด)")
rep("<button class=\"btn btn-g btn-sm\" onclick=\"laPreview(${i})\">👀 ดูตัวอย่างข้อความ</button>","<button class=\"btn btn-g btn-sm\" onclick=\"laPreview(${i})\">👀 ดูตัวอย่างการ์ด</button>")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

# Stage LINE-DOC-ALERT-CARD2 — ตัวอย่างการ์ดใน CRM ให้ตรงกับการ์ดแบบใหม่ (เล็กลง · ไอคอนสี · รูปพื้นหลังนายจ้าง · ไม่มีเบอร์โทร)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage LINE-DOC-ALERT-CARD2' in t: print('already'); sys.exit(0)
assert 'Stage LINE-DOC-ALERT-CARD' in t, 'run patch_line_alert2.py first'
i=t.index('  // Stage LINE-DOC-ALERT-CARD: แสดงเป็นการ์ดแบบเดียวกับใน LINE')
j=t.index("\n}\nasync function laSendNow")
new=r'''  // Stage LINE-DOC-ALERT-CARD2: แสดงเป็นการ์ดแบบเดียวกับใน LINE (การ์ดละไม่เกิน 6 คน เลื่อนดูใบถัดไปได้)
  const c=r.data.card, ws=(c&&Array.isArray(c.workers))?c.workers:[];
  document.getElementById('lineAlertPvTitle').textContent='ตัวอย่างการ์ด LINE · '+(g.name||'');
  const IC={bell:['none','<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>'],
    passport:['#1D64B0','<rect x="6" y="3.5" width="12" height="17" rx="1.8"/><circle cx="12" cy="10.5" r="3"/><path d="M9 10.5h6M12 7.5c1.2 1.6 1.2 4.4 0 6M12 7.5c-1.2 1.6-1.2 4.4 0 6M9.5 16.5h5"/>'],
    visa:['#7C3AED','<rect x="3.5" y="6" width="17" height="12" rx="1.8"/><path d="M3.5 10h17"/><path d="M7 14.5h4M14.5 14.5h2.5"/>'],
    wp:['#16A34A','<rect x="3.5" y="5.5" width="17" height="13" rx="1.8"/><circle cx="9" cy="11" r="2"/><path d="M6 15.5c.6-1.6 1.7-2.3 3-2.3s2.4.7 3 2.3M14 10h3.5M14 13h3.5"/>'],
    d90:['#EA580C','<rect x="4" y="5.5" width="16" height="14" rx="1.8"/><path d="M4 10h16M8.5 3.5v4M15.5 3.5v4"/><path d="M9 14.5l2 2 4-4"/>'],
    mou:['#0D9488','<path d="M7 3.5h7l4 4V20a.5.5 0 0 1-.5.5h-10.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14 3.5v4h4M9 12h6M9 15.5h4"/>']};
  const ico=(k,px)=>{const x=IC[k];if(!x)return'';return `<span style="display:inline-grid;place-items:center;width:${px}px;height:${px}px;border-radius:${x[0]==='none'?0:Math.round(px*.27)}px;background:${x[0]==='none'?'transparent':x[0]};flex:none"><svg width="${Math.round(px*(x[0]==='none'?.95:.65))}" height="${Math.round(px*(x[0]==='none'?.95:.65))}" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${x[1]}</svg></span>`;};
  const chip=dy=>{const[bg,fg]=dy<=7?['#FDE8E8','#C62828']:dy<=30?['#FFF1DE','#B45309']:['#E5F4EA','#1F8A4C'];return `<span style="background:${bg};color:${fg};font-size:10px;font-weight:700;padding:1px 6px;border-radius:99px;white-space:nowrap">${dy<=0?'วันนี้':dy+' วัน'}</span>`;};
  const pages=[];for(let i=0;i<ws.length;i+=6)pages.push(ws.slice(i,i+6));
  const title=(pi)=>`<div style="display:flex;align-items:center;gap:4px;font-size:10.5px;font-weight:700;color:#fff">${ico('bell',13)}แจ้งเตือนเอกสารใกล้หมดอายุ</div><div style="font-size:15px;font-weight:800;color:#fff;line-height:1.3;margin-top:1px">${esc(c.target||'-')}</div><div style="font-size:10.5px;color:#FFE9DB">${Number(c.count)||0} รายการ${pages.length>1?' · '+(pi+1)+'/'+pages.length:''}</div>`;
  const head=(pi)=>`<div class="laHero" style="position:relative;background:linear-gradient(90deg,#F26B1D,#F59E3B)"><div class="laHeroImg" style="display:none;aspect-ratio:2/1;background:#ddd center/cover no-repeat"></div><div class="laHeroTxt" style="padding:11px 12px">${title(pi)}</div></div>`;
  document.getElementById('lineAlertPvBody').innerHTML=!ws.length
    ?'<div style="background:#fff;border-radius:14px;padding:16px;font-size:13px;color:var(--g7)">ตอนนี้ไม่มีเอกสารที่ต้องเตือน (หรือเตือนไปแล้วทั้งหมด) — วันนี้จะไม่ส่งข้อความเข้ากลุ่มนี้</div>'
    :`<div style="display:flex;gap:10px;overflow-x:auto;padding-bottom:4px">${pages.map((pg,pi)=>`<div style="flex:none;width:260px;background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.12)">${head(pi)}
      <div style="padding:10px 12px">${pg.map((w,wi)=>`<div style="${wi?'border-top:1px solid #f0f0f0;margin-top:9px;padding-top:9px':''}"><div style="font-size:12px;font-weight:700;color:#222">${pi*6+wi+1}. ${esc(w.name||'-')}</div>${w.employer?`<div style="font-size:10px;color:#9a9a9a">${esc(w.employer)}</div>`:''}
        ${(w.docs||[]).map(d=>`<div style="display:flex;align-items:center;gap:6px;margin-top:5px">${ico(d.kind,18)}<span style="flex:1;font-size:11.5px;color:#4a4a4a">${esc(d.label||'')}</span><span style="font-size:10px;color:#8a8a8a">${esc(d.date||'')}</span>${chip(Number(d.days)||0)}</div>`).join('')}</div>`).join('')}</div>
      ${c.url?`<div style="padding:0 10px 10px"><a href="${esc(c.url)}" target="_blank" rel="noopener" style="display:block;text-align:center;background:#F26B1D;color:#fff;border-radius:7px;padding:8px;font-size:12.5px;font-weight:700;text-decoration:none">ดูรายละเอียดเอกสาร</a></div>`:'<div style="font-size:10.5px;color:#b45309;text-align:center;padding:0 10px 10px">ยังไม่มีลิงก์นายจ้าง — สร้างลิงก์ก่อน ปุ่ม "ดูรายละเอียด" ถึงจะขึ้น</div>'}</div>`).join('')}</div>`;
  document.getElementById('lineAlertPvModal').style.display='flex';
  // รูปพื้นหลังของนายจ้าง (ถ้ามี) — แสดงแบบเดียวกับการ์ดจริง
  if(ws.length&&c.banner&&c.banner.id&&typeof CUST_DOC_SIGN_URL==='string'){
    try{const res=await fetch(CUST_DOC_SIGN_URL,{method:'POST',mode:'cors',headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json'},
        body:JSON.stringify({document_id:Number(c.banner.id),user_id:curUser&&curUser.id!=null?String(curUser.id):'',username:curUser&&curUser.username||''})});
      const d=await res.json();
      if(d&&d.ok&&d.url)document.querySelectorAll('#lineAlertPvBody .laHero').forEach(h=>{const im=h.querySelector('.laHeroImg'),tx=h.querySelector('.laHeroTxt');
        im.style.display='block';im.style.backgroundImage=`url("${String(d.url).replace(/"/g,'%22')}")`;h.style.background='#000';
        tx.style.cssText='position:absolute;left:0;right:0;bottom:0;padding:22px 12px 10px;background:linear-gradient(0deg,rgba(0,0,0,.7),rgba(0,0,0,0))';});}catch(_){}
  }'''
t=t[:i]+new+t[j:]
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

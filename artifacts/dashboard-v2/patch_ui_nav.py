# Stage UI-NAV-2 — จัดหัว/เมนูใหม่
#   * กระดิ่งแจ้งเตือนย้ายไปซ้ายของปุ่ม TH ไทย · เอาปุ่ม "นำเข้าไฟล์" กับ "+ เพิ่มลูกค้า" ออกจากแถบบน
#   * "+ เพิ่มลูกค้า" ไปอยู่ที่หน้าลูกค้า (แถวค้นหา)
#   * เมนูข้าง: ซ่อน "ตอกบัตร" (ข้อมูลยังอยู่) · "นำเข้า" ขึ้นมาเป็นข้อ 4 (ต่อจากนายจ้าง)
#     แถบล่างมือถือ: ตอกบัตร → นายจ้าง
#   * หน้า "จัดการกลุ่ม" เป็นการ์ดแบบหน้านายจ้าง (ค้นหา · จำนวนแรงงาน · ด่วน · กดการ์ด = ดูแรงงานในกลุ่ม)
import sys,re
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage UI-NAV-2' in t: print('already'); sys.exit(0)
assert 'Stage NOTIFY-BELL' in t, 'run patch_bell.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
# 1) topbar
m=re.search(r'\n      <button class="theme-btn nb-btn" id="nbBtn"[^\n]*</button>',t); assert m
bell=m.group(0); t=t.replace(bell,'',1)
rep("""      <div class="lang-sw">
        <button class="lang-btn active" id="langTH\"""",bell[1:].replace('<button class="theme-btn nb-btn"','<!-- Stage UI-NAV-2 --><button class="theme-btn nb-btn"')+"""
      <div class="lang-sw">
        <button class="lang-btn active" id="langTH\"""")
m=re.search(r'\n    <button class="btn btn-g btn-sm" onclick="gv\(\'import\'\)">.*?นำเข้าไฟล์</button>\n    <button class="btn btn-p" onclick="openAdd\(\)">\+ เพิ่มลูกค้า</button>',t); assert m
t=t.replace(m.group(0),'',1)
# 2) customers toolbar
rep("""        <select class="fi" id="qassignee" onchange="doFilter()"><option value="">ผู้รับผิดชอบทั้งหมด</option></select>
      </div>""","""        <select class="fi" id="qassignee" onchange="doFilter()"><option value="">ผู้รับผิดชอบทั้งหมด</option></select>
        <button class="btn btn-p btn-sm" id="custAddBtn" onclick="openAdd()">+ เพิ่มลูกค้า</button>
      </div>""")
rep("""  const addBtn=document.querySelector('.topbar .btn-p');""","""  const addBtn=document.getElementById('custAddBtn');""")
# 3) mobile bottom nav: employers after customers (attendance hidden by CSS)
m=re.search(r'<div class="di" data-view="employers" onclick="mobNav\(\'employers\'\);mobDrawerClose\(\)">(<svg.*?</svg>)',t); assert m
svg=m.group(1)
m2=re.search(r'\n    <button class="mn-item" data-view="customers" onclick="mobNav\(\'customers\'\)">[^\n]*</button>',t); assert m2
t=t.replace(m2.group(0),m2.group(0)+'\n    <button class="mn-item" data-view="employers" onclick="mobNav(\'employers\')">'+svg+'<span class="mn-lbl">นายจ้าง</span></button>',1)
# 4) CSS
rep("""<style id="hideCaseModule">""","""<style id="uiNav2">/* Stage UI-NAV-2 */#niAttendance,#mobDrawer .di[data-view="attendance"],#mobNav .mn-item[data-view="attendance"],#mobMore .ms-item[onclick*="'attendance'"]{display:none!important}
#custAddBtn{margin-left:auto;white-space:nowrap;order:99}
@media(max-width:768px){#view-customers .toolbar #custAddBtn{grid-column:1/-1;margin-left:0;justify-content:center;min-height:40px}}
.grp-card .gc-act{display:flex;gap:6px;align-items:center;margin-top:10px}
.grp-card .gc-act .btn{font-size:11px;padding:4px 10px}
.grp-card .gc-desc{font-size:11px;color:var(--g5);margin-bottom:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
</style>
<style id="hideCaseModule">""")
# 5) nav order: นำเข้า ต่อจากนายจ้าง
rep("""  mv(document.getElementById('niDash'),[document.getElementById('niCustomers'),document.getElementById('sacc-cust'),document.getElementById('niEmployers')]);
  mv(document.querySelector('#mobDrawer .di[data-view="dash"]'),[document.querySelector('#mobDrawer .di[data-view="customers"]'),document.getElementById('dacc-cust'),document.querySelector('#mobDrawer .di[data-view="employers"]')]);""","""  mv(document.getElementById('niDash'),[document.getElementById('niCustomers'),document.getElementById('sacc-cust'),document.getElementById('niEmployers'),document.getElementById('niImport')]);
  mv(document.querySelector('#mobDrawer .di[data-view="dash"]'),[document.querySelector('#mobDrawer .di[data-view="customers"]'),document.getElementById('dacc-cust'),document.querySelector('#mobDrawer .di[data-view="employers"]'),document.querySelector('#mobDrawer .di[data-view="import"]')]);""")
# 6) groups page = employer style
a=t.index('function renderGroups(){'); b=t.index('function openAddGrp(){')
t=t[:a]+r"""// Stage UI-NAV-2: หน้าจัดการกลุ่มแบบเดียวกับหน้านายจ้าง
let grpQ='';
function renderGroups(){
  document.getElementById('grpContent').innerHTML=`
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px">
      <div style="font-size:16px;font-weight:700">${T('grpTitle')}</div>
      <button class="btn btn-p btn-sm" onclick="openAddGrp()">${T('grpAdd')}</button>
    </div>
    <div style="display:flex;gap:8px;align-items:center;margin-bottom:12px">
      <div class="srch" style="flex:1">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
        <input class="si" id="grpSearchInput" placeholder="ค้นหาชื่อกลุ่ม / รายละเอียด..." oninput="grpFilter(this.value)" value="${esc(grpQ)}">
      </div>
      <button class="btn btn-g btn-sm" id="grpClearBtn" onclick="grpFilter('')" style="display:${grpQ?'inline-flex':'none'}">${T('empClear')}</button>
    </div>
    <div id="grpResultCount" style="font-size:12px;color:var(--g5);margin-bottom:10px"></div>
    <div id="grpGrid" class="emp-grid"></div>
    <div style="margin-top:4px;padding:10px 13px;background:var(--pp);border-radius:var(--r);font-size:12px;color:var(--pd)">${T('grpTip')}</div>`;
  renderGrpGrid();
}
function grpFilter(q){
  grpQ=q;
  const inp=document.getElementById('grpSearchInput');if(inp&&inp.value!==q)inp.value=q;
  const cb=document.getElementById('grpClearBtn');if(cb)cb.style.display=q?'inline-flex':'none';
  renderGrpGrid();
}
function grpOpen(id){const g=groups.find(x=>x.id===id);if(!g)return;gv('customers',{grp:id,title:g.name});}
function renderGrpGrid(){
  const _ga=_isAdminRole();   // Stage 49A-2: ปุ่มลบกลุ่ม แสดงเฉพาะ admin
  const q=grpQ.toLowerCase().trim();
  const filt=q?groups.filter(g=>[g.name,g.description].some(v=>v&&String(v).toLowerCase().includes(q))):groups;
  const rc=document.getElementById('grpResultCount');if(rc)rc.textContent=q?T('empFoundFmt').replace('{n}',filt.length):'';
  const grid=document.getElementById('grpGrid');if(!grid)return;
  if(!filt.length){
    grid.innerHTML=q
      ?`<div style="color:var(--g5);font-size:13px;padding:50px;text-align:center;grid-column:1/-1"><div style="font-size:36px;opacity:.3;margin-bottom:8px">🔍</div>${T('empNoResult')}</div>`
      :`<div style="color:var(--g5);font-size:13px;padding:40px;text-align:center;grid-column:1/-1">${T('grpNone')}<br><button class="btn btn-p btn-sm" style="margin-top:12px" onclick="openAddGrp()">${T('grpAdd')}</button></div>`;
    return;
  }
  grid.innerHTML=filt.map(g=>{
    const cnt=customers.filter(c=>c.group_id===g.id).length;
    const alrt=customers.filter(c=>c.group_id===g.id&&isAlert(c)).length;
    return`<div class="emp-card grp-card" onclick="grpOpen(${g.id})">
      <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:8px">
        <div style="width:32px;height:32px;border-radius:8px;background:var(--pp);display:flex;align-items:center;justify-content:center;flex-shrink:0"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--p)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg></div>
        ${alrt>0?`<span class="eb eb-u">${alrt} ${T('empUrgent')}</span>`:''}
      </div>
      <div style="font-weight:700;font-size:14px;color:var(--g9);margin-bottom:4px">${esc(g.name)}</div>
      ${g.description?`<div class="gc-desc" title="${esc(g.description)}">${esc(g.description)}</div>`:''}
      <div style="display:flex;align-items:center;justify-content:space-between;margin-top:8px;padding-top:8px;border-top:1px solid var(--g1)">
        <span style="font-size:12px;color:var(--g5)">${T('empWorkers')}</span>
        <span style="font-size:18px;font-weight:800;font-family:var(--mono);color:var(--p)">${cnt}</span>
      </div>
      <div class="gc-act" onclick="event.stopPropagation()">
        <button class="btn btn-g btn-sm" onclick="openGrpShare(${g.id})">🔗 ลิงก์/QR</button>
        <button class="btn btn-g btn-sm" onclick="openEditGrp(${g.id})">แก้ไข</button>
        ${_ga?`<button class="btn btn-g btn-sm" style="color:var(--red);margin-left:auto" onclick="delGrp(${g.id})">ลบ</button>`:''}
      </div>
    </div>`;
  }).join('');
}
"""+t[b:]
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

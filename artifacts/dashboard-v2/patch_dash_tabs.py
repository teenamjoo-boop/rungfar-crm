# Stage DASH-TABS-TRIM — หน้าหลักเหลือแท็บ ทั้งหมด / ต่ออายุ / 90 วัน
#   ปิด: เอกสารค้าง · งานที่ต้องทำ · พนักงานขาดงาน · ยังไม่เช็คเอาท์ (ไม่ได้ใช้) — ไม่ลบข้อมูล/ฟังก์ชันเดิม
#   การ์ดสรุปเหลือ 3 ใบ (ตัด "เอกสารค้าง") · ตัดชิป "นัดหมาย / คิว / รับเล่ม" · ไม่โหลดยอดขาดงาน/เช็คเอาท์แล้ว
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage DASH-TABS-TRIM' in t: print('already'); sys.exit(0)
assert 'Stage DASH-V2' in t, 'run patch_dash.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("""  const TABS=[['all',T('dashFAll'),''],['renew',T('dashFRenew'),cntB(renewEntries.length)],['90',T('exp90'),cntB(d90Entries.length)],['docs',T('dashFDocs'),cntB(docPending.length)],['todo',T('dashFTodo'),cntB(todoEntries.length)],['absent',T('dashFAbsent'),dashCountBadge(dash_absentCount)],['noout',T('dashFNoOut'),dashCountBadge(dash_nooutCount)]];""","""  // Stage DASH-TABS-TRIM: เหลือ ทั้งหมด / ต่ออายุ / 90 วัน
  if(!['all','renew','90'].includes(dashFilter))dashFilter='all';
  const TABS=[['all',T('dashFAll'),''],['renew',T('dashFRenew'),cntB(renewEntries.length)],['90',T('exp90'),cntB(d90Entries.length)]];""")
rep("""  if(dashFilter==='absent')dashRenderAbsentToday();
  else dashRefreshAbsentCount();
  if(dashFilter==='noout')dashRenderNooutToday();
  else dashRefreshNooutCount();
}""","""}""")
rep("""    ${k('','doc','amber','เอกสารค้าง',o.docPending.length,'ใบแพทย์ / ประกัน / เล่ม / ค่าบัตร',"dashGo('docs')")}
""","")
rep("""<span onclick="dashGo('todo')"><b>${o.todoEntries.length}</b>นัดหมาย / คิว / รับเล่ม</span>""","")
rep(""".dx-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-bottom:12px}""",""".dx-kpis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:12px}""")
rep("""@media(max-width:768px){.dx-kpis{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}""","""@media(max-width:768px){.dx-kpis{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.dx-kpis>.dx-k:nth-child(3){grid-column:1/-1}""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

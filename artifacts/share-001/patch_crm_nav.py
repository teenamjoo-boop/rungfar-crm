# Stage NAV-ORDER: เมนูซ้าย (และเมนูมือถือ) เรียง หน้าหลัก → ลูกค้า → นายจ้าง/บริษัท → ที่เหลือเหมือนเดิม
import sys
MARK = 'Stage NAV-ORDER'
JS = r'''// ── Stage NAV-ORDER: ลูกค้า = ข้อ 2, นายจ้าง = ข้อ 3 (ย้ายตำแหน่งเมนูอย่างเดียว ไม่แตะการทำงาน) ──
function _swReorderNav(){
  if(!SIMPLE_WORKER_MODE)return;
  const mv=(anchor,els)=>{let a=anchor;els.forEach(el=>{if(el&&a){a.after(el);a=el;}});};
  mv(document.getElementById('niDash'),[document.getElementById('niCustomers'),document.getElementById('sacc-cust'),document.getElementById('niEmployers')]);
  mv(document.querySelector('#mobDrawer .di[data-view="dash"]'),[document.querySelector('#mobDrawer .di[data-view="customers"]'),document.getElementById('dacc-cust'),document.querySelector('#mobDrawer .di[data-view="employers"]')]);
}
try{_swReorderNav();}catch(_e){console.warn('[NAV] reorder',_e);}
'''
def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    a = "try{_swMoveDocNo();}catch(_e){console.warn('[S2] move doc fields',_e);}"
    if s.count(a) != 1: sys.exit(path + ': anchor')
    s = s.replace(a, a + nl + JS.replace('\n', nl))
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')
for p in sys.argv[1:]:
    patch(p)

# Stage SHARE-GROUP (หน้าเว็บ): ลิงก์รวมของกลุ่ม — หัวเป็นชื่อกลุ่ม, แสดงชื่อนายจ้างของแรงงานแต่ละคน,
#   ปุ่มกรองตามนายจ้าง (เมื่อกลุ่มมีมากกว่า 1 นายจ้าง) — ลิงก์นายจ้างเดิมหน้าตาเหมือนเดิม
import sys
MARK = 'Stage SHARE-GROUP'
CSS = """/* Stage SHARE-GROUP */
.echips{display:flex;gap:6px;flex-wrap:wrap;margin:2px 2px 10px}
.echip{font-size:13px;font-weight:600;padding:6px 12px;border-radius:99px;background:var(--card);border:1px solid var(--line);color:var(--ink)}
.echip.on{background:var(--brand);border-color:var(--brand);color:#fff}
#list .echips{grid-column:1/-1}
"""
JS = """// Stage SHARE-GROUP: กรองตามนายจ้าง (ลิงก์กลุ่ม)
let empF='';
function setEmpF(n){ empF=n||''; render(); }
function empChips(){
  if(!DATA||!DATA.employer||!DATA.employer.group) return '';
  const emps=[...new Set(DATA.workers.map(w=>w.employer).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'th'));
  if(emps.length<2) return '';
  return '<div class="echips">'+['',...emps].map(n=>`<button class="echip${n===empF?' on':''}" data-n="${esc(n)}" onclick="setEmpF(this.dataset.n)">${n?esc(n):'ทุกนายจ้าง'}</button>`).join('')+'</div>';
}
"""
def rep(s, o, n, path):
    if s.count(o) != 1: sys.exit(path + ': anchor ' + o[:60])
    return s.replace(o, n)
def patch(path):
    s = open(path, encoding='utf-8').read()
    if MARK in s: print(path, ': already patched — skip'); return
    s = rep(s, '</style>', CSS + '</style>', path)
    s = rep(s, "let DATA=null, filter='all';", "let DATA=null, filter='all';\n" + JS, path)
    s = rep(s, "document.getElementById('empSub').textContent='สถานะเอกสารแรงงาน'+(E.area?` · ${E.area}`:'');",
            "document.getElementById('empSub').textContent='สถานะเอกสารแรงงาน'+(E.group?` · ${E.employers||''} นายจ้าง`:(E.area?` · ${E.area}`:''));", path)
    s = rep(s, ".sort((a,b)=>(a.x?a.x.rank:3)", ".filter(t=>!empF||t.w.employer===empF)\n    .sort((a,b)=>(a.x?a.x.rank:3)", path)
    s = rep(s, "if(!rows.length){ L.innerHTML='<div class=\"empty\">ไม่พบแรงงานในกลุ่มนี้</div>'; return; }",
            "if(!rows.length){ L.innerHTML=empChips()+'<div class=\"empty\">ไม่พบแรงงานในกลุ่มนี้</div>'; return; }", path)
    s = rep(s, 'L.innerHTML=`<div class="sec">${head}</div>`+rows.map(', 'L.innerHTML=empChips()+`<div class="sec">${head}</div>`+rows.map(', path)
    s = rep(s, """<div class="en">${w.name_th&&w.name_en?esc(w.name_en)+' · ':''}${esc(w.nationality||'')}</div>""",
            """<div class="en">${w.name_th&&w.name_en?esc(w.name_en)+' · ':''}${esc(w.nationality||'')}${DATA.employer.group&&w.employer?' · '+esc(w.employer):''}</div>""", path)
    s = rep(s, "esc([w.category, w.nationality, DATA.employer.name].filter(Boolean).join(' · '))",
            "esc([w.category, w.nationality, w.employer||DATA.employer.name].filter(Boolean).join(' · '))", path)
    s = rep(s, "['นายจ้าง',DATA.employer.name]", "['นายจ้าง',w.employer||DATA.employer.name]", path)
    open(path, 'w', encoding='utf-8').write(s); print(path, ': patched')
for p in sys.argv[1:]: patch(p)

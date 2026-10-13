# Stage SHEET-VIEW + EMP-HUB
#  SHEET-VIEW: หน้า "ลูกค้า" เป็นตารางแบบ Google Sheets (โหมด SIMPLE_WORKER_MODE)
#    ลำดับ | รูป | นายจ้าง | ชื่อต่างด้าว | สัญชาติ | ประเภท | WORK | เวิร์คหมด | PASSPORT | เล่มหมดอายุ
#    | VISA หมด | 90 วัน | สถานะ | รายการ | หมายเหตุ | จัดการ
#    - วันหมดอายุทุกช่องมีป้าย "อีก X วัน / เลย X วัน" สีตามค่าตั้งเตือนกลาง (app_alert_settings)
#    - ประเภท / สถานะ / รายการ / หมายเหตุ กดที่ช่องแก้ได้ทันที (บันทึกผ่าน app_save_customer เดิม)
#    - เรียง: ใกล้หมดก่อน / ล่าสุด / นายจ้าง · ติ๊ก "จัดกลุ่มตามนายจ้าง" · ตัวกรองนายจ้าง/ประเภท
#    - ปุ่มด่วน: ทั้งหมด / ใกล้หมด / เลยกำหนด / ยังไม่มีวันหมดอายุ
#    - ช่องใหม่ในฐานข้อมูล: worker_category, status_note, work_items (migration 20261010)
#      ถ้ายังไม่รัน SQL → ตารางยังใช้ได้ แต่ 3 ช่องนี้แก้ไม่ได้ (แจ้งเตือน) — ไม่พัง
#  EMP-HUB: หน้านายจ้าง = ศูนย์รวม (สรุปตัวเลข · ลิงก์ลูกค้า · เอกสารนายจ้าง+วันหมดอายุ+อัปโหลด
#    · ตารางแรงงานเรียงตามความเร่งด่วน · ข้อมูลเพิ่มเติม/สถานประกอบการพับเก็บ)
#    อัปโหลดผ่าน customer-doc-upload (owner_type='employer') — ต้อง deploy เวอร์ชัน EMP-DOCS ก่อน
import sys

MARK = 'Stage SHEET-VIEW'

OLD_S1_COLS = ('html.simple-worker #view-customers th:nth-child(2),html.simple-worker #view-customers td:nth-child(2),'
               'html.simple-worker #view-customers th:nth-child(9),html.simple-worker #view-customers td:nth-child(9),'
               'html.simple-worker #view-customers th:nth-child(10),html.simple-worker #view-customers td:nth-child(10),'
               'html.simple-worker #view-customers th:nth-child(14),html.simple-worker #view-customers td:nth-child(14){display:none!important}')

CSS = r'''<style id="sheetView">/* Stage SHEET-VIEW + EMP-HUB */
html:not(.simple-worker) .sw-only{display:none!important}
html.sheet-nocols .sw-only{display:none!important}
html.simple-worker #qct,html.simple-worker #qws{display:none!important}
table.sh-t{border-collapse:separate;border-spacing:0;width:100%}
table.sh-t th{background:#eef2f7;color:#334155;font-size:11px;font-weight:700;white-space:nowrap;padding:7px 8px;border-bottom:1px solid #cbd5e1;border-right:1px solid #e2e8f0;text-align:left;text-transform:none;letter-spacing:0}
table.sh-t td{padding:6px 8px;border-bottom:1px solid #e5e7eb;border-right:1px solid #f1f5f9;vertical-align:middle;font-size:12px}
table.sh-t tr.sh-r{cursor:pointer}
table.sh-t tr.sh-r:hover td{background:#f8fafc}
table.sh-t tr.sh-lv2 td:first-child{box-shadow:inset 3px 0 0 #dc2626}
table.sh-t tr.sh-lv1 td:first-child{box-shadow:inset 3px 0 0 #f59e0b}
.sh-no{color:#94a3b8;font-family:var(--mono);font-size:11px;text-align:right}
.sh-mono{font-family:var(--mono);font-size:11.5px;white-space:nowrap}
.sh-emp{max-width:170px;font-size:11.5px;color:#334155}
.sh-d{font-size:11.5px;white-space:nowrap;color:#1f2937}
.sh-chip{display:inline-block;margin-top:2px;padding:1px 7px;border-radius:20px;font-size:10px;font-weight:700;white-space:nowrap}
.sh-ok{background:#ecfdf5;color:#047857}.sh-w{background:#fef3c7;color:#b45309}.sh-x{background:#fee2e2;color:#b91c1c}
.sh-na{color:#9ca3af;font-size:11px}
.sh-cat{display:inline-block;padding:2px 8px;border-radius:6px;background:#f1f5f9;color:#334155;font-size:11px;font-weight:700;white-space:nowrap}
.sh-cat.c-mou{background:#eef2ff;color:#4338ca}.sh-cat.c-mati{background:#ecfeff;color:#0e7490}
.sh-ed{cursor:text}.sh-ed:hover{outline:1px dashed #93c5fd;outline-offset:-3px}
.sh-txt{max-width:190px;min-width:100px;white-space:pre-wrap;word-break:break-word;font-size:11.5px}
.sh-add{color:#cbd5e1;font-size:12px}.sh-ed:hover .sh-add{color:#3b82f6}
.sh-in{width:100%;min-width:120px;font:inherit;font-size:12px;padding:4px 6px;border:1.5px solid #3b82f6;border-radius:6px;outline:none;background:#fff;box-sizing:border-box}
tr.sh-grp td{background:#f8fafc;font-weight:700;color:#0f172a;font-size:12.5px;padding:8px 10px;border-top:2px solid #cbd5e1;cursor:pointer}
tr.sh-grp .sh-gs{font-weight:500;color:#64748b;font-size:11.5px;margin-left:8px}
.sh-ctl{display:inline-flex;gap:6px;align-items:center;flex-wrap:wrap}
.sh-ctl select{font:inherit;font-size:12px;padding:4px 8px;border:1px solid var(--g3);border-radius:7px;background:#fff}
.sh-ctl label{font-size:12px;color:var(--g6);display:inline-flex;align-items:center;gap:4px;cursor:pointer;white-space:nowrap}
.qv-chip b{font-family:var(--mono);margin-left:4px}
.cc-sh{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}
.cc-sh .sh-chip{margin-top:0}
.cc-stn{font-size:11px;color:#334155;background:#f1f5f9;border-radius:6px;padding:1px 7px}
.eh-top{display:flex;gap:12px;align-items:flex-start;margin-bottom:12px}
.eh-ic{width:40px;height:40px;border-radius:10px;background:var(--pp);display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0}
.eh-name{font-size:19px;font-weight:800;color:var(--g9)}
.eh-sub{font-size:12px;color:var(--g5);margin-top:2px}
.eh-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:12px}
.eh-st{background:var(--g0);border:1px solid var(--g2);border-radius:10px;padding:8px 10px}
.eh-st b{display:block;font-size:20px;font-family:var(--mono);color:var(--g9)}
.eh-st span{font-size:11px;color:var(--g5)}
.eh-st.w{background:#fffbeb;border-color:#fde68a}.eh-st.w b{color:#b45309}
.eh-st.x{background:#fef2f2;border-color:#fecaca}.eh-st.x b{color:#b91c1c}
.eh-sec{margin-top:14px;padding-top:12px;border-top:1px solid var(--g2)}
.eh-h{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:13px;font-weight:700;color:var(--g8);margin-bottom:8px}
.eh-hint{font-size:11px;font-weight:400;color:var(--g5)}
.eh-tbl{overflow-x:auto;border:1px solid var(--g2);border-radius:10px}
.eh-doc{display:flex;align-items:center;gap:10px;padding:8px 10px;border:1px solid var(--g2);border-radius:9px;margin-bottom:6px;background:#fff}
.eh-doc-ic{font-size:18px}
.eh-doc-n{font-size:13px;font-weight:600;color:var(--g9);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.eh-doc-s{font-size:11px;color:var(--g5)}
.eh-doc-x{text-align:right;cursor:pointer;min-width:96px}
.eh-doc-x:hover{outline:1px dashed #93c5fd;outline-offset:2px;border-radius:6px}
.eh-up{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-end;background:var(--g0);border:1px dashed var(--g3);border-radius:9px;padding:10px;margin-top:8px}
.eh-up select,.eh-up input[type=date]{width:auto;min-width:150px}
.eh-lbl{display:flex;flex-direction:column;font-size:11px;color:var(--g5);gap:2px}
.eh-err{font-size:12px;color:#b91c1c;background:#fef2f2;border-radius:8px;padding:6px 10px;margin-bottom:6px}
.eh-more{margin-top:14px;border-top:1px solid var(--g2);padding-top:10px}
.eh-more summary{cursor:pointer;font-size:12px;font-weight:700;color:var(--g6)}
@media(max-width:700px){.eh-stats{grid-template-columns:repeat(2,1fr)}.eh-doc{flex-wrap:wrap}.eh-doc-x{text-align:left}}
</style>'''

COLS_DEF = r'''// Stage SHEET-VIEW: 3 ช่องใหม่ (migration 20261010) — ถ้ายังไม่รัน SQL จะ fallback อัตโนมัติ
const SHEET_COLS=',worker_category,status_note,work_items';
let _sheetColsOk=null;
'''

JS = r'''// =============================================================
// Stage SHEET-VIEW — ตารางแรงงานแบบ Google Sheets (SIMPLE_WORKER_MODE)
// =============================================================
let _sheetGroupEmp=false;try{_sheetGroupEmp=localStorage.getItem('crm_sheet_grp')==='1';}catch(_){}
let _sheetSort='urgent';try{_sheetSort=localStorage.getItem('crm_sheet_sort')||'urgent';}catch(_){}
const _SHEET_EXP=[['exp_wp','wp','WP'],['exp_passport','passport','เล่ม'],['exp_visa','visa','VISA'],['next_90','next90','90 วัน'],['exp_mou','mou','MOU']];
function _sheetW(k){const v=Number(typeof settings!=='undefined'&&settings&&settings[k]);return v>0?v:({passport:30,visa:30,wp:60,next90:7,mou:60})[k];}
function _sheetChipCls(d,w){if(d===null||d===undefined||isNaN(d))return'';if(d<0)return'sh-x';if(d<=w)return'sh-w';return'sh-ok';}
function _sheetDay(d){if(d===null||d===undefined||isNaN(d))return'';if(d<0)return'เลย '+Math.abs(d)+' วัน';if(d===0)return'หมดวันนี้';return'อีก '+d+' วัน';}
function _sheetDate(v,k){if(!v)return'<span class="sh-na">—</span>';const d=du(v);return`<div class="sh-d">${fd(v)}</div><span class="sh-chip ${_sheetChipCls(d,_sheetW(k))}">${_sheetDay(d)}</span>`;}
function _sheetMinDays(c){const xs=_SHEET_EXP.map(([f])=>du(c[f])).filter(d=>d!==null&&!isNaN(d));return xs.length?Math.min(...xs):null;}
// 2 = เลยกำหนด · 1 = ใกล้หมด (ภายในค่าตั้งเตือน) · 0 = ปกติ · -1 = ไม่มีวันหมดอายุ
function _sheetLevel(c){let lv=-1;_SHEET_EXP.forEach(([f,k])=>{const d=du(c[f]);if(d===null||isNaN(d))return;lv=Math.max(lv,d<0?2:(d<=_sheetW(k)?1:0));});return lv;}
function _sheetCatHtml(v){if(!v)return'<span class="sh-add">+ ประเภท</span>';const s=String(v);const cls=/mou/i.test(s)?'c-mou':(/มติ|ครม/.test(s)?'c-mati':'');return`<span class="sh-cat ${cls}">${esc(s)}</span>`;}
function _sheetAv(c){const ini=c.name?String(c.name).split(' ').map(w=>w[0]).slice(0,2).join('').toUpperCase():'?';
  const u=c.photo||(typeof _custPhotoCache!=='undefined'&&_custPhotoCache[c.id])||null;
  if(u)return`<img src="${esc(u)}" class="c-avatar" title="คลิกดูรูปใหญ่" onclick="openPhotoModal(this.src);event.stopPropagation()">`;
  return(c._hasPhoto||c.photo_storage_path)?`<div class="c-avatar-placeholder" data-custphoto="${c.id}">${esc(ini)}</div>`:`<div class="c-avatar-placeholder">${esc(ini)}</div>`;}
const _SHEET_HEAD=['','ลำดับ','รูป','นายจ้าง','ชื่อต่างด้าว','สัญชาติ','ประเภท','WORK','เวิร์คหมด','PASSPORT','เล่มหมดอายุ','VISA หมด','90 วัน','สถานะ','รายการ','หมายเหตุ',''];
function _sheetUiInit(){
  document.documentElement.classList.toggle('sheet-nocols',_sheetColsOk===false);
  const tr=document.querySelector('#view-customers thead tr');
  if(tr&&tr.dataset.sheet!=='1'){tr.dataset.sheet='1';tr.innerHTML=_SHEET_HEAD.map(h=>`<th>${h}</th>`).join('');const t=tr.closest('table');if(t)t.classList.add('sh-t');}
  const qv=document.getElementById('custQvChips');
  if(qv&&qv.dataset.sheet!=='1'){qv.dataset.sheet='1';customerQuickView='';
    qv.innerHTML=[['all','ทั้งหมด'],['soon','ใกล้หมด'],['overdue','เลยกำหนด'],['nodate','ยังไม่มีวันหมดอายุ']].map(([k,l])=>`<button class="qv-chip${k==='all'?' active':''}" id="qvc-${k}" onclick="setQuickView('${k==='all'?'':k}')">${l}<b id="qvn-${k}"></b></button>`).join('');}
  const tb=document.querySelector('#view-customers .toolbar');
  if(tb&&!document.getElementById('qemp')){
    tb.insertAdjacentHTML('beforeend',`<select class="fi" id="qemp" onchange="doFilter()"><option value="">นายจ้างทั้งหมด</option></select><select class="fi" id="qcat" onchange="doFilter()"><option value="">ประเภททั้งหมด</option></select>`);}
  const sb=document.getElementById('selAllBtn');
  if(sb&&!document.getElementById('sheetCtl')){
    sb.insertAdjacentHTML('beforebegin',`<span class="sh-ctl" id="sheetCtl"><select id="shSort" onchange="sheetSetSort(this.value)" title="เรียงลำดับ"><option value="urgent">เรียง: ใกล้หมดก่อน</option><option value="latest">เรียง: เพิ่มล่าสุด</option><option value="emp">เรียง: นายจ้าง</option></select><label><input type="checkbox" id="shGrp" onchange="sheetSetGroup(this.checked)">จัดกลุ่มตามนายจ้าง</label></span>`);}
  const ss=document.getElementById('shSort');if(ss)ss.value=_sheetSort;
  const sg=document.getElementById('shGrp');if(sg)sg.checked=_sheetGroupEmp;
  _sheetFillFilters();
}
function _sheetFillFilters(){
  const qe=document.getElementById('qemp');
  if(qe){const cur=qe.value;const used=new Set((customers||[]).map(c=>c.employer_id).filter(v=>v!=null));
    const list=(employers||[]).filter(e=>used.has(e.id)).sort((a,b)=>String(a.name||'').localeCompare(String(b.name||''),'th'));
    qe.innerHTML='<option value="">นายจ้างทั้งหมด</option>'+list.map(e=>`<option value="${e.id}">${esc(e.name)}</option>`).join('')+'<option value="__none__">— ไม่มีนายจ้าง —</option>';
    qe.value=cur;if(qe.selectedIndex<0)qe.value='';}
  const qc=document.getElementById('qcat');
  if(qc){const cur=qc.value;const cats=[...new Set(['MOU','มติ.ครม.',...(customers||[]).map(c=>c.worker_category).filter(Boolean)])];
    qc.innerHTML='<option value="">ประเภททั้งหมด</option>'+cats.map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('')+'<option value="__none__">— ไม่ระบุ —</option>';
    qc.value=cur;if(qc.selectedIndex<0)qc.value='';}
}
function _sheetFilterOk(c){
  const qe=document.getElementById('qemp')?.value||'';const qc=document.getElementById('qcat')?.value||'';
  if(qe&&(qe==='__none__'?c.employer_id!=null:String(c.employer_id||'')!==qe))return false;
  if(qc&&(qc==='__none__'?!!c.worker_category:c.worker_category!==qc))return false;
  return true;
}
function _sheetQv(c,v){if(v==='soon')return _sheetLevel(c)===1;if(v==='overdue')return _sheetLevel(c)===2;if(v==='nodate')return _sheetLevel(c)===-1;return null;}
function sheetSetSort(v){_sheetSort=v||'urgent';try{localStorage.setItem('crm_sheet_sort',_sheetSort);}catch(_){}curPage=1;renderTable();}
function sheetSetGroup(on){_sheetGroupEmp=!!on;try{localStorage.setItem('crm_sheet_grp',on?'1':'0');}catch(_){}curPage=1;renderTable();}
function _sheetSortList(list){
  const byName=(a,b)=>String(a.name||'').localeCompare(String(b.name||''));
  const byUrg=(a,b)=>{const da=_sheetMinDays(a),db=_sheetMinDays(b);if(da===null&&db===null)return byName(a,b);if(da===null)return 1;if(db===null)return -1;return da-db||byName(a,b);};
  const byEmp=(a,b)=>{const ea=a.employer_id?empN(a.employer_id):'￿',eb=b.employer_id?empN(b.employer_id):'￿';return ea.localeCompare(eb,'th');};
  const inner=_sheetSort==='urgent'?byUrg:(_sheetSort==='emp'?byName:null);
  if(_sheetGroupEmp||_sheetSort==='emp')list.sort((a,b)=>byEmp(a,b)||(inner?inner(a,b):0));
  else if(inner)list.sort(inner);
  return list;
}
function _sheetRow(c,no){
  const mD='<span class="sh-na">—</span>';
  return`<tr onclick="openDetail(${c.id})" id="row-${c.id}" class="sh-r sh-lv${_sheetLevel(c)} ${selectedIds.has(c.id)?'row-selected':''}">
      <td onclick="event.stopPropagation()"><input type="checkbox" class="row-check" data-id="${c.id}" ${selectedIds.has(c.id)?'checked':''} onchange="toggleRow(${c.id},this.checked)"></td>
      <td class="sh-no">${no}</td>
      <td onclick="event.stopPropagation()">${_sheetAv(c)}</td>
      <td class="sh-emp">${c.employer_id?esc(empN(c.employer_id)):mD}</td>
      <td><div class="ctbl-name">${esc(c.name)}</div>${c.name_th?`<div class="ctbl-sub">${esc(c.name_th)}</div>`:''}</td>
      <td><span class="nb ${NC[c.nationality]||'nb-ot'}" style="font-size:10px">${NF[c.nationality]||''} ${esc(c.nationality||'—')}</span></td>
      <td class="sh-ed" onclick="event.stopPropagation();sheetEditCat(this,${c.id})">${_sheetCatHtml(c.worker_category)}</td>
      <td class="sh-mono">${c.license_no?esc(c.license_no):mD}</td>
      <td>${_sheetDate(c.exp_wp,'wp')}</td>
      <td class="sh-mono">${c.passport_no?esc(c.passport_no):mD}</td>
      <td>${_sheetDate(c.exp_passport,'passport')}</td>
      <td>${_sheetDate(c.exp_visa,'visa')}</td>
      <td>${_sheetDate(c.next_90,'next90')}</td>
      <td class="sh-ed sh-txt" onclick="event.stopPropagation();sheetEditText(this,${c.id},'status_note')">${c.status_note?esc(c.status_note):'<span class="sh-add">+ สถานะ</span>'}</td>
      <td class="sh-ed sh-txt" onclick="event.stopPropagation();sheetEditText(this,${c.id},'work_items')">${c.work_items?esc(c.work_items):'<span class="sh-add">+ รายการ</span>'}</td>
      <td class="sh-ed sh-txt" onclick="event.stopPropagation();sheetEditText(this,${c.id},'note')">${c.note?esc(c.note):'<span class="sh-add">+</span>'}</td>
      <td onclick="event.stopPropagation()"><div style="display:flex;gap:3px"><button class="bic" onclick="openEdit(${c.id})">${uiIcon('edit')}</button><button class="bic" onclick="delCust(${c.id})" style="color:var(--red)">${uiIcon('trash')}</button></div></td>
    </tr>`;
}
function _sheetRenderTable(){
  _sheetUiInit();
  const all=customers||[];
  [['soon',1],['overdue',2],['nodate',-1]].forEach(([k,lv])=>{const el=document.getElementById('qvn-'+k);if(el){const n=all.filter(c=>_sheetLevel(c)===lv).length;el.textContent=n?String(n):'';}});
  const total=filtered.length;
  const rcnt=document.getElementById('rcnt');if(rcnt)rcnt.textContent=total;
  if(!total){document.getElementById('tbody').innerHTML='';renderCustomerCards([]);document.getElementById('emptyRow').style.display='block';document.getElementById('pag').innerHTML='';updateBulkBar();return;}
  document.getElementById('emptyRow').style.display='none';
  _sheetSortList(filtered);
  const s=(curPage-1)*PG,e=Math.min(s+PG,total);const page=filtered.slice(s,e);
  const empCnt={};if(_sheetGroupEmp)filtered.forEach(c=>{const k=c.employer_id||0;empCnt[k]=empCnt[k]||{n:0,w:0};empCnt[k].n++;if(_sheetLevel(c)>=1)empCnt[k].w++;});
  let prev=null;const out=[];
  page.forEach((c,i)=>{
    if(_sheetGroupEmp){const k=c.employer_id||0;if(k!==prev){prev=k;const st=empCnt[k]||{n:0,w:0};
      out.push(`<tr class="sh-grp"${k?` onclick="openEmpDet(${k})" title="เปิดหน้านายจ้าง"`:''}><td colspan="${_SHEET_HEAD.length}">🏢 ${k?esc(empN(k)):'ไม่มีนายจ้าง'}<span class="sh-gs">${st.n} คน${st.w?` · ต้องดู ${st.w} คน`:''}${k?' · กดเพื่อเปิดหน้านายจ้าง ›':''}</span></td></tr>`);}}
    out.push(_sheetRow(c,s+i+1));
  });
  document.getElementById('tbody').innerHTML=out.join('');
  renderCustomerCards(page);
  _bindCustPhotos();
  const pages=Math.ceil(total/PG);const ss=s+1,ee=e;
  document.getElementById('pag').innerHTML=`<span>${T('pagShow')} ${total?ss:0}–${ee} ${T('pagFrom')} ${total}</span><div class="pbtns"><button class="pb" onclick="goPage(${curPage-1})" ${curPage<=1?'disabled':''}>‹</button>${Array.from({length:Math.min(pages,5)},(_,i)=>{const p=Math.max(1,Math.min(curPage-2,pages-4))+i;return`<button class="pb ${p===curPage?'on':''}" onclick="goPage(${p})">${p}</button>`;}).join('')}<button class="pb" onclick="goPage(${curPage+1})" ${curPage>=pages?'disabled':''}>›</button></div>`;
  updateBulkBar();
}
// ── แก้ไขในช่อง (inline) — บันทึกผ่าน app_save_customer เดิม ──
function _sheetNeedCols(){if(_sheetColsOk===false){toast('ต้องรัน SQL 20261010 บน Supabase ก่อน จึงจะบันทึกช่องนี้ได้','err');return false;}return true;}
async function _sheetSave(id,patch){
  const c=(customers||[]).find(x=>x.id===id);if(!c)return false;
  const old={};Object.keys(patch).forEach(k=>{old[k]=c[k]==null?null:c[k];});
  const r=await _customerSaveRpc(id,patch);
  if(r.status==='ok'){Object.assign(c,patch);
    try{const ch={};Object.keys(patch).forEach(k=>{ch[k]={from:old[k],to:patch[k]};});logAudit('customer.update','customer',id,{name:c.name,passport_no:c.passport_no||c.alien_id||null,changed:Object.keys(patch),changes:ch,source:'sheetInline'});}catch(_){}
    return true;}
  toast(r.status==='unauthorized'?'ไม่มีสิทธิ์ กรุณาเข้าสู่ระบบใหม่':'บันทึกไม่สำเร็จ','err');return false;
}
function sheetEditText(td,id,field){
  if(field!=='note'&&!_sheetNeedCols())return;
  if(td.querySelector('textarea'))return;
  const c=(customers||[]).find(x=>x.id===id);if(!c)return;
  const cur=String(c[field]||'');
  td.innerHTML='<textarea class="sh-in" rows="2"></textarea>';const ta=td.firstChild;ta.value=cur;ta.focus();ta.select();
  let done=false;
  const fin=async save=>{if(done)return;done=true;const v=ta.value.trim();
    if(save&&v!==cur.trim()){td.innerHTML='<span class="sh-na">กำลังบันทึก…</span>';if(await _sheetSave(id,{[field]:v||null}))toast('บันทึกแล้ว');}
    renderTable();};
  ta.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();fin(true);}else if(e.key==='Escape'){e.preventDefault();fin(false);}});
  ta.addEventListener('blur',()=>fin(true));
}
function sheetEditCat(td,id){
  if(!_sheetNeedCols())return;
  if(td.querySelector('select'))return;
  const c=(customers||[]).find(x=>x.id===id);if(!c)return;
  const cur=c.worker_category||'';
  const opts=[...new Set(['MOU','มติ.ครม.',...(customers||[]).map(x=>x.worker_category).filter(Boolean)])];
  td.innerHTML=`<select class="sh-in"><option value="">— ไม่ระบุ —</option>${opts.map(o=>`<option value="${esc(o)}" ${o===cur?'selected':''}>${esc(o)}</option>`).join('')}<option value="__other__">อื่น ๆ (พิมพ์เอง)…</option></select>`;
  const sel=td.firstChild;sel.focus();
  let done=false;
  const fin=async v=>{if(done)return;done=true;if(v!==null&&v!==cur){if(await _sheetSave(id,{worker_category:v||null}))toast('บันทึกแล้ว');}renderTable();};
  sel.addEventListener('change',()=>{let v=sel.value;if(v==='__other__'){v=(prompt('ประเภท:','')||'').trim();if(!v){fin(null);return;}}fin(v);});
  sel.addEventListener('keydown',e=>{if(e.key==='Escape')fin(null);});
  sel.addEventListener('blur',()=>setTimeout(()=>fin(null),200));
}
// ── การ์ดมือถือ / หัวรายละเอียด ──
function _sheetCardChips(c){
  const ch=_SHEET_EXP.slice(0,4).map(([f,k,l])=>{const d=du(c[f]);return(d===null||isNaN(d))?'':`<span class="sh-chip ${_sheetChipCls(d,_sheetW(k))}">${l} ${_sheetDay(d)}</span>`;}).join('');
  return`<div class="cc-sh">${c.worker_category?_sheetCatHtml(c.worker_category):''}${c.status_note?`<span class="cc-stn">${esc(c.status_note)}</span>`:''}${ch}</div>`;
}
function _sheetDetChips(c){return`${c.worker_category?_sheetCatHtml(c.worker_category):''}${c.status_note?`<span class="cc-stn" style="font-size:12px">📌 ${esc(c.status_note)}</span>`:''}`;}

// =============================================================
// Stage EMP-HUB — หน้านายจ้างเป็นศูนย์รวม (เอกสารนายจ้าง + แรงงานเรียงตามความเร่งด่วน)
// =============================================================
const _EMP_DOC_TYPES=[['company_certificate','หนังสือรับรองบริษัท'],['employer_id_card','บัตรประชาชนนายจ้าง'],['house_registration','ทะเบียนบ้าน'],['employer_poa','หนังสือมอบอำนาจ'],['pp20','ภพ.20'],['commercial_registration','ใบทะเบียนพาณิชย์'],['workplace_photo','รูปสถานประกอบการ'],['map','แผนที่'],['other','อื่น ๆ']];
let _ehDocs=[],_ehEmpId=null,_ehErr='';
function _empHubHtml(e,empc){
  const lv=empc.map(_sheetLevel);const nOver=lv.filter(x=>x===2).length,nSoon=lv.filter(x=>x===1).length;
  const sorted=empc.slice().sort((a,b)=>{const da=_sheetMinDays(a),db=_sheetMinDays(b);if(da===null&&db===null)return String(a.name||'').localeCompare(String(b.name||''));if(da===null)return 1;if(db===null)return -1;return da-db;});
  const st=(n,l,cls)=>`<div class="eh-st ${cls}"><b>${n}</b><span>${l}</span></div>`;
  const sub=[e.business_type,e.contact_person,e.phone].filter(Boolean).map(esc).join(' · ');
  const rows=sorted.map(c=>`<tr class="sh-r sh-lv${_sheetLevel(c)}" onclick="document.getElementById('empDetModal').style.display='none';openDetail(${c.id})">
      <td onclick="event.stopPropagation()">${_sheetAv(c)}</td>
      <td><div class="ctbl-name">${esc(c.name)}</div>${c.name_th?`<div class="ctbl-sub">${esc(c.name_th)}</div>`:''}</td>
      <td>${c.worker_category?_sheetCatHtml(c.worker_category):'<span class="sh-na">—</span>'}</td>
      <td class="sh-mono">${c.license_no?esc(c.license_no):'<span class="sh-na">—</span>'}</td>
      <td>${_sheetDate(c.exp_wp,'wp')}</td><td>${_sheetDate(c.exp_passport,'passport')}</td><td>${_sheetDate(c.exp_visa,'visa')}</td><td>${_sheetDate(c.next_90,'next90')}</td>
      <td class="sh-txt">${c.status_note?esc(c.status_note):'<span class="sh-na">—</span>'}</td></tr>`).join('');
  return`<div class="eh-top"><div class="eh-ic">🏢</div><div style="flex:1;min-width:0"><div class="eh-name">${esc(e.name)}</div><div class="eh-sub">${sub||'—'}</div>${e.address?`<div class="eh-sub">${esc(e.address)}</div>`:''}</div></div>
  <div class="eh-stats">${st(empc.length,'แรงงานทั้งหมด','')}${st(nOver,'เลยกำหนด',nOver?'x':'')}${st(nSoon,'ใกล้หมดอายุ',nSoon?'w':'')}<div class="eh-st" id="ehDocStat"><b>…</b><span>เอกสารนายจ้าง</span></div></div>
  <div id="empShareSec"></div>
  <div class="eh-sec"><div class="eh-h">📎 เอกสารนายจ้าง / บริษัท <span class="eh-hint">กดวันหมดอายุเพื่อแก้ไข</span></div><div id="empDocHub"><div class="sh-na" style="padding:8px">กำลังโหลด…</div></div></div>
  <div class="eh-sec"><div class="eh-h">👷 แรงงาน (${empc.length}) <span class="eh-hint">เรียงจากใกล้หมดอายุก่อน · กดชื่อเพื่อดูวันหมดอายุและเอกสาร</span><button class="btn btn-p btn-sm" style="margin-left:auto" onclick="empHubAddWorker(${e.id})">+ เพิ่มแรงงาน</button></div>
    ${empc.length?`<div class="eh-tbl"><table class="sh-t"><thead><tr><th>รูป</th><th>ชื่อ</th><th>ประเภท</th><th>WORK</th><th>เวิร์คหมด</th><th>เล่มหมดอายุ</th><th>VISA หมด</th><th>90 วัน</th><th>สถานะ</th></tr></thead><tbody>${rows}</tbody></table></div>`:'<div class="sh-na" style="padding:14px;text-align:center">ยังไม่มีแรงงานของนายจ้างนี้</div>'}
  </div>
  <details class="eh-more"><summary>ข้อมูลนายจ้างเพิ่มเติม / สถานประกอบการ</summary><div id="empP2Sec"></div></details>`;
}
function empHubAddWorker(empId){
  const m=document.getElementById('empDetModal');if(m)m.style.display='none';
  openAdd();const rc=document.getElementById('r_comp');if(rc){rc.checked=true;ctChange();}
  const s=document.getElementById('f_empId');if(s)s.value=String(empId);
}
async function _loadEmpDocHub(empId){
  _ehEmpId=empId;_ehErr='';
  let docs=[];
  try{docs=await _delReqRpc('app_list_documents',{p_owner_type:'employer',p_owner_id:Number(empId),p_limit:100,p_offset:0});}
  catch(e){_ehErr=(e&&e.message)||'error';}
  if(_ehEmpId!==empId)return;
  _ehDocs=Array.isArray(docs)?docs:[];
  _renderEmpDocHub();
  try{const ids=(customers||[]).filter(c=>c.employer_id===empId&&!c.photo&&(c._hasPhoto||c.photo_storage_path)).map(c=>c.id);if(ids.length)_fetchCustPhotos(ids);}catch(_){}
}
function _renderEmpDocHub(){
  const box=document.getElementById('empDocHub');if(!box)return;
  const docs=_ehDocs.slice().sort((a,b)=>{const x=a.doc_expiry||'9999',y=b.doc_expiry||'9999';return x<y?-1:x>y?1:0;});
  const near=docs.filter(d=>{const x=du(d.doc_expiry);return x!==null&&x<=30;}).length;
  const st=document.getElementById('ehDocStat');
  if(st){st.className='eh-st'+(near?' w':'');st.innerHTML=`<b>${docs.length}</b><span>เอกสารนายจ้าง${near?` · ใกล้หมด ${near}`:''}</span>`;}
  const rows=docs.map(d=>{const x=du(d.doc_expiry);const isPdf=/pdf/i.test(d.mime_type||d.file_type||'');
    return`<div class="eh-doc"><div class="eh-doc-ic">${isPdf?'📄':'🖼️'}</div>
      <div style="flex:1;min-width:0"><div class="eh-doc-n">${esc(d.doc_name||_dcDocTypeLabel(d.doc_type))}</div><div class="eh-doc-s">${esc(_dcDocTypeLabel(d.doc_type))} · อัปโหลด ${fd(d.created_at)}${d.uploaded_by?' · '+esc(d.uploaded_by):''}</div></div>
      <div class="eh-doc-x" onclick="ehEditExp('${esc(String(d.id))}',this)" title="แก้วันหมดอายุ">${d.doc_expiry?`<div class="sh-d">หมด ${fd(d.doc_expiry)}</div><span class="sh-chip ${_sheetChipCls(x,30)}">${_sheetDay(x)}</span>`:'<span class="sh-add">+ วันหมดอายุ</span>'}</div>
      <button class="btn btn-g btn-sm" onclick="dcOpenDoc('${esc(String(d.id))}',${!!d.has_storage})">เปิดดู</button></div>`;}).join('');
  box.innerHTML=(_ehErr?`<div class="eh-err">โหลดเอกสารไม่สำเร็จ: ${esc(_ehErr)}</div>`:'')
    +(rows||'<div class="sh-na" style="padding:4px 0 6px">ยังไม่มีเอกสารนายจ้าง — อัปโหลดด้านล่างได้เลย</div>')
    +`<div class="eh-up"><label class="eh-lbl">ประเภทเอกสาร<select id="ehType" class="fi2">${_EMP_DOC_TYPES.map(([k,l])=>`<option value="${k}">${l}</option>`).join('')}</select></label>
      <label class="eh-lbl">วันหมดอายุ (ถ้ามี)<input type="date" id="ehExp" class="fi2"></label>
      <label class="btn btn-g btn-sm" style="cursor:pointer">เลือกไฟล์ PDF / รูป…<input type="file" id="ehFile" accept="image/*,.pdf" multiple style="display:none" onchange="ehPick(this)"></label>
      <span id="ehFileN" class="eh-hint"></span>
      <button class="btn btn-p btn-sm" id="ehGo" onclick="ehUpload()">อัปโหลด</button></div>`;
}
function ehPick(inp){const n=document.getElementById('ehFileN');if(n)n.textContent=inp.files&&inp.files.length?(inp.files.length===1?inp.files[0].name:inp.files.length+' ไฟล์'):'';}
async function _callEmpDocUpload({employer_id,doc_type,doc_name,file_name,file_type,data_url,doc_expiry}){
  const res=await fetch(CUST_DOC_UPLOAD_URL,{method:'POST',mode:'cors',
    headers:{'apikey':SB_KEY,'Authorization':`Bearer ${SB_KEY}`,'Content-Type':'application/json'},
    body:JSON.stringify({user_id:curUser&&curUser.id!=null?String(curUser.id):'',username:curUser&&curUser.username||'',owner_type:'employer',owner_id:employer_id,doc_type,doc_name,file_name:file_name||doc_name,file_type,file_size:data_url?approxBytesFromDataURL(data_url):0,data_url,doc_expiry:doc_expiry||null})});
  return await res.json();
}
function _ehErrMsg(code){return({owner_type_not_supported:'ต้องอัปเดตฟังก์ชัน customer-doc-upload บน Supabase ก่อน',invalid_doc_type:'ต้องอัปเดตฟังก์ชัน customer-doc-upload บน Supabase ก่อน',db_error:'บันทึกไม่ได้ — ต้องรัน SQL 20261010 ก่อน',employer_not_found:'ไม่พบนายจ้างในระบบ',invalid_doc_expiry:'วันหมดอายุไม่ถูกต้อง',unauthorized:'กรุณาเข้าสู่ระบบใหม่',pdf_too_large:'PDF ใหญ่เกิน 10MB',image_too_large:'รูปใหญ่เกินไป'})[code]||code;}
async function ehUpload(){
  const f=document.getElementById('ehFile');const files=f&&f.files?[...f.files]:[];
  if(!files.length){toast('กรุณาเลือกไฟล์ก่อน','err');return;}
  if(_ehEmpId==null)return;
  if(!(await guardSession()))return;
  const type=document.getElementById('ehType').value||'other';
  const label=(_EMP_DOC_TYPES.find(x=>x[0]===type)||[0,'เอกสารนายจ้าง'])[1];
  const exp=_ceDate(document.getElementById('ehExp').value||'')||null;
  const btn=document.getElementById('ehGo');if(btn)btn.disabled=true;
  showLoading('กำลังอัปโหลดเอกสารนายจ้าง...');
  let ok=0,fail=0,last='';
  try{for(const file of files){try{const p=await _bulkPrepare(file);
      const r=await _callEmpDocUpload({employer_id:_ehEmpId,doc_type:type,doc_name:files.length>1?(label+' — '+file.name):label,file_name:file.name,file_type:p.type,data_url:p.data,doc_expiry:exp});
      if(!r||!r.ok)throw new Error(r&&r.error||'upload_failed');ok++;}catch(e){fail++;last=(e&&e.message)||'error';}}}
  finally{hideLoading();}
  if(ok){try{logAudit('document.upload','employer',_ehEmpId,{count:ok,failed:fail,doc_type:type,doc_expiry:exp,source:'empDocHub'});}catch(_){}}
  toast(fail?('อัปโหลดไม่สำเร็จ '+fail+' ไฟล์: '+_ehErrMsg(last)):('อัปโหลดแล้ว '+ok+' ไฟล์'),fail?'err':undefined);
  await _loadEmpDocHub(_ehEmpId);
}
function ehEditExp(id,el){
  if(el.querySelector('input'))return;
  const d=_ehDocs.find(x=>String(x.id)===String(id));if(!d)return;
  el.onclick=null;
  el.innerHTML=`<input type="date" class="sh-in" style="min-width:130px" value="${esc(d.doc_expiry||'')}"><div style="display:flex;gap:4px;margin-top:4px;justify-content:flex-end"><button class="btn btn-p btn-sm btn-xs">บันทึก</button><button class="btn btn-g btn-sm btn-xs">ยกเลิก</button></div>`;
  const inp=el.querySelector('input');const [bOk,bNo]=el.querySelectorAll('button');inp.focus();
  let done=false;
  const fin=async save=>{if(done)return;done=true;
    const v=_ceDate(inp.value||'')||null;
    if(save&&v!==(d.doc_expiry||null)){
      try{await _delReqRpc('app_update_document_metadata',{p_document_id:String(d.id),p_doc_name:d.doc_name||null,p_doc_type:d.doc_type||null,p_source:d.source||null,p_doc_expiry:v,p_doc_status:null,p_doc_note:null});
        d.doc_expiry=v;toast('บันทึกวันหมดอายุแล้ว');try{logAudit('document.update','document',d.id,{doc_expiry:v,source:'empDocHub'});}catch(_){}}
      catch(e){toast('บันทึกไม่สำเร็จ: '+((e&&e.message)||''),'err');}}
    _renderEmpDocHub();};
  bOk.onclick=ev=>{ev.stopPropagation();fin(true);};bNo.onclick=ev=>{ev.stopPropagation();fin(false);};
  inp.addEventListener('click',ev=>ev.stopPropagation());
  inp.addEventListener('keydown',ev=>{if(ev.key==='Enter')fin(true);else if(ev.key==='Escape')fin(false);});
}
'''

F_WCAT = ('<div class="fgi sw-only"><label class="fl">ประเภท</label><input class="fi2" id="f_wcat" list="wcatList" placeholder="MOU / มติ.ครม.">'
          '<datalist id="wcatList"><option value="MOU"><option value="มติ.ครม."></datalist></div>')
F_SEC = ('<div class="fsec sw-only"><div class="fst">สถานะ / รายการ</div><div class="fg">'
         '<div class="fgi full"><label class="fl">สถานะ (เขียนเองได้ เช่น ถ่ายบัตรแล้ว)</label><input class="fi2" id="f_stnote" placeholder="เช่น ถ่ายบัตรแล้ว / รอเล่ม"></div>'
         '<div class="fgi full"><label class="fl">รายการ</label><input class="fi2" id="f_items" placeholder="เช่น ต่อวีซ่า + เวิร์ค"></div>'
         '</div></div>')


def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:80]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage S1-SIMPLE' not in s:
        sys.exit(f'{path}: ต้องมี Stage S1-SIMPLE ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    # CSS: ยกเลิกการซ่อนคอลัมน์แบบ index ของ S1 (หัวตารางใหม่) + เพิ่มสไตล์ชีส
    s = rep(s, OLD_S1_COLS, '', path)
    s = rep(s, '<style id="hideCaseModule">', CSS.replace('\n', nl) + nl + '<style id="hideCaseModule">', path)
    # โหลดลูกค้า: ลองดึง 3 ช่องใหม่ก่อน → ไม่ได้ (ยังไม่รัน SQL) ใช้ชุดเดิม
    a = "const CUST_LIST_COLS='"
    i = s.index(a); j = s.index('\n', i) + 1
    s = s[:j] + COLS_DEF.replace('\n', nl) + s[j:]
    s = rep(s, "(async()=>{try{return await dbGet('customers','?deleted_at=is.null&order=created_at.desc.nullslast,id.desc&limit=2000&select='+CUST_LIST_COLS);}",
            "(async()=>{if(_sheetColsOk!==false){try{const _sr=await dbGet('customers','?deleted_at=is.null&order=created_at.desc.nullslast,id.desc&limit=2000&select='+CUST_LIST_COLS+SHEET_COLS);_sheetColsOk=true;return _sr;}catch(_){_sheetColsOk=false;}}try{return await dbGet('customers','?deleted_at=is.null&order=created_at.desc.nullslast,id.desc&limit=2000&select='+CUST_LIST_COLS);}", path)
    # หัวตาราง: ไม่ให้ setLang ทับหัวคอลัมน์แบบชีส
    s = rep(s, 'ths.forEach((th,i)=>{if(hmap[i]!==undefined)th.textContent=hmap[i];});',
            'if(!SIMPLE_WORKER_MODE)ths.forEach((th,i)=>{if(hmap[i]!==undefined)th.textContent=hmap[i];});', path)
    # ตัวกรอง/ค้นหา
    s = rep(s, 'const mq=!q||[c.name,', 'const mq=!q||[c.license_no,c.status_note,c.work_items,c.worker_category,c.name,', path)
    s = rep(s, "const mqv=customerQuickView==='pending'?",
            "const _sq=SIMPLE_WORKER_MODE?_sheetQv(c,customerQuickView):null;const mqv=_sq!==null?_sq:customerQuickView==='pending'?", path)
    s = rep(s, "&&(!asg||String(c.assignee_code||'')===String(asg))&&mqv;",
            "&&(!asg||String(c.assignee_code||'')===String(asg))&&mqv&&(!SIMPLE_WORKER_MODE||_sheetFilterOk(c));", path)
    s = rep(s, "['all','pending','submitted','unpaid'].forEach(k=>{",
            "['all','pending','submitted','unpaid','soon','overdue','nodate'].forEach(k=>{", path)
    # ตาราง + การ์ดมือถือ
    s = rep(s, 'function renderTable(){', JS.replace('\n', nl) + 'function renderTable(){if(SIMPLE_WORKER_MODE)return _sheetRenderTable();', path)
    s = rep(s, '${payBadge}${svcs}${ex}${expChips}', '${SIMPLE_WORKER_MODE?_sheetCardChips(c):payBadge+svcs+ex+expChips}', path)
    s = rep(s, '<span class="${wsC(c.work_status)} cc-st">${wsT(c.work_status||\'รับเรื่อง\')}</span>',
            '${SIMPLE_WORKER_MODE?\'\':`<span class="${wsC(c.work_status)} cc-st">${wsT(c.work_status||\'รับเรื่อง\')}</span>`}', path)
    # หัวรายละเอียดลูกค้า
    a = "<span class=\"${c.customer_type==='company'?'ct-comp':'ct-free'}\">${c.customer_type==='company'?T('detCustComp'):T('detCustFree')}</span>"
    s = rep(s, a, "${SIMPLE_WORKER_MODE?_sheetDetChips(c):`" + a + "`}", path)
    a = "<span class=\"${wsC(c.work_status)}\">${wsT(c.work_status||'รับเรื่อง')}</span>"
    s = rep(s, a, "${SIMPLE_WORKER_MODE?'':`" + a + "`}", path)
    a = "<div class=\"df\"><div class=\"dfl\">${T('detPassport')}</div>"
    s = rep(s, a, "${SIMPLE_WORKER_MODE?`<div class=\"df\"><div class=\"dfl\">WORK (ใบอนุญาตทำงาน)</div><div class=\"dfv\" style=\"font-family:var(--mono);font-size:12px\">${esc(c.license_no||'—')}</div></div><div class=\"df\"><div class=\"dfl\">รายการ</div><div class=\"dfv\">${esc(c.work_items||'—')}</div></div>`:''}" + a, path)
    # ฟอร์มลูกค้า: ประเภท / สถานะ / รายการ
    a = '<option value="เวียดนาม">🇻🇳 เวียดนาม</option></select></div>'
    s = rep(s, a, a + F_WCAT, path)
    s = rep(s, '<div class="fsec" id="staffSec">', F_SEC + nl + '      <div class="fsec" id="staffSec">', path)
    s = rep(s, "['name','nameTh','pp','alien','phone','emp',", "['wcat','stnote','items','name','nameTh','pp','alien','phone','emp',", path)
    s = rep(s, "sv('wpn',c.wp_no);", "sv('wcat',c.worker_category);sv('stnote',c.status_note);sv('items',c.work_items);sv('wpn',c.wp_no);", path)
    s = rep(s, '_ceObj(data); // Stage DATE-BE-FIX',
            "_ceObj(data); // Stage DATE-BE-FIX" + nl +
            "    if(SIMPLE_WORKER_MODE&&_sheetColsOk!==false){data.worker_category=VT('f_wcat')||null;data.status_note=VT('f_stnote')||null;data.work_items=VT('f_items')||null;} // Stage SHEET-VIEW", path)
    # นำเข้า: ประเภท / สถานะ(ข้อความ) / รายการ
    s = rep(s, "{key:'services',label:'รายการ',aliases:['รายการ','บริการ','services']},",
            "{key:'services',label:'บริการ',aliases:['บริการ','services']}," + nl +
            "  {key:'work_items',label:'รายการ',aliases:['รายการ','ราคาต่ออายุ','work_items']}," + nl +
            "  {key:'worker_category',label:'ประเภท',aliases:['ประเภท','ประเภทแรงงาน','worker_category']},", path)
    s = rep(s, "{key:'work_status',label:'สถานะ',aliases:['สถานะ','สถานะงาน','work_status']},",
            "{key:'work_status',label:'สถานะงาน',aliases:['สถานะงาน','work_status']}," + nl +
            "  {key:'status_note',label:'สถานะ',aliases:['สถานะ','status_note']},", path)
    s = rep(s, "const _svc=get(row,'services');",
            "{const _wc=String(get(row,'worker_category')||'').trim();if(_wc&&_wc!=='-'&&_wc!=='ประเภท')data.worker_category=/^mou$/i.test(_wc)?'MOU':(/มติ|ครม/.test(_wc)?'มติ.ครม.':_wc);"
            "const _sn=_impStatus(get(row,'status_note'));if(_sn)data.status_note=_sn;const _wi=_impClean(get(row,'work_items'));if(_wi)data.work_items=_wi;} // Stage SHEET-VIEW" + nl +
            "      const _svc=get(row,'services');", path)
    # หน้านายจ้าง = ศูนย์รวม
    s = rep(s, 'const html=`<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px',
            'const html=SIMPLE_WORKER_MODE?_empHubHtml(e,empc):`<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px', path)
    s = rep(s, 'try{_loadEmpShare(id);}catch(_e){} // Stage SHARE-001',
            'try{_loadEmpShare(id);}catch(_e){} // Stage SHARE-001' + nl +
            '  if(SIMPLE_WORKER_MODE){try{_loadEmpDocHub(id);}catch(_e){}} // Stage EMP-HUB', path)
    s = rep(s, '<div id="empDocSec"></div>', "${SIMPLE_WORKER_MODE?'':'<div id=\"empDocSec\"></div>'}", path)
    i = s.index("📎 ${T('emp2Docs')}")
    a0 = s.rindex('<div ', 0, i); a1 = s.index('</div>', i) + len('</div>')
    s = s[:a0] + "${SIMPLE_WORKER_MODE?'':`" + s[a0:a1] + "`}" + s[a1:]
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

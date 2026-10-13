# Stage S2-FORM-DOCS-IMPORT (ต่อจาก SHEET-VIEW)
#  1) ซ่อน สาขา / ผู้รับผิดชอบ (ฟอร์ม + ตัวกรอง + งานของฉัน + มอบหมายแบบกลุ่ม) — ข้อมูลเดิมยังอยู่
#  2) ย้าย "เลขคำขอ" + "ใบอนุญาตเลขที่" ไปไว้ต่อจากเลขพาสปอร์ต (แท็บข้อมูลพื้นฐาน), ซ่อนเลขคำขอ VISA,
#     ซ่อนแท็บ "เลขเอกสาร" (ไม่มีอะไรเหลือ)
#  3) แก้หัวข้อ "เจ้าหน้าที่รับผิดชอบ" ไปทับหัวข้อ "สถานะ / รายการ" (setLang นับ index ของ .fst)
#  4) อัปโหลดเอกสารแรงงาน: กด "+ เพิ่มไฟล์" ก่อน → แต่ละไฟล์มีช่องตั้งชื่อ (มีคำแนะนำ) ระบบเดาประเภทจากชื่อให้
#     เพิ่มประเภท: ใบรับรองแพทย์ ประกันสุขภาพ ใบอัตลักษณ์ CI ใบรับแจ้ง 90 วัน สัญญาจ้าง ฯลฯ
#     (ต้อง deploy customer-doc-upload เวอร์ชันที่รับประเภทใหม่)
#  5) นำเข้า/วางชีส: ติ๊ก "อัปเดตข้อมูลคนเดิม" → คนที่มีอยู่แล้วถูกอัปเดตเฉพาะช่องที่ชีสมีค่าและค่าไม่ตรงกัน
import sys, re

MARK = 'Stage S2-FORM-DOCS-IMPORT'

CSS = ('<style id="s2FormDocs">/* ' + MARK + ' */'
       'html.simple-worker .fgi:has(#f_branch),html.simple-worker .fgi:has(#f_assignee),'
       'html.simple-worker #qbr,html.simple-worker #qassignee,html.simple-worker #niMyWork,html.simple-worker #drawerMyWork,'
       'html.simple-worker #bulkAsgWrap,html.simple-worker #bulkSelfBtn{display:none!important}'
       'html.simple-worker #cModal .tbar3 .tbtn:nth-child(2){display:none!important}'
       'html.simple-worker #newDocType,html.simple-worker #newDocLabel{display:none!important}'
       '.mdoc-name{width:100%;box-sizing:border-box;font:inherit;font-size:12px;font-weight:600;padding:4px 6px;border:1px solid var(--g3);border-radius:6px;background:#fff;margin-top:2px}'
       '.mdoc-name:focus{outline:none;border-color:#3b82f6}'
       '.mdoc-hint{font-size:11.5px;color:var(--g5);align-self:center}'
       '</style>')

JS_AFTER_FLAG = r'''// ── Stage S2: ย้ายเลขคำขอ / ใบอนุญาตเลขที่ ไปต่อจากเลขพาสปอร์ต · ซ่อนเลขคำขอ VISA ──
function _swMoveDocNo(){
  if(!SIMPLE_WORKER_MODE)return;
  const pp=document.getElementById('f_pp');const ppg=pp&&pp.closest('.fgi');if(!ppg)return;
  const mv=(id,lbl,ph)=>{const el=document.getElementById(id);const g=el&&el.closest('.fgi');if(!g)return null;const l=g.querySelector('.fl');if(l)l.textContent=lbl;if(ph)el.placeholder=ph;return g;};
  const a=mv('f_wpn','เลขคำขอ','เช่น WP-68-XXXXXX');const b=mv('f_licn','ใบอนุญาตเลขที่','เลขใบอนุญาตทำงาน (WORK)');
  if(b)ppg.after(b);if(a)ppg.after(a);
  const v=document.getElementById('f_visn');const vg=v&&v.closest('.fgi');if(vg)vg.style.display='none';
}
try{_swMoveDocNo();}catch(_e){console.warn('[S2] move doc fields',_e);}
'''

DOC_JS = r'''// ── Stage S2: เดาประเภทเอกสารจากชื่อ (ชื่อไฟล์ หรือชื่อที่ตั้งเอง) ──
const _DOC_GUESS=[
  [/ใบอัตลักษณ์|อัตลักษณ์|identity|บัตรชมพู|pink/i,'identity_card','ใบอัตลักษณ์'],
  [/แพทย์|แพท|medical|med[\s_.-]?cert/i,'medical','ใบรับรองแพทย์'],
  [/ประกัน|insurance/i,'insurance','ประกันสุขภาพ'],
  [/สัญญา|contract/i,'contract','สัญญาจ้าง'],
  [/มอบอำนาจ|(^|[^a-z])poa([^a-z]|$)|power.?of.?attorney/i,'pow','หนังสือมอบอำนาจ'],
  [/ใบเสร็จ|receipt/i,'receipt','ใบเสร็จ'],
  [/ตม\.?\s?47|tm\.?\s?47|(^|[^0-9])90\s?(วัน|day)|รายงานตัว/i,'tm47','ใบรับแจ้ง 90 วัน'],
  [/(^|[^a-z])ci([^a-z]|$)|certificate.?of.?identity/i,'ci','CI'],
  [/visa|วีซ่า|วีซา/i,'visa','วีซ่า'],
  [/(^|[^a-z])wp([^a-z]|$)|work.?permit|เวิร์ค|เวิค|ใบอนุญาต/i,'wp','ใบอนุญาตทำงาน'],
  [/passport|พาสปอร์ต|พาสปอต|หนังสือเดินทาง|(^|[^a-z])pp([^a-z]|$)/i,'passport','พาสปอร์ต'],
  [/รูปถ่าย|รูปหน้าตรง|(^|[^a-z])photo([^a-z]|$)/i,'photo','รูปถ่าย'],
];
function _docGuess(s){s=String(s||'');for(const [re,t,l] of _DOC_GUESS){if(re.test(s))return{type:t,label:l};}return null;}
const _DOC_NAME_SUGGEST=['พาสปอร์ต','วีซ่า','ใบอนุญาตทำงาน','ใบรับรองแพทย์','ประกันสุขภาพ','ใบอัตลักษณ์','CI','ใบรับแจ้ง 90 วัน','สัญญาจ้าง','หนังสือมอบอำนาจ','รูปถ่าย','ใบเสร็จ'];
function mdocRename(id,v){const d=(multiDocs||[]).find(x=>x.id===id);if(!d)return;d.label=String(v||'').trim();const g=_docGuess(d.label);d.type=g?g.type:'other';}
'''

IMP_JS = r'''// ── Stage S2: นำเข้าซ้ำ → อัปเดตคนเดิม (เฉพาะช่องที่ชีสมีค่า และค่าไม่ตรงกับในระบบ) ──
const _IMP_UPD_LBL={exp_wp:'เวิร์คหมด',exp_passport:'เล่มหมดอายุ',exp_visa:'VISA',next_90:'90 วัน',exp_mou:'MOU',license_no:'WORK',wp_no:'เลขคำขอ',passport_no:'PASSPORT',worker_category:'ประเภท',status_note:'สถานะ',work_items:'รายการ',note:'หมายเหตุ',phone:'เบอร์',employer_id:'นายจ้าง'};
function _impBuildUpdate(row,get,c){
  const P={};
  const cur=k=>{const v=c[k];if(v==null)return'';return(/^exp_|^next_90$/.test(k))?String(_ceDate(String(v).slice(0,10))):String(v);};
  const set=(k,v)=>{if(v==null||v==='')return;if(String(v)!==cur(k))P[k]=v;};
  const d=k=>{if(impMap[k]===undefined)return null;const r=get(row,k);return r?(impDate(r)||null):null;};
  ['exp_wp','exp_passport','exp_visa','next_90','exp_mou'].forEach(k=>set(k,d(k)));
  ['license_no','wp_no','passport_no','work_items','note','phone'].forEach(k=>set(k,_impClean(get(row,k))));
  const wc=String(get(row,'worker_category')||'').trim();
  if(wc&&wc!=='-'&&wc!=='ประเภท')set('worker_category',/^mou$/i.test(wc)?'MOU':(/มติ|ครม/.test(wc)?'มติ.ครม.':wc));
  set('status_note',_impStatus(get(row,'status_note')));
  const en=get(row,'employer_name');
  if(en){const _en=normalizeEmployerName(en);const ef=employers.find(x=>normalizeEmployerName(x.name)===_en);if(ef&&ef.id!==c.employer_id){P.employer_id=ef.id;P.customer_type='company';}}
  if(typeof _sheetColsOk!=='undefined'&&_sheetColsOk===false){delete P.worker_category;delete P.status_note;delete P.work_items;}
  const keys=Object.keys(P).filter(k=>k!=='customer_type');
  return keys.length?{patch:P,labels:keys.map(k=>_IMP_UPD_LBL[k]||k)}:null;
}
'''

UPD_DUP = (r"""const _exC=existingByKey.get(key);const _notes=[];"""
           r"""if(_exC&&_impUpdEx){const _up=_impBuildUpdate(row,get,_exC);if(_up){const _ur=await _bulkUpdateCustomersRpc([_exC.id],_up.patch);"""
           r"""if(_ur.status==='unauthorized'){hideLoading();toast('ไม่มีสิทธิ์นำเข้าข้อมูล กรุณาเข้าสู่ระบบใหม่','err');return;}"""
           r"""if(_ur.status==='ok'){Object.assign(_exC,_up.patch);countExUpd++;_notes.push('อัปเดต: '+_up.labels.join(', '));"""
           r"""try{logAudit('customer.update','customer',_exC.id,{name:_exC.name,passport_no:_exC.passport_no||_exC.alien_id||null,changed:Object.keys(_up.patch),source:'importUpdate'});}catch(_){}}"""
           r"""else _notes.push('อัปเดตไม่สำเร็จ');}} // Stage S2""")


def rep(s, old, new, path, cnt=1):
    n = s.count(old)
    if n != cnt:
        sys.exit(f'{path}: anchor count {n} != {cnt} for: {old[:80]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHEET-VIEW' not in s:
        sys.exit(f'{path}: ต้องมี Stage SHEET-VIEW ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = rep(s, '<style id="hideCaseModule">', CSS + nl + '<style id="hideCaseModule">', path)
    a = "if(SIMPLE_WORKER_MODE)document.documentElement.classList.add('simple-worker');"
    i = s.index(a); j = s.index('\n', i) + 1
    s = s[:j] + JS_AFTER_FLAG.replace('\n', nl) + s[j:]
    # หัวข้อ section: ข้าม .sw-only (กัน "เจ้าหน้าที่รับผิดชอบ" ไปทับ "สถานะ / รายการ")
    s = rep(s, "const fsts=document.querySelectorAll('#cModal .fst');",
            "const fsts=[...document.querySelectorAll('#cModal .fst')].filter(e=>!e.closest('.sw-only'));", path)
    # ── เอกสารแรงงาน ──
    s = rep(s, "const _DOC_TYPE_LABELS={passport_photo:'รูปพาสปอร์ต',visa:'VISA',wp:'Work Permit',employer_card:'บัตรนายจ้าง',receipt:'ใบเสร็จ',photo:'รูปถ่าย',pow:'หนังสือมอบอำนาจ',other:'อื่นๆ'};",
            "const _DOC_TYPE_LABELS={passport_photo:'รูปพาสปอร์ต',visa:'VISA',wp:'Work Permit',employer_card:'บัตรนายจ้าง',receipt:'ใบเสร็จ',photo:'รูปถ่าย',pow:'หนังสือมอบอำนาจ',other:'อื่นๆ',"
            "passport:'พาสปอร์ต',ci:'CI',work_permit:'ใบอนุญาตทำงาน',medical:'ใบรับรองแพทย์',insurance:'ประกันสุขภาพ',identity_card:'ใบอัตลักษณ์',tm47:'ใบรับแจ้ง 90 วัน',contract:'สัญญาจ้าง',profile_photo:'รูปถ่ายแรงงาน'}; // Stage S2"
            + nl + DOC_JS.replace('\n', nl), path)
    s = rep(s, "requested_extra_doc:'เอกสารที่เจ้าหน้าที่ขอเพิ่ม',",
            "requested_extra_doc:'เอกสารที่เจ้าหน้าที่ขอเพิ่ม',identity_card:'ใบอัตลักษณ์',tm47:'ใบรับแจ้ง 90 วัน',contract:'สัญญาจ้าง',", path)
    s = rep(s, '<button class="btn btn-p btn-sm" onclick="triggerMultiDoc()">+ เพิ่มไฟล์</button>',
            '<button class="btn btn-p btn-sm" onclick="triggerMultiDoc()">+ เพิ่มไฟล์</button>'
            '<span class="mdoc-hint sw-only">เลือกได้หลายไฟล์พร้อมกัน แล้วพิมพ์ชื่อเอกสารใต้แต่ละไฟล์ได้เลย (เช่น ใบรับรองแพทย์ ประกันสุขภาพ ใบอัตลักษณ์)</span>'
            '<datalist id="docNameList">' + ''.join(f'<option value="{x}">' for x in ['พาสปอร์ต','วีซ่า','ใบอนุญาตทำงาน','ใบรับรองแพทย์','ประกันสุขภาพ','ใบอัตลักษณ์','CI','ใบรับแจ้ง 90 วัน','สัญญาจ้าง','หนังสือมอบอำนาจ','รูปถ่าย','ใบเสร็จ']) + '</datalist>', path)
    s = rep(s, "multiDocs.push({id:'doc_'+Date.now()+'_'+Math.random().toString(36).substr(2,5),type,label:customLabel||typeLabel,",
            "const _g2=SIMPLE_WORKER_MODE?_docGuess(file.name):null;" + nl +
            "      multiDocs.push({id:'doc_'+Date.now()+'_'+Math.random().toString(36).substr(2,5),type:SIMPLE_WORKER_MODE?(_g2?_g2.type:'other'):type,label:SIMPLE_WORKER_MODE?(_g2?_g2.label:String(file.name||'เอกสาร').replace(/\\.[^.]+$/,'').slice(0,80)):(customLabel||typeLabel),", path)
    i = s.index('function renderMultiDocGrid(){')
    a = '<div class="mdoc-label">${safeLabel}</div>'
    k = s.index(a, i)
    s = s[:k] + ("${(SIMPLE_WORKER_MODE&&!doc.dbId)?`<input class=\"mdoc-name\" list=\"docNameList\" value=\"${esc(doc.label||'')}\" placeholder=\"ตั้งชื่อเอกสาร\" "
                 "oninput=\"mdocRename('${doc.id}',this.value)\" onclick=\"event.stopPropagation()\">`:`" + a + "`}") + s[k + len(a):]
    s = rep(s, "doc_type:doc.type,doc_name:doc.label,file_name:", "doc_type:doc.type,doc_name:doc.label||docTypeLabel(doc.type),file_name:", path)
    # ── นำเข้าซ้ำ → อัปเดตคนเดิม ──
    s = rep(s, 'async function doImport(){', IMP_JS.replace('\n', nl) + 'async function doImport(){', path)
    s = rep(s, "showLoading(`กำลังนำเข้าข้อมูล ${impData.length} แถว...`);",
            "showLoading(`กำลังนำเข้าข้อมูล ${impData.length} แถว...`);const _impUpdEx=!!(document.getElementById('impUpdEx')&&document.getElementById('impUpdEx').checked); // Stage S2", path)
    s = rep(s, 'let countAsgUpd=0;', 'let countAsgUpd=0;let countExUpd=0;', path)
    s = rep(s, 'const _exC=existingByKey.get(key);const _notes=[];', UPD_DUP, path)
    s = rep(s, '<button class="btn btn-p btn-sm" onclick="doImport()">✅ นำเข้า ${cntNew} รายการ</button>',
            "${cntDupEx>0?`<label style=\"font-size:12px;display:inline-flex;gap:5px;align-items:center;margin-right:8px;cursor:pointer;color:#92400e\"><input type=\"checkbox\" id=\"impUpdEx\" checked>อัปเดตข้อมูลคนเดิม ${cntDupEx} คน ตามไฟล์นี้</label>`:''}"
            '<button class="btn btn-p btn-sm" onclick="doImport()">✅ นำเข้า ${cntNew} รายการ${cntDupEx>0?\' + อัปเดตคนเดิม\':\'\'}</button>', path)
    s = rep(s, 'ซ้ำข้อมูลเดิม<br><strong style="font-size:20px;color:#d97706">${countDupEx}</strong>',
            'ซ้ำข้อมูลเดิม<br><strong style="font-size:20px;color:#d97706">${countDupEx}</strong>${countExUpd?`<div style="font-size:11px;color:#16a34a;margin-top:2px">อัปเดตแล้ว ${countExUpd} คน</div>`:\'\'}', path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

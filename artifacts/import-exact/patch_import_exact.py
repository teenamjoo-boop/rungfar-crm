# Stage IMPORT-EXACT: รับ Excel แบบ "หัวเป็นชื่อนายจ้าง + ตารางแรงงาน" ได้ครบ
#  - ชื่อนายจ้างจากแถวหัวเรื่อง (เช่น "หจก.สยามอิเล็กทริค") → ช่อง "นายจ้างของทุกคนในไฟล์" (แก้/เลือกได้)
#  - คอลัมน์ใหม่: วันเกิด (dob), Email (เก็บในหมายเหตุ)
#  - alias เพิ่ม: วันหมดอยุ/อายุใบอนุญาตทำงาน → วันหมด WP, ใบอนุญาตทำงานเลขที่ → เลขใบอนุญาตทำงาน
#  - ข้อความในช่องวันที่ที่ไม่ใช่วันที่ (เช่น "รอถ่ายบัตรวันที่ 2/12/69", "รอPass") → ไม่เดาเป็นวันที่ แต่เก็บข้อความไว้ในหมายเหตุ
import sys,io
path=sys.argv[1]
s=io.open(path,encoding='utf-8',newline='').read()
NL='\r\n' if s.count('\r\n')>s.count('\n')//2 else '\n'
def rep(old,new,count=1):
    global s
    if NL=='\r\n': old=old.replace('\n','\r\n'); new=new.replace('\n','\r\n')
    n=s.count(old)
    if n!=count: raise SystemExit(f'anchor x{n} (want {count}): {old[:90]!r}')
    s=s.replace(old,new)
if 'Stage IMPORT-EXACT' in s: raise SystemExit('already patched')

# 1) state
rep("let impData=[],impCols=[],impMap={};",
    "let impData=[],impCols=[],impMap={};\nlet impDefEmp=''; // Stage IMPORT-EXACT: นายจ้างของทุกแถว (จากหัวเรื่องในไฟล์ เมื่อไม่มีคอลัมน์นายจ้าง)")

# 2) fields / aliases
rep("{key:'license_no',label:'เลขใบอนุญาตทำงาน',aliases:['work','เลขใบอนุญาตทำงาน','เลขใบอนุญาต','เลขเวิร์ค','license_no']},",
    "{key:'license_no',label:'เลขใบอนุญาตทำงาน',aliases:['work','เลขใบอนุญาตทำงาน','เลขใบอนุญาต','เลขเวิร์ค','license_no','ใบอนุญาตทำงานเลขที่','เลขที่ใบอนุญาตทำงาน','work permit no']},")
rep("'วันหมดเวิร์ค','wp หมด','วันหมดใบอนุญาตทำงาน']},",
    "'วันหมดเวิร์ค','wp หมด','วันหมดใบอนุญาตทำงาน','วันหมดอายุใบอนุญาตทำงาน','วันหมดอยุใบอนุญาตทำงาน','หมดอายุใบอนุญาตทำงาน','หมดอยุใบอนุญาตทำงาน','วันหมดอายุ wp','wp หมดอายุ']},")
rep("  {key:'note',label:'หมายเหตุ',aliases:['หมายเหตุ','remark','note']},",
    "  {key:'note',label:'หมายเหตุ',aliases:['หมายเหตุ','remark','note']},\n"
    "  // Stage IMPORT-EXACT\n"
    "  {key:'dob',label:'วันเกิด',aliases:['วันเกิด','ว/ด/ป เกิด','ว/ด/ปเกิด','ว.ด.ป.เกิด','ว.ด.ป. เกิด','วดป เกิด','วัน/เดือน/ปี เกิด','วันเดือนปีเกิด','dob','date of birth','birthday','เกิด']},\n"
    "  {key:'email',label:'Email',aliases:['email','e-mail','อีเมล','อีเมล์']},")

# 3) helpers (หลัง _impStatus)
rep("function _impStatus(v){const s=String(v==null?'':v).trim();return(!s||s==='สถานะ'||s==='-')?'':s;}",
    "function _impStatus(v){const s=String(v==null?'':v).trim();return(!s||s==='สถานะ'||s==='-')?'':s;}\n"
    "// ── Stage IMPORT-EXACT ──\n"
    "// ชื่อนายจ้างจากแถวหัวเรื่องเหนือหัวตาราง (แถวที่มีข้อความช่องเดียว) — ใช้เมื่อไฟล์ไม่มีคอลัมน์นายจ้าง\n"
    "function _impTitleEmp(rows,hdr){\n"
    "  const _co=/(บริษัท|บ\\.|หจก|ห้างหุ้นส่วน|จำกัด|co\\.|ltd|limited|นาย|นาง|น\\.ส\\.|สวน|ฟาร์ม|โรงงาน|ร้าน)/i;\n"
    "  for(let r=Math.min(hdr,6)-1;r>=0;r--){\n"
    "    const cells=(rows[r]||[]).map(c=>String(c==null?'':c).trim()).filter(Boolean);\n"
    "    if(cells.length!==1)continue;const t=cells[0];\n"
    "    if(t.length<2||t.length>80||/^\\d+$/.test(t))continue;\n"
    "    const n=normalizeEmployerName(t);\n"
    "    if((employers||[]).some(e=>normalizeEmployerName(e.name)===n)||_co.test(t))return t;\n"
    "  }\n"
    "  return '';\n"
    "}\n"
    "// นายจ้างของแถว: คอลัมน์นายจ้างในไฟล์ก่อน → ถ้าไฟล์ไม่มีคอลัมน์นายจ้าง ใช้ \"นายจ้างของทุกคนในไฟล์\"\n"
    "function _impEmpName(row,get){if(impMap.employer_name!==undefined&&impMap.employer_name>=0)return get(row,'employer_name');return String(impDefEmp||'').trim();}\n"
    "// ข้อความเพิ่มเติมที่ต้องไม่หาย → ต่อท้ายหมายเหตุ: Email + ช่องวันที่ที่เป็นข้อความ (เช่น \"รอPass\")\n"
    "const _IMP_DATE_LBL={exp_wp:'วันหมด WP',exp_visa:'วันหมด VISA',exp_passport:'วันหมดพาสปอร์ต',next_90:'90 วัน',dob:'วันเกิด',submit_date:'วันที่ยื่น',appt_date:'นัดหมาย',queue_date:'คิวว่าง',receive_date:'วันรับเล่ม'};\n"
    "function _impExtraNote(row,get){\n"
    "  const out=[];\n"
    "  Object.keys(_IMP_DATE_LBL).forEach(k=>{if(impMap[k]===undefined||impMap[k]<0)return;const raw=get(row,k);if(raw&&!_impBlankId(raw)&&!impDate(raw))out.push(_IMP_DATE_LBL[k]+': '+raw);});\n"
    "  const em=_impClean(get(row,'email'));if(em)out.push('Email: '+em);\n"
    "  return out;\n"
    "}\n"
    "function _impJoinNote(base,extra){const b=_impClean(base);const parts=(b?[b]:[]).concat(extra||[]);return parts.length?parts.join(' · '):null;}\n"
    "// อัปเดตสถานะช่องนายจ้าง (ไม่ render ใหม่ทั้งหน้า — กันเคอร์เซอร์หลุดตอนพิมพ์)\n"
    "function impDefEmpInput(v){impDefEmp=v;const el=document.getElementById('impDefEmpSt');if(el)el.innerHTML=_impDefEmpStatus();}\n"
    "function _impDefEmpStatus(){const t=String(impDefEmp||'').trim();if(!t)return'<span style=\"color:var(--g5)\">ว่าง = ไม่ผูกนายจ้าง</span>';const n=normalizeEmployerName(t);return(employers||[]).some(e=>normalizeEmployerName(e.name)===n)?'<span style=\"color:#16a34a;font-weight:600\">✅ มีในระบบแล้ว</span>':'<span style=\"color:#b45309;font-weight:600\">➕ จะสร้างนายจ้างใหม่</span>';}")

# 4) "รอ..." ในช่องวันที่ ไม่ใช่วันที่ → ไม่ดึงวันที่ที่ฝังอยู่ (กันเตือนหมดอายุผิด)
rep("  // Mixed text with embedded date (\"ต่ออายุ31/03/69\") — extract and retry\n",
    "  // Mixed text with embedded date (\"ต่ออายุ31/03/69\") — extract and retry\n"
    "  if(/^รอ/.test(v))return null; // Stage IMPORT-EXACT: \"รอถ่ายบัตรวันที่ 2/12/69\" = งานที่รออยู่ ไม่ใช่วันหมดอายุ → เก็บเป็นหมายเหตุแทน\n")

# 5) อ่านไฟล์: ตั้ง impDefEmp จากหัวเรื่อง
rep("impCols=(rows[_h]||[]).map(c=>String(c).trim());\n  impData=rows.slice(_h+1).filter(r=>r.some(c=>c));",
    "impCols=(rows[_h]||[]).map(c=>String(c).trim());\n  impData=rows.slice(_h+1).filter(r=>r.some(c=>c));\n  impDefEmp=_impTitleEmp(rows,_h); // Stage IMPORT-EXACT")
rep("const _ch=impDetectHeaderRow(_rows);impCols=(_rows[_ch]||[]).map(c=>String(c).trim());",
    "const _ch=impDetectHeaderRow(_rows);impCols=(_rows[_ch]||[]).map(c=>String(c).trim());impDefEmp=_impTitleEmp(_rows,_ch);")
rep("const _hdr=impDetectHeaderRow(arr);impCols=(arr[_hdr]||[]).map(String);",
    "const _hdr=impDetectHeaderRow(arr);impCols=(arr[_hdr]||[]).map(String);impDefEmp=_impTitleEmp(arr,_hdr);")

# 6) preview: dedup key ใช้นายจ้างของแถว + ช่องนายจ้างของทุกคน + รายการข้อความที่จะลงหมายเหตุ
rep("const _k=makeImpKeyEx(get(r,'passport_no'),get(r,'alien_id'),get(r,'wp_no'),name,get(r,'nationality'),get(r,'employer_name'));",
    "const _k=makeImpKeyEx(get(r,'passport_no'),get(r,'alien_id'),get(r,'wp_no'),name,get(r,'nationality'),_impEmpName(r,get));")
rep("  <div style=\"padding:12px 15px;border-bottom:1px solid var(--g2)\"><div style=\"font-size:12px;font-weight:700;color:var(--g7);margin-bottom:8px\">จับคู่คอลัมน์</div>",
    "  ${_impEmpBox}${_impNoteBox}<div style=\"padding:12px 15px;border-bottom:1px solid var(--g2)\"><div style=\"font-size:12px;font-weight:700;color:var(--g7);margin-bottom:8px\">จับคู่คอลัมน์</div>")
rep("  document.getElementById('impPreview').innerHTML=`${photoPanel}<div class=\"twrap\">",
    "  // Stage IMPORT-EXACT: ไฟล์ไม่มีคอลัมน์นายจ้าง → ให้ระบุนายจ้างของทุกคน (เติมจากหัวเรื่องให้อัตโนมัติ)\n"
    "  const _noEmpCol=!(impMap.employer_name!==undefined&&impMap.employer_name>=0);\n"
    "  const _impEmpBox=_noEmpCol?`<div style=\"padding:10px 15px;border-bottom:1px solid var(--g2);background:#f0f7ff;display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:12px\"><b style=\"color:var(--g8)\">นายจ้างของทุกคนในไฟล์นี้:</b><input class=\"fi2\" list=\"impEmpList\" style=\"min-width:240px;flex:1;max-width:380px\" value=\"${esc(impDefEmp||'')}\" placeholder=\"พิมพ์หรือเลือกนายจ้าง\" oninput=\"impDefEmpInput(this.value)\"><datalist id=\"impEmpList\">${(employers||[]).map(e=>`<option value=\"${esc(e.name)}\">`).join('')}</datalist><span id=\"impDefEmpSt\">${_impDefEmpStatus()}</span></div>`:'';\n"
    "  const _xn=impData.map((r,i)=>({i,x:_impExtraNote(r,get)})).filter(o=>o.x.some(t=>!/^Email: /.test(t)));\n"
    "  const _impNoteBox=_xn.length?`<div style=\"padding:8px 15px;border-bottom:1px solid #fde68a;background:#fffbeb;font-size:11px;color:#92400e\"><b>ช่องวันที่ที่เป็นข้อความ ${_xn.length} แถว</b> — ไม่ตั้งเป็นวันที่ แต่เก็บข้อความไว้ใน \"หมายเหตุ\" ของแรงงาน: ${_xn.slice(0,6).map(o=>esc((get(impData[o.i],'name')||'#'+(o.i+1))+' → '+o.x.filter(t=>!/^Email: /.test(t)).join(', '))).join(' · ')}${_xn.length>6?' …':''}</div>`:'';\n"
    "  document.getElementById('impPreview').innerHTML=`${photoPanel}<div class=\"twrap\">")

# 7) doImport: นายจ้าง / dob / หมายเหตุ
rep("const nat=get(row,'nationality');const empName=get(row,'employer_name');",
    "const nat=get(row,'nationality');const empName=_impEmpName(row,get); // Stage IMPORT-EXACT")
rep("work_status:_impStatus(get(row,'work_status'))||'รับเรื่อง',note:_impClean(get(row,'note'))};",
    "work_status:_impStatus(get(row,'work_status'))||'รับเรื่อง',note:_impJoinNote(get(row,'note'),_impExtraNote(row,get))}; // Stage IMPORT-EXACT: + Email/ข้อความในช่องวันที่\n"
    "      {const _dob=_ds('dob',get(row,'dob'));if(_dob)data.dob=_dob;} // Stage IMPORT-EXACT")

# 8) อัปเดตคนเดิม: นายจ้างของทุกคน + วันเกิด
rep("  const en=get(row,'employer_name');\n  if(en){const _en=normalizeEmployerName(en);",
    "  const en=_impEmpName(row,get); // Stage IMPORT-EXACT\n  if(en){const _en=normalizeEmployerName(en);")
rep("  ['exp_wp','exp_passport','exp_visa','next_90','exp_mou'].forEach(k=>set(k,d(k)));",
    "  ['exp_wp','exp_passport','exp_visa','next_90','exp_mou','dob'].forEach(k=>set(k,d(k)));")
rep("const _IMP_UPD_LBL={exp_wp:'เวิร์คหมด',",
    "const _IMP_UPD_LBL={dob:'วันเกิด',exp_wp:'เวิร์คหมด',")

# 9) พรีวิว: แสดงนายจ้างของแถวในแผงรูป + ตารางตัวอย่างไม่เลื่อนคอลัมน์เมื่อมีช่องว่าง (เช่นคอลัมน์รูปถ่าย)
rep("const nm=get(r,'name')||'—',emp=get(r,'employer_name')||'—'",
    "const nm=get(r,'name')||'—',emp=_impEmpName(r,get)||'—'")
rep("${r.map((v,ci)=>`<td>${dateColIdx.has(ci)?(impDate(v)||''):(v||'')}</td>`).join('')}",
    "${impCols.map((_c,ci)=>{const v=r[ci];return`<td>${dateColIdx.has(ci)?(impDate(v)||''):(v==null?'':v)}</td>`;}).join('')}")

io.open(path,'w',encoding='utf-8',newline='').write(s)
print('patched',path)

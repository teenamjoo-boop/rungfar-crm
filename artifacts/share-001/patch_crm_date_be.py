# Stage DATE-BE-FIX — กันวันที่ปี พ.ศ. หลุดเข้าฐานข้อมูลเป็น ค.ศ. (เช่น 2569-11-09 → แสดงเป็นปี 3112 / อีก 198,358 วัน)
#   1) แสดงผล: fd()/du() อ่านปี ≥2400 เป็น พ.ศ. แล้วแปลงเป็น ค.ศ. ก่อนคำนวณ (ข้อมูลเก่าที่ผิดแสดงถูกทันที)
#   2) ช่องกรอกวันที่ทุกช่อง (input type=date): ออกจากช่องแล้วปี ≥2400 → ลบ 543 อัตโนมัติ + แจ้งเตือน
#   3) saveCustomer: แปลงวันที่ปี ≥2400 ใน payload ก่อนบันทึก (กันกรณีกดบันทึกโดยไม่แตะช่อง)
import sys

MARK = 'Stage DATE-BE-FIX'

HELPERS = r'''// ── Stage DATE-BE-FIX: ปี ≥2400 = กรอกเป็น พ.ศ. → แปลงเป็น ค.ศ. ──
function _ceDate(d){if(d==null||d==='')return d;const s=String(d);const m=s.match(/^(\d{4})(-\d{2}-\d{2}.*)$/);if(m){const y=+m[1];if(y>=2400)return String(y-543)+m[2];}return d;}
function _ceObj(o){if(o&&typeof o==='object')Object.keys(o).forEach(k=>{const v=o[k];if(typeof v==='string'&&/^\d{4}-\d{2}-\d{2}/.test(v))o[k]=_ceDate(v);});return o;}
document.addEventListener('focusout',function(e){const el=e.target;if(!el||el.tagName!=='INPUT'||el.type!=='date'||!el.value)return;const v=_ceDate(el.value);if(v!==el.value){el.value=v;el.dispatchEvent(new Event('change',{bubbles:true}));try{toast('ช่องวันที่ต้องกรอกปี ค.ศ. — แปลงปี พ.ศ. ให้แล้ว');}catch(_){}}},true);
'''

def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:70]}')
    return s.replace(old, new)

def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    nl = '\r\n' if '\r\n' in s else '\n'
    a = "function fd(d){if(!d)return'—';return new Date(d).toLocaleDateString('th-TH',{day:'2-digit',month:'short',year:'2-digit'});}"
    s = rep(s, a, HELPERS.replace('\n', nl)
            + "function fd(d){if(!d)return'—';return new Date(_ceDate(d)).toLocaleDateString('th-TH',{day:'2-digit',month:'short',year:'2-digit'});}", path)
    a = "function du(d){if(!d)return null;const t=new Date();t.setHours(0,0,0,0);const x=new Date(d);"
    s = rep(s, a, "function du(d){if(!d)return null;const t=new Date();t.setHours(0,0,0,0);const x=new Date(_ceDate(d));", path)
    a = "updated_at:new Date().toISOString(),...(curUser&&curUser.username?{updated_by_code:curUser.username}:{})};"
    s = rep(s, a, a + "_ceObj(data); // " + MARK, path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

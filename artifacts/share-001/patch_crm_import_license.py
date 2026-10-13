# Stage IMPORT-SHEETS-2 — คอลัมน์ WORK = เลขใบอนุญาตทำงาน → บันทึกลง customers.license_no (ช่อง "เลขใบอนุญาต")
#   (เดิมรอบแรกใส่ลง wp_no = "เลขคำขอ WP" ซึ่งไม่ถูกต้อง)
import sys

MARK = 'Stage IMPORT-SHEETS-2'

def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:70]}')
    return s.replace(old, new)

def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage UI-HIDE-CASES' not in s:
        sys.exit(f'{path}: run patch_crm_hide_import.py first')
    nl = '\r\n' if '\r\n' in s else '\n'
    old_wp = "aliases:['เลขคำขอ','เลขคำขอ wp','wp_no','work permit','work','เลขใบอนุญาตทำงาน','เลข wp']}"
    s = rep(s, old_wp,
            "aliases:['เลขคำขอ','เลขคำขอ wp','wp_no','work permit','เลข wp']}," + nl
            + "  {key:'license_no',label:'เลขใบอนุญาตทำงาน',aliases:['work','เลขใบอนุญาตทำงาน','เลขใบอนุญาต','เลขเวิร์ค','license_no']}",
            path)
    a = "data.exp_passport=_ds('exp_passport',get(row,'exp_passport')); // Stage IMPORT-SHEETS"
    s = rep(s, a, a + nl + "      data.license_no=_impClean(get(row,'license_no')); // " + MARK, path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

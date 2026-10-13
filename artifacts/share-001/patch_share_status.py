# Stage SHARE-STATUS: แสดง "สถานะงาน" (ข้อความที่เจ้าหน้าที่เขียนใน CRM) ด้านขวาของแต่ละคนในหน้าลิงก์
#  - ต้องใช้ employer-share-view เวอร์ชันที่ส่ง status มา (ไม่มี = ไม่แสดง ไม่พัง)
#  - หน้ารายละเอียดแรงงาน: เพิ่มบรรทัด "สถานะงาน" ในข้อมูลส่วนตัว
import sys

MARK = 'Stage SHARE-STATUS'
CSS = '''/* Stage SHARE-STATUS */
.w .wst{flex:none;max-width:31%;font-size:11.5px;line-height:1.35;font-weight:600;color:#24508a;background:#eaf2fc;border:1px solid #d3e3f7;padding:5px 9px;border-radius:10px;text-align:center;overflow:hidden;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;word-break:break-word}
@media (min-width:700px){.w .wst{max-width:34%;font-size:13px;padding:6px 12px}}
'''


def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:80]}')
    return s.replace(old, new)


def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHARE-SMOOTH' not in s:
        sys.exit(path + ': ต้องมี SHARE-SMOOTH ก่อน')
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    s = rep(s, '</style>', CSS + '</style>', path)
    s = rep(s, '      <span class="chev">›</span>',
            '      ${w.status?`<span class="wst">${esc(w.status)}</span>`:\'\'}\n      <span class="chev">›</span>', path)
    s = rep(s, "  const kv=[['ชื่อ (ภาษาไทย)',w.name_th],", "  const kv=[...(w.status?[['สถานะงาน',w.status]]:[]),['ชื่อ (ภาษาไทย)',w.name_th],", path)
    open(path, 'wb').write(s.replace('\n', nl).encode('utf-8'))
    print(path, ': patched')


for p in sys.argv[1:]:
    patch(p)

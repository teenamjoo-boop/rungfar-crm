# Case Template Content Worksheet
แบบฟอร์มเตรียมข้อมูลสำหรับกรอก “ข้อมูลเตรียมงาน” ในแม่แบบเอกสาร / ขั้นตอนงาน

> **Stage 54A-9C** — ไฟล์เอกสารอย่างเดียว ไม่มี SQL / ไม่มีคำสั่งลบข้อมูล / ไม่แก้โค้ดระบบ
> ใช้เตรียมเนื้อหาบนกระดาษก่อน แล้วค่อยนำไปกรอกในหน้า “แม่แบบเอกสาร / ขั้นตอนงาน” ของ CRM

---

## จุดประสงค์ของไฟล์นี้

ไฟล์นี้ช่วยเจ้าของระบบ / admin เตรียมเนื้อหา “ข้อมูลเตรียมงาน” ของแต่ละแม่แบบ **ก่อน** นำไปกรอกจริงใน CRM
เนื้อหาที่ต้องเตรียมต่อหนึ่งแม่แบบ:

- **ใช้กับกรณีไหน** — เคสแบบนี้ใช้กับสถานการณ์ใด
- **อ้างอิงมติ / มาตรา / แบบฟอร์ม** — เอกสารอ้างอิงที่เกี่ยวข้อง
- **ขั้นตอนโดยย่อ** — พนักงานต้องทำอะไรบ้าง
- **หมายเหตุสำหรับพนักงาน** — จุดที่พลาดบ่อย / ต้องระวัง
- **แหล่งข้อมูลอ้างอิง** — เอามาจากคู่มือ/ไฟล์ไหน เวอร์ชันอะไร

> ⚠️ **กรอกจากแหล่งที่ตรวจแล้วเท่านั้น** — ใช้ได้เฉพาะข้อมูลจากไฟล์ PDF / คู่มือทางการ / กระบวนการภายในบริษัทที่ยืนยันแล้ว
> ถ้ายังไม่มีแหล่ง ให้ทิ้งเป็น `TODO` หรือ `NEED_SOURCE` ไว้ก่อน — **ห้ามเดา**

---

## กติกาของแต่ละช่อง (field rules)

| ช่อง (field) | เขียนอะไร | ความยาวแนะนำ | ตัวอย่างรูปแบบ (placeholder) | แสดงที่ไหนใน CRM |
|---|---|---|---|---|
| `eligibility_note` | เคสนี้ใช้กับกรณีไหน (สั้น ชัด) | 1 บรรทัด ~120 ตัวอักษร | `ใช้กับ TODO_CASE_CONDITION` | หน้ารายละเอียดแม่แบบ · พรีวิวตอนสร้างเคส · แถบในหน้าเคส |
| `process_summary` | ขั้นตอนโดยย่อ 3–6 ข้อ | สั้น หลายบรรทัด ~300 ตัวอักษร | `1) TODO → 2) TODO → 3) TODO` | หน้ารายละเอียดแม่แบบ · พรีวิวตอนสร้างเคส |
| `cabinet_resolution_refs` | อ้างอิงมติ ครม./มติ (หนึ่งบรรทัด = หนึ่งมติ) | 1–3 รายการ | `TODO_DATE \| TODO_MATI_NAME \| TODO_NOTE` | หน้ารายละเอียด (เต็ม) · ที่อื่นแสดงเป็นชิป “มติ N” |
| `law_refs` | มาตรา / ข้อ / เงื่อนไข (หนึ่งบรรทัด = หนึ่งข้อ) | 1–5 รายการ | `TODO_LAW \| TODO_SECTION \| TODO_USAGE` | หน้ารายละเอียด (เต็ม) · ที่อื่นแสดงเป็นชิป “มาตรา/เงื่อนไข N” |
| `form_refs` | แบบฟอร์มที่เกี่ยวข้อง (หนึ่งบรรทัด = หนึ่งแบบ) | ไม่กี่รายการ | `TODO_FORM_CODE \| TODO_FORM_NAME \| TODO_USAGE` | หน้ารายละเอียด · ชิป “แบบฟอร์ม N” ทุกที่ |
| `internal_guidance` | หมายเหตุ/เคล็ดลับ/จุดพลาดบ่อยสำหรับพนักงาน | ช่องเดียวที่ยาวได้ | `TODO_STAFF_TIP` | หน้ารายละเอียดแม่แบบ (และบรรทัด 📝 สั้นในหน้าเคส) |
| `source_note` | เอาข้อมูลมาจากไหน เวอร์ชัน/วันที่ | 1 บรรทัด | `TODO_SOURCE_FILE \| TODO_VERSION_DATE \| TODO_PAGE` | ท้ายหน้ารายละเอียดแม่แบบเท่านั้น |

> **หมายเหตุ:** ช่อง `cabinet_resolution_refs`, `law_refs`, `form_refs` ในหน้าแก้ไข CRM เป็นกล่องข้อความหลายบรรทัด
> ระบบจะแปลง “หนึ่งบรรทัด = หนึ่งรายการ” ให้อัตโนมัติ — ไม่ต้องพิมพ์ JSON

---

## รูปแบบบรรทัดอ้างอิงที่ปลอดภัย (reference format)

ใช้เครื่องหมาย `|` คั่นเป็นช่อง เพื่อให้อ่านง่ายและสม่ำเสมอ:

- **มติ:** `YYYY-MM-DD | ชื่อมติ/หัวข้อ | หมายเหตุสั้น`
  ตัวอย่าง placeholder: `TODO_DATE | TODO_MATI_NAME | TODO_NOTE`
- **มาตรา/เงื่อนไข:** `กฎหมาย/ประกาศ | มาตรา/ข้อ | ใช้กับกรณี`
  ตัวอย่าง placeholder: `TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE`
- **แบบฟอร์ม:** `รหัสแบบฟอร์ม | ชื่อแบบฟอร์ม | ใช้เมื่อ`
  ตัวอย่าง placeholder: `TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE`
- **source_note:** `ชื่อไฟล์/คู่มือ | เวอร์ชัน/วันที่ | หน้า/หัวข้อ`
  ตัวอย่าง placeholder: `TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION`

> ตัวอย่างข้างบนเป็น placeholder เท่านั้น — ยังไม่ใช่ข้อมูลจริง อย่านำไปกรอกตรง ๆ

---

## สถานะการเตรียมข้อมูล (fill status legend)

| สถานะ | ความหมาย |
|---|---|
| `MISSING_SOURCE` | ยังไม่มีแหล่งอ้างอิง (PDF/คู่มือ) — กรอกไม่ได้ ต้องขอแหล่งก่อน |
| `PARTIAL_INTERNAL` | เป็นกระบวนการภายในบริษัท กรอกบางช่องได้ (เช่น ขั้นตอน/หมายเหตุ) แต่อ้างอิงราชการยังไม่มี |
| `VERIFIED_SOURCE` | ตรวจกับแหล่งจริงแล้ว เนื้อหาถูกต้อง พร้อมกรอก |
| `READY_TO_ENTER_CRM` | ตรวจ + จัดรูปแบบครบ พร้อมนำเข้า CRM ได้ทันที |

**เส้นทางปกติ:** `MISSING_SOURCE` → (ได้แหล่ง) → `PARTIAL_INTERNAL`/`VERIFIED_SOURCE` → (จัดรูปแบบครบ) → `READY_TO_ENTER_CRM` → กรอกใน CRM

---

# แม่แบบทั้ง 16 รายการ (worksheet)

> ช่อง Priority / Owner / Last reviewed ให้ผู้รับผิดชอบเติมเอง
> ค่า Priority ที่ใส่ไว้เป็น “คำแนะนำ” จากความถี่งานทั่วไป — ปรับได้ตามจริง

---

## MOU_MYANMAR_NEW — งาน MOU พม่า (นำเข้าใหม่)

Status: MISSING_SOURCE
Category: mou
Checklist count: 8
Priority: แนะนำ สูง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## MOU_LAOS_NEW — งาน MOU ลาว (นำเข้าใหม่)

Status: MISSING_SOURCE
Category: mou
Checklist count: 8
Priority: แนะนำ สูง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## MOU_CAMBODIA_NEW — งาน MOU กัมพูชา (นำเข้าใหม่)

Status: MISSING_SOURCE
Category: mou
Checklist count: 8
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## CI_MYANMAR — เอกสาร CI พม่า

Status: MISSING_SOURCE
Category: ci
Checklist count: 6
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## VISA_WP_RENEWAL — ต่อวีซ่า + ใบอนุญาตทำงาน

Status: MISSING_SOURCE
Category: renewal
Checklist count: 8
Priority: แนะนำ สูง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## WP_RENEWAL — ต่อใบอนุญาตทำงาน

Status: MISSING_SOURCE
Category: work_permit
Checklist count: 8
Priority: แนะนำ สูง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## VISA_RENEWAL — ต่อวีซ่า

Status: MISSING_SOURCE
Category: visa
Checklist count: 8
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## REPORT_90_DAYS — รายงานตัว 90 วัน

Status: PARTIAL_INTERNAL
Category: report_90
Checklist count: 8
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- งานประจำที่รู้กันดี แต่ยังต้องยืนยันเงื่อนไข/รอบเวลากับแหล่งจริงก่อนใส่เลขมาตรา -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## CHANGE_EMPLOYER — เปลี่ยนนายจ้าง

Status: MISSING_SOURCE
Category: change_employer
Checklist count: 10
Priority: แนะนำ สูง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## CHANGE_EMPLOYER_URGENT — เปลี่ยนนายจ้าง (เร่งด่วน)

Status: MISSING_SOURCE
Category: change_employer
Checklist count: 10
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- เหมือน CHANGE_EMPLOYER แต่มีเงื่อนไขเร่งด่วน — ระบุกรอบเวลา/เงื่อนไขจากแหล่งจริง -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## EMPLOYER_NOTIFICATION_IN — แจ้งแรงงานเข้าทำงาน

Status: MISSING_SOURCE
Category: notification
Checklist count: 8
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## EMPLOYER_NOTIFICATION_OUT — แจ้งแรงงานออกจากงาน

Status: MISSING_SOURCE
Category: notification
Checklist count: 8
Priority: แนะนำ กลาง (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- TODO_DATE | TODO_MATI_NAME | TODO_NOTE

### มาตรา / เงื่อนไข
- TODO_LAW_OR_NOTICE | TODO_SECTION | TODO_USAGE

### แบบฟอร์มที่เกี่ยวข้อง
- TODO_FORM_CODE | TODO_FORM_NAME | TODO_USAGE

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- TODO_SOURCE_FILE | TODO_VERSION_DATE | TODO_PAGE_OR_SECTION

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## WORKER_DOCUMENT_FIX — แก้ไข/อัปเดตเอกสารแรงงาน

Status: PARTIAL_INTERNAL
Category: other
Checklist count: 6
Priority: แนะนำ ต่ำ (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- กระบวนการภายในบริษัท — กรอก eligibility/ขั้นตอน/หมายเหตุได้เลย ส่วนอ้างอิงราชการเว้นว่างถ้าไม่เกี่ยว -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### มาตรา / เงื่อนไข
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### แบบฟอร์มที่เกี่ยวข้อง
- (เว้นว่างได้ถ้าไม่มีแบบฟอร์มราชการ) TODO_ถ้ามี

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- กระบวนการภายในบริษัท | TODO_VERSION_DATE | TODO_ผู้ยืนยัน

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## PASSPORT_UPDATE — อัปเดตพาสปอร์ตเล่มใหม่

Status: PARTIAL_INTERNAL
Category: other
Checklist count: 6
Priority: แนะนำ ต่ำ (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- ส่วนใหญ่เป็นงานภายใน — ถ้ามีขั้นตอนแจ้งหน่วยงานต้องยืนยันจากแหล่งจริงก่อน -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### มาตรา / เงื่อนไข
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### แบบฟอร์มที่เกี่ยวข้อง
- (เว้นว่างได้ถ้าไม่มีแบบฟอร์มราชการ) TODO_ถ้ามี

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- กระบวนการภายในบริษัท | TODO_VERSION_DATE | TODO_ผู้ยืนยัน

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## HEALTH_INSURANCE — ประกันสุขภาพแรงงาน

Status: PARTIAL_INTERNAL
Category: other
Checklist count: 6
Priority: แนะนำ ต่ำ (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- งานจัดทำ/ต่อประกัน — กรอกกระบวนการภายในได้ ส่วนเงื่อนไขราชการ (ถ้ามี) ต้องยืนยันแหล่ง -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### มาตรา / เงื่อนไข
- (เว้นว่างได้ถ้าเป็นงานภายในล้วน) TODO_ถ้ามี

### แบบฟอร์มที่เกี่ยวข้อง
- (เว้นว่างได้ถ้าไม่มีแบบฟอร์มราชการ) TODO_ถ้ามี

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- กระบวนการภายในบริษัท | TODO_VERSION_DATE | TODO_ผู้ยืนยัน

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

## OTHER_LABOR_DOCUMENT — เอกสารแรงงานอื่น ๆ

Status: PARTIAL_INTERNAL
Category: other
Checklist count: 6
Priority: แนะนำ ต่ำ (ปรับได้)
Owner: TODO
Last reviewed: TODO_DATE

### ใช้กับกรณี
TODO  <!-- แม่แบบกลางสำหรับงานที่ไม่เข้าแม่แบบอื่น — แนะนำกรอกเฉพาะ “ใช้กับกรณี” ให้ชัด ที่เหลือเว้นว่าง -->

### ขั้นตอนโดยย่อ
1. TODO
2. TODO
3. TODO

### อ้างอิงมติ
- (มักเว้นว่าง) TODO_ถ้ามี

### มาตรา / เงื่อนไข
- (มักเว้นว่าง) TODO_ถ้ามี

### แบบฟอร์มที่เกี่ยวข้อง
- (มักเว้นว่าง) TODO_ถ้ามี

### หมายเหตุภายในสำหรับพนักงาน
- TODO

### แหล่งข้อมูล
- กระบวนการภายในบริษัท | TODO_VERSION_DATE | TODO_ผู้ยืนยัน

### พร้อมกรอกเข้า CRM หรือยัง?
- [ ] ยังไม่พร้อม
- [ ] พร้อมบางส่วน
- [ ] พร้อมกรอกเข้า CRM

---

# วิธีนำข้อมูลเข้า CRM

เมื่อช่องของแม่แบบใดมีสถานะ `READY_TO_ENTER_CRM` แล้ว:

1. เปิดเมนู **“แม่แบบเอกสาร / ขั้นตอนงาน”**
2. เปิดแม่แบบที่ต้องการ (คลิกที่การ์ด)
3. กด **“แก้ไขแม่แบบ”**
4. เลื่อนไปส่วน **“ข้อมูลเตรียมงาน”** แล้วคัดลอกบรรทัดที่ตรวจแล้วลงในช่องให้ตรงกัน:
   - ใช้กับกรณี → `eligibility_note`
   - ขั้นตอนโดยย่อ → `process_summary`
   - อ้างอิงมติ → กล่อง “อ้างอิงมติ” (หนึ่งบรรทัด = หนึ่งรายการ)
   - มาตรา/เงื่อนไข → กล่อง “มาตรา / เงื่อนไข”
   - แบบฟอร์ม → กล่อง “แบบฟอร์มที่เกี่ยวข้อง”
   - หมายเหตุภายใน → `internal_guidance`
   - แหล่งข้อมูล → `source_note`
5. กด **บันทึก**
6. เปิดแม่แบบใหม่อีกครั้ง ตรวจว่า:
   - การ์ด “ข้อมูลเตรียมงาน” แสดงเนื้อหาถูกต้อง
   - ชิป “มติ / มาตรา/เงื่อนไข / แบบฟอร์ม” ขึ้นจำนวนตรงกับที่กรอก
   - ลองเปิด **สร้างเคส** แล้วเลือกแม่แบบนี้ ดูว่าพรีวิวขึ้นถูกต้อง

---

# ห้ามทำ (Do not enter)

- ❌ ห้ามกรอกข้อมูลจากความจำ ถ้ายังไม่ได้ตรวจแหล่งอ้างอิง
- ❌ ห้ามใส่เลขมติ / มาตรา / รหัสแบบฟอร์ม ถ้าไม่แน่ใจ — ปล่อยเป็น `TODO`/`NEED_SOURCE` ดีกว่าใส่ผิด
- ❌ ห้ามใส่ข้อความยาวเกินจำเป็น — สั้น ชัด พนักงานอ่านเร็ว
- ❌ ห้ามใส่ข้อความที่ทำให้พนักงานเข้าใจว่า CRM เป็นระบบราชการ หรือยื่นงานแทนเว็บราชการ

> CRM นี้คือ **ศูนย์เตรียมงานภายใน** ก่อนพนักงานไปยื่นจริงในระบบราชการ/e-WorkPermit — ข้อมูลในนี้ช่วยเตรียม ไม่ใช่เอกสารราชการ

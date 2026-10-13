-- =============================================================
-- Stage SHEET-VIEW + EMP-DOCS (additive, ปลอดภัย, รันซ้ำได้)
--   1) customers: 3 ช่องใหม่ตามชีสงานจริง (ว่างได้ทั้งหมด — แถวเดิมไม่เปลี่ยน)
--        worker_category  = ประเภท (MOU / มติ.ครม. / อื่น ๆ — พิมพ์เองได้)
--        status_note      = สถานะ (ข้อความอิสระที่เจ้าหน้าที่เขียน เช่น "ถ่ายบัตรแล้ว")
--        work_items       = รายการ (ข้อความอิสระ — ยังไม่ fix รูปแบบ ปรับทีหลังได้)
--      * RPC app_save_customer / app_bulk_create_customers / app_bulk_update_customers
--        whitelist คอลัมน์จากสคีมาจริงอยู่แล้ว → รับ 3 ช่องนี้อัตโนมัติ ไม่ต้องแก้ RPC
--   2) documents: ให้เก็บ "เอกสารนายจ้าง" ได้ (owner_type='employer', ไม่มี customer_id)
--        - customer_id เลิกบังคับ NOT NULL
--        - constraint ใหม่: เอกสารลูกค้าต้องมี customer_id; เอกสารประเภทอื่นต้องมี owner_id
--      * ไม่มีการลบ/แก้แถวเดิม (แถวเดิมเป็น customer ทั้งหมด มี customer_id ครบ)
-- รันบน: STAGING ก่อน (bzwtknqvhvdmatangzqf) — Production รอยืนยันแยก
-- =============================================================

alter table public.customers add column if not exists worker_category text;
alter table public.customers add column if not exists status_note     text;
alter table public.customers add column if not exists work_items      text;

alter table public.documents alter column customer_id drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'documents_owner_ref_check'
                   and conrelid = 'public.documents'::regclass) then
    alter table public.documents
      add constraint documents_owner_ref_check
      check (
        (owner_type = 'customer' and customer_id is not null)
        or (owner_type <> 'customer' and owner_id is not null)
      );
  end if;
end $$;

-- ตรวจผล (ควรได้: new_cols=3, customer_id_nullable=YES, owner_check=1)
select
  (select count(*) from information_schema.columns
    where table_schema='public' and table_name='customers'
      and column_name in ('worker_category','status_note','work_items'))          as new_cols,
  (select is_nullable from information_schema.columns
    where table_schema='public' and table_name='documents' and column_name='customer_id') as customer_id_nullable,
  (select count(*) from pg_constraint where conname='documents_owner_ref_check') as owner_check;

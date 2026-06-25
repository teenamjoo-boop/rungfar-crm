-- =============================================================
-- STAGE 22B — public.delete_requests (คำขอลบ จากพนักงาน → แอดมินอนุมัติ)
-- เป้าหมาย:
--   * ธุรกิจเปลี่ยนนโยบาย: Staff "ห้ามลบ" ลูกค้า/เอกสารโดยตรงอีกต่อไป
--     ให้ Staff "ส่งคำขอลบ" แล้ว Admin เป็นผู้อนุมัติ/ปฏิเสธ
--     เมื่ออนุมัติ → ลบจริง + บันทึก Audit Log
--   * ตารางใหม่ตัวเดียว (additive) — ไม่แตะ customers / documents / audit_logs
--   * โมเดลเดียวกับทั้งแอป: client เข้าถึงด้วย anon key, ตรวจสิทธิ์ฝั่ง client
--     (เหมือน customers/groups/documents) — การ์ด admin/staff อยู่ใน UI + ฟังก์ชัน
--
-- ⚠️ Additive only — ไม่ ALTER/DROP ตารางเดิม, ไม่แตะ RLS ตารางอื่น
-- ⚠️ ต้อง apply migration นี้ใน Supabase ก่อนใช้งานฟีเจอร์คำขอลบ
--    - ก่อน apply: ปุ่ม "ขอลบ" จะ INSERT ไม่สำเร็จ (best-effort / แจ้ง error),
--      หน้า "คำขอลบ" จะว่าง — แต่ action อื่นทำงานปกติ
-- =============================================================

-- 1) ตาราง delete_requests ----------------------------------------------------
create table if not exists public.delete_requests (
  id                bigint generated always as identity primary key,
  created_at        timestamptz not null default now(),
  requested_by_code text,                       -- curUser.username (รหัสพนักงานผู้ขอ)
  requested_by_name text,                       -- curUser.full_name
  requested_by_role text,                       -- staff / admin ...
  request_type      text not null,              -- customer_delete | customer_bulk_delete | document_delete
  entity_type       text,                       -- customer | document
  entity_id         text,                       -- id ที่ขอลบ (text รองรับเดี่ยว; bulk ใช้ detail.ids)
  entity_name       text,                       -- ชื่อ/พาสปอร์ต/เลขต่างด้าว/ชื่อเอกสาร (อ่านง่าย)
  detail            jsonb,                       -- สรุปปลอดภัย {count, ids, names, doc_type, customer_name} — ห้ามมี base64/photo/file_data
  reason            text,                        -- เหตุผล (optional จากผู้ขอ)
  status            text not null default 'pending', -- pending | approved | rejected | cancelled
  reviewed_by_code  text,                        -- admin ผู้ตรวจ
  reviewed_by_name  text,
  reviewed_at       timestamptz,
  review_note       text
);

create index if not exists idx_delete_requests_status     on public.delete_requests (status);
create index if not exists idx_delete_requests_created_at on public.delete_requests (created_at desc);
create index if not exists idx_delete_requests_requester  on public.delete_requests (requested_by_code);

-- 2) RLS — โมเดล client-trust เดียวกับตารางหลักของแอป (anon key) ----------------
--    เปิด select/insert/update ให้ client; การ์ด admin/staff ทำฝั่ง UI+ฟังก์ชัน
--    ไม่เปิด DELETE (คำขอไม่ถูกลบ — ใช้สถานะ cancelled แทน)
alter table public.delete_requests enable row level security;

drop policy if exists delete_requests_select_any on public.delete_requests;
create policy delete_requests_select_any
  on public.delete_requests
  for select
  to anon, authenticated
  using (true);

drop policy if exists delete_requests_insert_any on public.delete_requests;
create policy delete_requests_insert_any
  on public.delete_requests
  for insert
  to anon, authenticated
  with check (true);

drop policy if exists delete_requests_update_any on public.delete_requests;
create policy delete_requests_update_any
  on public.delete_requests
  for update
  to anon, authenticated
  using (true)
  with check (true);

-- สิทธิ์ตาราง: select/insert/update เท่านั้น (ไม่ให้ DELETE ตรง)
revoke all on table public.delete_requests from anon, authenticated;
grant select, insert, update on table public.delete_requests to anon, authenticated;

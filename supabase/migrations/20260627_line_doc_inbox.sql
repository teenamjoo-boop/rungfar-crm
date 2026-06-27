-- =============================================================
-- STAGE 29B — public.line_file_inbox (+ private storage bucket line-doc-inbox)
-- เป้าหมาย:
--   * รับไฟล์ (รูป/PDF/Excel/CSV) ที่คนส่งเข้ากลุ่ม LINE หลัก แล้วเก็บเป็น
--     "รายการรอตรวจ" (pending) ให้ทีม CRM เลือกลูกค้า/ประเภทเอกสาร แล้วอนุมัติ
--     ก่อนแนบเข้าเอกสารลูกค้าจริง (Stage 29C จะทำ UI + อนุมัติ)
--   * Edge Function line-doc-inbox (service_role) เป็นผู้เขียนตารางนี้เท่านั้น
--     ไฟล์จริงเก็บใน Storage (private bucket) — เก็บ "path/metadata" ในตาราง
--     ❌ ห้ามเก็บ base64/file bytes ในตาราง  ❌ ห้ามเก็บ raw webhook payload
--
-- ⚠️ Additive only — ไม่ ALTER/DROP ตารางเดิม, ไม่แตะ RLS ตารางอื่น
-- ⚠️ โมเดล RLS: เปิด RLS แต่ "ไม่สร้าง policy" → เข้าถึงได้เฉพาะ service_role
--    (เหมือน line_ai_excel_*). CRM จะอ่านผ่าน RPC SECURITY DEFINER ภายหลัง (29C)
-- =============================================================

create extension if not exists pgcrypto;

-- 1) ตาราง line_file_inbox ----------------------------------------------------
create table if not exists public.line_file_inbox (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  -- ── ที่มาจาก LINE ──
  line_group_id       text,
  line_user_id        text,
  line_display_name   text,
  line_message_id     text unique,        -- dedup กัน LINE webhook retry ซ้ำ
  line_event_id       text,               -- webhookEventId — trace/debug
  -- ── metadata ไฟล์ (ไม่เก็บ bytes/base64) ──
  file_name           text,
  mime_type           text,
  file_size           bigint,
  storage_path        text not null,      -- path ใน bucket line-doc-inbox เท่านั้น
  preview_path        text,               -- thumbnail (อนาคต) — optional
  source_type         text not null default 'other',  -- image | pdf | excel | other
  -- ── สถานะ workflow ──
  status              text not null default 'pending', -- pending | approved | rejected | linked
  linked_customer_id  bigint,             -- customers.id (set ตอนอนุมัติ) — ไม่ผูก FK (ตารางลูกค้าจัดการนอก migration)
  linked_document_id  bigint,             -- documents.id หลังแนบเข้าเอกสารลูกค้า
  doc_type            text,
  note                text,
  -- ── อนุมัติ / ปฏิเสธ ──
  approved_by_code    text,
  approved_by_name    text,
  approved_at         timestamptz,
  rejected_by_code    text,
  rejected_by_name    text,
  rejected_at         timestamptz,
  reject_reason       text,
  -- ── constraints ──
  constraint line_file_inbox_status_chk
    check (status in ('pending','approved','rejected','linked')),
  constraint line_file_inbox_source_type_chk
    check (source_type in ('image','pdf','excel','other'))
);

create index if not exists idx_line_file_inbox_status
  on public.line_file_inbox (status, created_at desc);
create index if not exists idx_line_file_inbox_group
  on public.line_file_inbox (line_group_id, created_at desc);
create index if not exists idx_line_file_inbox_source_type
  on public.line_file_inbox (source_type, created_at desc);

-- 2) RLS — เปิด RLS แต่ไม่สร้าง policy → service_role (Edge Function) เท่านั้น ----
--    (service_role bypass RLS เสมอ) CRM อ่านผ่าน RPC SECURITY DEFINER ใน 29C
alter table public.line_file_inbox enable row level security;

-- =============================================================
-- 3) Storage bucket: line-doc-inbox (PRIVATE)
--    ถ้ารันใน SQL Editor / supabase db push สำเร็จ จะสร้างให้เลย
--    ถ้า environment นี้ไม่อนุญาต insert storage.buckets ให้สร้างใน Dashboard:
--      Storage → New bucket → name: line-doc-inbox → Public = OFF (private)
-- =============================================================
insert into storage.buckets (id, name, public)
values ('line-doc-inbox', 'line-doc-inbox', false)
on conflict (id) do nothing;

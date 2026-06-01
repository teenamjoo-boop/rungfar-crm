-- =============================================================
-- LINE AI Excel Helper — SIMPLE-A Schema
-- รันใน Supabase SQL Editor (โปรเจกต์ ref: magwqolbjmwymqxelizl)
--
-- ระบบแยกจาก CRM/attendance เดิมโดยสิ้นเชิง
-- เป้าหมาย: รับรูปเอกสารในกลุ่ม LINE แยก → พิมพ์ "อ่าน" → Gemini สรุปเป็น TSV
--
-- 3 ตาราง:
--   line_ai_excel_batches  — ชุดรูป (batch) ต่อกลุ่ม ภายในหน้าต่างเวลา 30 นาที
--   line_ai_excel_files    — ไฟล์รูปในแต่ละ batch
--   line_ai_excel_results  — ผลที่ Gemini อ่าน (TSV + raw json)
-- =============================================================

create extension if not exists pgcrypto;

-- ─── line_ai_excel_batches ────────────────────────────────────
create table if not exists public.line_ai_excel_batches (
  id            uuid primary key default gen_random_uuid(),
  group_id      text not null,
  user_id       text,
  status        text not null default 'collecting',  -- collecting | read | cancelled
  image_count   int  not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_image_at timestamptz not null default now(),
  read_at       timestamptz
);

-- หา active batch เร็ว: group + status + เวลา
create index if not exists idx_line_ai_excel_batches_lookup
  on public.line_ai_excel_batches (group_id, status, last_image_at desc);

-- ─── line_ai_excel_files ──────────────────────────────────────
create table if not exists public.line_ai_excel_files (
  id              uuid primary key default gen_random_uuid(),
  batch_id        uuid not null references public.line_ai_excel_batches(id) on delete cascade,
  line_message_id text not null unique,   -- กัน webhook retry ซ้ำ
  storage_path    text not null,
  mime_type       text,
  created_at      timestamptz not null default now()
);

create index if not exists idx_line_ai_excel_files_batch
  on public.line_ai_excel_files (batch_id, created_at);

-- ─── line_ai_excel_results ────────────────────────────────────
create table if not exists public.line_ai_excel_results (
  id          uuid primary key default gen_random_uuid(),
  batch_id    uuid not null references public.line_ai_excel_batches(id) on delete cascade,
  result_text text,
  raw_json    jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists idx_line_ai_excel_results_batch
  on public.line_ai_excel_results (batch_id);

-- ─── RLS ──────────────────────────────────────────────────────
-- เปิด RLS แต่ไม่สร้าง policy ให้ anon/authenticated
-- → เข้าถึงได้เฉพาะ service_role (Edge Function) ซึ่ง bypass RLS เสมอ
alter table public.line_ai_excel_batches enable row level security;
alter table public.line_ai_excel_files   enable row level security;
alter table public.line_ai_excel_results enable row level security;

-- =============================================================
-- Storage bucket: line-ai-excel-intake (private)
-- ถ้ารันใน SQL Editor ได้ จะสร้างให้เลย; ถ้า error ให้สร้างใน Dashboard:
-- Storage → New bucket → name: line-ai-excel-intake → Private
-- =============================================================
insert into storage.buckets (id, name, public)
values ('line-ai-excel-intake', 'line-ai-excel-intake', false)
on conflict (id) do nothing;

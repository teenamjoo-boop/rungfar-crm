-- =============================================================
-- STAGE STORAGE-CLEANUP — ล้างไฟล์ใน Storage ที่ไม่ใช้แล้ว (อัตโนมัติทุกวัน)
--   ลบได้ 2 แบบ (Edge Function `storage-cleanup` เป็นคนลบไฟล์จริงผ่าน Storage API):
--   1) ไฟล์กำพร้าใน customer-documents / customer-photos
--      = ไม่มีเอกสาร (documents.storage_path / thumbnail_path) หรือรูปแรงงาน (customers.photo_storage_path) อ้างถึง
--        และ (อายุเกิน p_orphan_hours ชม. หรือ เป็นไฟล์ของแรงงานที่ไม่มีในระบบแล้ว)
--      → ไฟล์ที่ลบใน CRM ไปแล้ว / รูปเก่าที่ถูกเปลี่ยน / ข้อมูลทดสอบที่ลบไปแล้ว
--   2) ไฟล์ของระบบสร้าง PDF/Excel ทาง LINE (line-ai-excel-intake) + กล่องรับเอกสาร LINE (line-doc-inbox)
--      ที่อายุเกิน p_line_days วัน (ยกเว้นชุดที่กำลังรวบรวม/กำลังสร้าง)
--   ❌ ไม่แตะ: line-assets และ bucket อื่น ๆ · ไม่ลบแถวในตารางใด ๆ
--
--   ความปลอดภัย:
--   - ฟังก์ชันทั้งหมด service_role เท่านั้น (ไม่ให้ anon/authenticated เรียก)
--   - token สำหรับเรียก Edge Function เก็บใน Vault (สร้างแบบสุ่มในฐานข้อมูล ไม่มีใครต้องคัดลอก)
--   - ตั้งเวลา: pg_cron ทุกวัน 03:05 น. (เวลาไทย) → pg_net เรียก Edge Function
--
-- ลำดับติดตั้ง (ต่อ 1 environment):
--   1) Deploy Edge Function `storage-cleanup` (Verify JWT = OFF — ตรวจ token เอง)
--   2) รันไฟล์นี้
--   3) รัน "ตั้งค่า URL" ด้านล่างสุด 1 บรรทัด (คนละ URL ต่อ staging / production)
-- รันซ้ำได้
-- =============================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- A) รายการไฟล์ที่ลบได้
create or replace function public.app_storage_cleanup_candidates(
  p_line_days    integer default 3,
  p_orphan_hours integer default 24
)
returns table(bucket text, name text, reason text, size_bytes bigint)
language sql
security definer
set search_path = ''
stable
as $$
  -- 1) ไฟล์กำพร้าใน bucket ของ CRM
  select o.bucket_id::text, o.name::text,
         case when cust_gone then 'orphan_deleted_worker' else 'orphan' end,
         coalesce((o.metadata->>'size')::bigint, 0)
  from (
    select o.*,
           (o.name ~ '^customers/[0-9]+/'
            and not exists (select 1 from public.customers c
                            where c.id = (split_part(o.name, '/', 2))::bigint)) as cust_gone
    from storage.objects o
    where o.bucket_id in ('customer-documents', 'customer-photos')
  ) o
  where not exists (select 1 from public.documents d
                    where d.storage_bucket = o.bucket_id
                      and (d.storage_path = o.name or d.thumbnail_path = o.name))
    and not exists (select 1 from public.customers c
                    where c.photo_storage_bucket = o.bucket_id
                      and c.photo_storage_path = o.name)
    and (o.cust_gone
         or o.created_at < now() - make_interval(hours => greatest(coalesce(p_orphan_hours, 24), 1)))

  union all

  -- 2) ไฟล์ระบบสร้าง PDF/Excel + กล่องรับเอกสาร LINE ที่เกินอายุ
  select o.bucket_id::text, o.name::text, 'line_expired',
         coalesce((o.metadata->>'size')::bigint, 0)
  from storage.objects o
  where o.bucket_id in ('line-ai-excel-intake', 'line-doc-inbox')
    and o.created_at < now() - make_interval(days => greatest(coalesce(p_line_days, 3), 1))
    and not exists (select 1 from public.line_ai_excel_batches b
                    where b.status in ('collecting', 'finalizing')
                      and position(b.id::text in o.name) > 0)
  limit 5000;
$$;

revoke all on function public.app_storage_cleanup_candidates(integer, integer) from public, anon, authenticated;
grant execute on function public.app_storage_cleanup_candidates(integer, integer) to service_role;

-- B) token สำหรับเรียก Edge Function (สุ่มเก็บใน Vault ครั้งแรกครั้งเดียว)
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'storage_cleanup_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'storage_cleanup_token',
                                'storage-cleanup edge function token');
  end if;
end $$;

create or replace function public.app_storage_cleanup_check_token(p_token text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce(length(p_token) >= 32, false)
     and exists (select 1 from vault.decrypted_secrets s
                 where s.name = 'storage_cleanup_token' and s.decrypted_secret = p_token);
$$;

revoke all on function public.app_storage_cleanup_check_token(text) from public, anon, authenticated;
grant execute on function public.app_storage_cleanup_check_token(text) to service_role;

-- B2) บันทึก audit จาก Edge Function (service_role ไม่มีสิทธิ์เขียน audit_logs ตรง) — เฉพาะจำนวน/ขนาด ไม่มี path
create or replace function public.app_storage_cleanup_log(p_detail jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
  values ('system', 'storage-cleanup', 'system', 'storage.cleanup', 'storage', 'daily',
          coalesce(p_detail, '{}'::jsonb) - 'name' - 'names' - 'path' - 'paths');
$$;

revoke all on function public.app_storage_cleanup_log(jsonb) from public, anon, authenticated;
grant execute on function public.app_storage_cleanup_log(jsonb) to service_role;

-- C) สั่งทำงาน (ใช้ทั้งตอนตั้งเวลา และกดเองใน SQL Editor)
--    p_run = false → แค่นับ (ไม่ลบ) · true → ลบจริง
--    ผลลัพธ์: ดูได้ที่ net._http_response (id ที่คืนกลับ) และ audit_logs action = 'storage.cleanup'
create or replace function public.app_storage_cleanup_kick(p_run boolean default false)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url   text;
  v_token text;
begin
  select decrypted_secret into v_url   from vault.decrypted_secrets where name = 'storage_cleanup_url';
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'storage_cleanup_token';
  if v_url is null or v_token is null then
    raise exception 'storage_cleanup_not_configured';
  end if;
  return net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cleanup-token', v_token),
    body    := jsonb_build_object('run', coalesce(p_run, false)),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.app_storage_cleanup_kick(boolean) from public, anon, authenticated;

-- D) ตั้งเวลา: ทุกวัน 20:05 UTC = 03:05 น. เวลาไทย
select cron.unschedule(jobid) from cron.job where jobname = 'storage-cleanup-daily';
select cron.schedule('storage-cleanup-daily', '5 20 * * *', $$select public.app_storage_cleanup_kick(true);$$);

-- E) ตรวจผล — ควรได้ fn_ok = 4, token_ok = true, cron_ok = 1
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('app_storage_cleanup_candidates', 'app_storage_cleanup_check_token', 'app_storage_cleanup_kick', 'app_storage_cleanup_log')) as fn_ok,
  exists (select 1 from vault.secrets where name = 'storage_cleanup_token')                                 as token_ok,
  (select count(*) from cron.job where jobname = 'storage-cleanup-daily')                                  as cron_ok,
  exists (select 1 from vault.secrets where name = 'storage_cleanup_url')                                   as url_ok;

-- ---------- ตั้งค่า URL (รันครั้งเดียวต่อ environment — เลือกบรรทัดที่ตรงกับโปรเจกต์ที่เปิดอยู่) ----------
-- STAGING:    select vault.create_secret('https://bzwtknqvhvdmatangzqf.supabase.co/functions/v1/storage-cleanup', 'storage_cleanup_url');
-- PRODUCTION: select vault.create_secret('https://magwqolbjmwymqxelizl.supabase.co/functions/v1/storage-cleanup', 'storage_cleanup_url');

-- =============================================================
-- STAGE 48A-2 — app_admin_audit_action_summary (admin-only, READ-ONLY)
-- เป้าหมาย:
--   * สรุป "การกระทำ" จาก public.audit_logs สำหรับการ์ดแดชบอร์ด (admin เท่านั้น)
--   * อ่านอย่างเดียว — ❌ ไม่ INSERT/UPDATE/DELETE, ❌ ไม่คืน detail JSON ดิบ
--   * คืนเฉพาะ "ตัวเลขสรุป + ป้ายไทย" เท่านั้น
--     ❌ ไม่คืน storage_path / file_data / base64 / signed URL / bucket path
--
--   ตรวจสิทธิ์ admin แบบเดียวกับ app_admin_list_audit_logs:
--     เช็ครหัสผ่านผ่าน app_verify_login เดิม + ยืนยัน role='admin'
--
--   เมตริก (range = p_start_date..p_end_date เหมือน list RPC; today/7วัน = หน้าต่างคงที่ตามเวลาไทย):
--     total / today / last7 / customer / document / delete_request /
--     export / high_attention / user / line_inbox  + top actors (สูงสุด 3)
--
-- ไม่แตะ:
--   * โครงสร้าง/ข้อมูล audit_logs (อ่านอย่างเดียว), app_log_audit_event,
--     app_admin_list_audit_logs, security_login_logs, customers/documents,
--     storage, Edge Functions, LINE, Attendance, Meta Ads
--
-- ⚠️ Additive: create or replace function + grant เท่านั้น (idempotent)
-- =============================================================

create or replace function public.app_admin_audit_action_summary(
  p_admin_username text,
  p_admin_password text,
  p_start_date     date default null,
  p_end_date       date default null
)
returns table (
  metric_key   text,
  metric_label text,
  metric_value integer,
  metric_group text,
  sort_order   integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok          integer := 0;
  v_admin       boolean := false;
  v_today_start timestamptz;
  v_week_start  timestamptz;
begin
  -- ── 1) ตรวจรหัสผ่าน admin ด้วย RPC login เดิม (scheme เดียวกับ list RPC) ──
  select count(*) into v_ok
  from public.app_verify_login(p_username := p_admin_username, p_password := p_admin_password);
  if coalesce(v_ok, 0) < 1 then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── 2) ยืนยันว่าเป็น admin จริง (DEFINER อ่าน app_users ได้แม้ RLS ปิด) ──
  select (lower(coalesce(u.role, '')) = 'admin') into v_admin
  from public.app_users u where u.username = p_admin_username limit 1;
  if not coalesce(v_admin, false) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- ── หน้าต่างเวลาไทย สำหรับ today / 7 วันล่าสุด (อิสระจากช่วงที่เลือก) ──
  v_today_start := (((now() at time zone 'Asia/Bangkok')::date)::timestamp) at time zone 'Asia/Bangkok';
  v_week_start  := ((((now() at time zone 'Asia/Bangkok')::date) - 6)::timestamp) at time zone 'Asia/Bangkok';

  -- ── 3) คืนเมตริก (อ่านอย่างเดียว) — count เท่านั้น ไม่มี detail ดิบ ──
  return query
  with f as (
    -- ช่วงที่เลือก: predicate เดียวกับ app_admin_list_audit_logs
    select a.action, a.actor_code, a.actor_name
    from public.audit_logs a
    where (p_start_date is null or a.created_at >= p_start_date::timestamptz)
      and (p_end_date   is null or a.created_at <  ((p_end_date + 1))::timestamptz)
  ),
  agg as (
    select
      count(*)::int                                                                          as c_total,
      count(*) filter (where action like 'customer.%')::int                                  as c_customer,
      count(*) filter (where action like 'document.%')::int                                  as c_document,
      count(*) filter (where action like 'delete\_request.%')::int                           as c_delreq,
      count(*) filter (where action like '%.export')::int                                    as c_export,
      count(*) filter (where action like 'user.%')::int                                      as c_user,
      count(*) filter (where action like 'line\_inbox.%')::int                               as c_line,
      count(*) filter (where action in (
        'delete_request.create','delete_request.approve','delete_request.reject',
        'customer.export','user.disable','user.enable',
        'line_inbox.approve','line_inbox.reject'))::int                                       as c_high
    from f
  ),
  tdy as (
    select count(*)::int as c_today from public.audit_logs where created_at >= v_today_start
  ),
  wk as (
    select count(*)::int as c_week from public.audit_logs where created_at >= v_week_start
  ),
  actors as (
    select who, c, row_number() over (order by c desc, who) as rn
    from (
      select coalesce(nullif(btrim(coalesce(actor_name, '')), ''), actor_code, '—') as who,
             count(*)::int as c
      from f
      group by 1
    ) g
    order by c desc, who
    limit 3
  )
  select * from (
    select 'total'::text,          'การกระทำทั้งหมด'::text, (select c_total    from agg), 'headline'::text, 1
    union all select 'today',          'วันนี้',              (select c_today    from tdy), 'headline', 2
    union all select 'last7',          '7 วันล่าสุด',          (select c_week     from wk),  'headline', 3
    union all select 'customer',       'งานลูกค้า',            (select c_customer from agg), 'headline', 4
    union all select 'document',       'งานเอกสาร',            (select c_document from agg), 'headline', 5
    union all select 'delete_request', 'คำขอลบ',              (select c_delreq   from agg), 'headline', 6
    union all select 'export',         'ส่งออกข้อมูล',         (select c_export   from agg), 'headline', 7
    union all select 'high_attention', 'งานที่ควรตรวจสอบ',     (select c_high     from agg), 'headline', 8
    union all select 'user',           'จัดการผู้ใช้',         (select c_user     from agg), 'secondary', 9
    union all select 'line_inbox',     'เอกสารจาก LINE',       (select c_line     from agg), 'secondary', 10
  ) m(metric_key, metric_label, metric_value, metric_group, sort_order)
  union all
  select 'actor_' || a.rn::text, a.who, a.c, 'actor', (20 + a.rn)::int
  from actors a
  order by sort_order;
end;
$$;

-- สิทธิ์เรียกใช้: เปิดให้ anon/authenticated (ฟังก์ชันบังคับตรวจ admin credential ภายในก่อนคืนข้อมูลเสมอ)
revoke all on function public.app_admin_audit_action_summary(text, text, date, date) from public;
grant execute on function public.app_admin_audit_action_summary(text, text, date, date) to anon, authenticated;

-- =============================================================
-- STAGE DASH-LINE-STATUS-2 — ป้าย "แจ้งนายจ้างทาง LINE แล้ว" นับเฉพาะกลุ่มที่ผูกอยู่ตอนนี้
--   เดิม: นับทุกครั้งที่เคยส่ง รวมที่ส่งเข้า "กลุ่มทดสอบ" → หน้าหลักขึ้นว่าแจ้งแล้ว ทั้งที่กลุ่มจริงยังไม่ได้รับ
--   ใหม่: นับเฉพาะที่ส่งเข้ากลุ่ม LINE ที่ (1) ยังผูกกับนายจ้าง/กลุ่มของแรงงานคนนั้น (2) เปิดแจ้งเตือน (3) บอทยังอยู่ในกลุ่ม
--   * ไม่ลบประวัติการส่ง (line_doc_alert_log) — ระบบส่งกันซ้ำ "แยกต่อกลุ่ม LINE" อยู่แล้ว
--     กลุ่มจริงจึงได้รับรายการเหล่านี้ตามรอบ 09:00 ตามปกติ
-- ต้องรันหลัง 20261023_line_alert_status.sql · อ่านอย่างเดียว · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

create or replace function public.app_line_alert_status(p_user_id text, p_username text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.app_users u
                  where u.id::text = p_user_id and u.username = p_username and coalesce(u.is_active, true) and u.role is not null) then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'sent', (select coalesce(jsonb_agg(jsonb_build_array(x.customer_id, x.kind, x.expiry, x.sent_at)), '[]'::jsonb)
               from (select l.customer_id, l.kind, l.expiry, min(l.sent_at) sent_at
                       from public.line_doc_alert_log l
                       join public.line_doc_alert_targets t on t.line_group_id = l.line_group_id and t.enabled
                       join public.line_bot_groups b on b.group_id = t.line_group_id and b.is_active
                       join public.customers c on c.id = l.customer_id
                      where not l.skipped and l.sent_at > now() - interval '180 days'
                        and ((t.employer_id is not null and c.employer_id = t.employer_id)
                          or (t.group_id is not null and c.group_id = t.group_id))
                      group by 1, 2, 3) x),
    'employers', (select coalesce(jsonb_agg(distinct t.employer_id), '[]'::jsonb) from public.line_doc_alert_targets t
                    join public.line_bot_groups b on b.group_id = t.line_group_id and b.is_active
                   where t.enabled and t.employer_id is not null),
    'groups', (select coalesce(jsonb_agg(distinct t.group_id), '[]'::jsonb) from public.line_doc_alert_targets t
                 join public.line_bot_groups b on b.group_id = t.line_group_id and b.is_active
                where t.enabled and t.group_id is not null));
end;
$$;

revoke all on function public.app_line_alert_status(text, text) from public;
grant execute on function public.app_line_alert_status(text, text) to anon, authenticated;

-- ---------- ตรวจผล ----------
-- fn_ok = 1 · ส่งเข้ากลุ่มที่ผูกอยู่ = ป้ายที่จะเห็น · ส่งเข้ากลุ่มอื่น (เช่นกลุ่มทดสอบ) = ไม่นับแล้ว
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'app_line_alert_status') as fn_ok,
       (select count(*) from public.line_doc_alert_log l
          join public.line_doc_alert_targets t on t.line_group_id = l.line_group_id and t.enabled
         where not l.skipped) as sent_to_bound_groups,
       (select count(*) from public.line_doc_alert_log l
         where not l.skipped and not exists (select 1 from public.line_doc_alert_targets t
                                              where t.line_group_id = l.line_group_id and t.enabled)) as sent_to_other_groups;

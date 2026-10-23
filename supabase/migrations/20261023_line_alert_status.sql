-- =============================================================
-- STAGE DASH-LINE-STATUS — หน้าหลัก CRM แสดงว่า "แจ้งนายจ้างทาง LINE แล้ว"
--   app_line_alert_status(user_id, username) → { sent: [[customer_id, kind, expiry, sent_at]...],
--                                                 employers: [employer_id...], groups: [group_id...] }
--   * sent      = เอกสารที่ส่งเข้ากลุ่ม LINE แล้ว (ไม่นับที่กด "ข้าม") ของ 180 วันล่าสุด
--   * employers/groups = นายจ้าง/กลุ่มที่ผูกกลุ่ม LINE และเปิดแจ้งเตือนอยู่
--   ผู้ใช้ CRM ที่ active ทุกคนเรียกได้ (ตรวจ app_users แบบเดียวกับ app_get_alert_settings) · มีแค่ id/ประเภท/วันที่ ไม่มีชื่อ
-- ต้องรันหลัง 20261022c_line_doc_alert.sql · อ่านอย่างเดียว · รันซ้ำได้ · รันบน STAGING ก่อน
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
                      where not l.skipped and l.sent_at > now() - interval '180 days'
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

-- ---------- ตรวจผล — ควรได้ fn_ok = 1 ----------
select count(*) as fn_ok from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'app_line_alert_status';

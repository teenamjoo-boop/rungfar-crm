-- =============================================================
-- STAGE LINE-DOC-ALERT — แจ้งเตือนเอกสารใกล้หมดอายุ เข้ากลุ่ม LINE ของนายจ้าง (บอทมีตัง)
--   * ผูกกลุ่ม LINE (ที่บอทอยู่ = public.line_bot_groups) กับ "นายจ้าง" หรือ "กลุ่ม" (เช่น สวนยาง) — 1 กลุ่ม LINE ผูกได้ 1 อย่าง
--   * ใช้วันแจ้งเตือนล่วงหน้าเดียวกับ CRM (public.app_alert_settings: พาสปอร์ต / VISA / Work Permit / 90 วัน / MOU)
--   * เอกสาร 1 ชิ้น (แรงงาน × ประเภท × วันหมดอายุ) เตือนในกลุ่มครั้งเดียว — ต่ออายุแล้ว (วันหมดอายุใหม่) ถึงจะเตือนรอบใหม่
--   * เตือนเฉพาะเอกสารที่ยังไม่หมดอายุ · ไม่นับแรงงานที่ลบแล้ว / ปิดใช้งาน / ลาออก
--   * ส่งทุกวัน 09:00 น. (เวลาไทย) เฉพาะกลุ่มที่ "เปิดแจ้งเตือน" และมีรายการใหม่ — ไม่มีรายการ = ไม่ส่ง (ไม่เปลืองโควตา LINE)
--   * Edge Function `line-doc-alert` เป็นคนส่งข้อความ (LINE Messaging API push) แล้วบันทึกว่าส่งแล้ว
--
--   ความปลอดภัย:
--   - ตารางใหม่ RLS เปิด 0 policy · ไม่เก็บข้อมูลส่วนตัว (เก็บแค่ id กลุ่ม LINE / id แรงงาน / ประเภท / วันหมดอายุ)
--   - หน้าจอ CRM เรียกผ่าน RPC app_line_alert_* (admin เท่านั้น — ตรวจ app_users แบบเดียวกับ app_save_alert_settings)
--   - Edge Function เรียกผ่าน RPC line_doc_alert_* (service_role เท่านั้น) · token อยู่ใน Vault (สุ่มในฐานข้อมูล ไม่ต้องคัดลอก)
--
-- ลำดับติดตั้ง (ต่อ 1 environment):
--   1) Deploy Edge Function `line-doc-alert` (Verify JWT = OFF — ตรวจ token เอง) · ต้องมี secret LINE_CHANNEL_ACCESS_TOKEN
--   2) รันไฟล์นี้
--   3) รัน "ตั้งค่า URL" ด้านล่างสุด 1 บรรทัด (คนละ URL ต่อ staging / production)
-- ต้องรันหลัง 20261009_app_alert_settings.sql และ 20260815_line_bot_groups_foundation.sql · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- -------------------------------------------------------------
-- A) ตาราง
-- -------------------------------------------------------------
create table if not exists public.line_doc_alert_targets (
  line_group_id   text primary key references public.line_bot_groups(group_id) on delete cascade,
  employer_id     bigint null references public.employers(id) on delete cascade,
  group_id        bigint null references public.groups(id) on delete cascade,
  enabled         boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by_code text null,
  constraint line_doc_alert_targets_one check (num_nonnulls(employer_id, group_id) = 1)
);
comment on table public.line_doc_alert_targets is
  'LINE-DOC-ALERT: กลุ่ม LINE ไหน = นายจ้าง/กลุ่มไหน และเปิดแจ้งเตือนเอกสารหรือไม่ (ไม่มีข้อมูลส่วนตัว)';

create table if not exists public.line_doc_alert_log (
  id            bigint generated always as identity primary key,
  line_group_id text   not null,
  customer_id   bigint not null,
  kind          text   not null check (kind in ('passport','visa','wp','d90','mou')),
  expiry        date   not null,
  skipped       boolean not null default false,       -- true = กด "ข้ามรายการเดิม" (ไม่ได้ส่งจริง)
  sent_at       timestamptz not null default now(),
  constraint line_doc_alert_log_once unique (line_group_id, customer_id, kind, expiry)
);
comment on table public.line_doc_alert_log is
  'LINE-DOC-ALERT: เอกสารที่เตือนเข้ากลุ่มแล้ว (กันเตือนซ้ำ) — id/ประเภท/วันหมดอายุ เท่านั้น ไม่มีชื่อ/เลขเอกสาร';

alter table public.line_doc_alert_targets enable row level security;
alter table public.line_doc_alert_log     enable row level security;
revoke all on table public.line_doc_alert_targets from public, anon, authenticated;
revoke all on table public.line_doc_alert_log     from public, anon, authenticated;

-- bucket สาธารณะสำหรับรูปในการ์ด LINE (ไอคอนสี + รูปพื้นหลังนายจ้างที่ย่อแล้ว) — LINE ต้องดึงรูปจาก URL https ได้ตรง ๆ
--   เก็บเฉพาะรูปพื้นหลังหน้าลิงก์ (ไม่ใช่เอกสารแรงงาน) · ชื่อไฟล์สุ่มจาก path ต้นฉบับ (เดาไม่ได้)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('line-alert-media', 'line-alert-media', true, 2097152, array['image/jpeg','image/png'])
on conflict (id) do nothing;

-- -------------------------------------------------------------
-- B) ตัวช่วย
-- -------------------------------------------------------------
-- รหัสสั้นในลิงก์ /s/<รหัส> — ตรงกับ _shareCode() ใน CRM: base62 ของ 16 ตัวแรกของ token (64 บิต) เติม 0 ให้ครบ 11 ตัว
create or replace function public.line_doc_alert_share_code(p_token text)
returns text language plpgsql immutable set search_path = '' as $$
declare
  a  constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  h  text := lower(left(coalesce(p_token,''),16));
  n  numeric := 0;
  s  text := '';
  i  integer;
begin
  if h !~ '^[0-9a-f]{16}$' then return null; end if;
  for i in 1..16 loop n := n * 16 + position(substr(h,i,1) in '0123456789abcdef') - 1; end loop;
  while n > 0 loop
    s := substr(a, (mod(n,62))::int + 1, 1) || s;
    n := div(n, 62);
  end loop;
  return lpad(s, 11, '0');
end;
$$;

-- วันที่แบบไทยสั้น: 2026-12-15 → "15 ธ.ค. 69"
create or replace function public.line_doc_alert_thdate(p_d date)
returns text language sql immutable set search_path = '' as $$
  select extract(day from p_d)::int || ' ' ||
         (array['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'])[extract(month from p_d)::int] || ' ' ||
         right((extract(year from p_d)::int + 543)::text, 2);
$$;

-- -------------------------------------------------------------
-- C) รายการที่ถึงเวลาเตือน (ยังไม่เคยเตือน) ต่อกลุ่ม LINE
--    p_line_group_id null = ทุกกลุ่ม · p_include_disabled = รวมกลุ่มที่ยังปิดอยู่ (ใช้ดูตัวอย่าง)
-- -------------------------------------------------------------
create or replace function public.line_doc_alert_due(p_line_group_id text default null, p_include_disabled boolean default false)
returns table (line_group_id text, target_kind text, target_name text, share_token text,
               customer_id bigint, worker_name text, employer_name text, kind text, expiry date, days_left integer)
language sql stable security definer set search_path = '' as $$
  with st as (select coalesce(s.passport,60) passport, coalesce(s.visa,60) visa, coalesce(s.wp,60) wp,
                     coalesce(s.next90,15) next90, coalesce(s.mou,60) mou
                from (select 1) one left join public.app_alert_settings s on s.id = 1),
       td as (select (now() at time zone 'Asia/Bangkok')::date d),
       t as (select x.line_group_id, x.employer_id, x.group_id,
                    case when x.employer_id is not null then 'employer' else 'group' end tk,
                    coalesce(e.name, g.name) tname,
                    case when x.employer_id is not null
                      then (select l.token from public.employer_share_links l where l.employer_id = x.employer_id
                              and l.revoked_at is null and (l.expires_at is null or l.expires_at > now()) order by l.id desc limit 1)
                      else (select l.token from public.group_share_links l where l.group_id = x.group_id
                              and l.revoked_at is null and (l.expires_at is null or l.expires_at > now()) order by l.id desc limit 1)
                    end tok
               from public.line_doc_alert_targets x
               join public.line_bot_groups b on b.group_id = x.line_group_id and b.is_active
               left join public.employers e on e.id = x.employer_id
               left join public.groups g on g.id = x.group_id
              where (x.enabled or p_include_disabled)
                and (p_line_group_id is null or x.line_group_id = p_line_group_id)),
       w as (select t.line_group_id, t.tk, t.tname, t.tok, c.id cid,
                    coalesce(nullif(btrim(c.name),''), nullif(btrim(c.name_th),''), '-') wname,
                    (select em.name from public.employers em where em.id = c.employer_id) ename,
                    c.exp_passport, c.exp_visa, c.exp_wp, c.next_90, c.exp_mou
               from t join public.customers c
                 on (t.employer_id is not null and c.employer_id = t.employer_id)
                 or (t.group_id is not null and c.group_id = t.group_id)
              where c.deleted_at is null and coalesce(c.status,'active') not in ('inactive','resigned')),
       it as (select w.*, k.kind, k.dt, k.win
                from w cross join st
                cross join lateral (values ('passport', w.exp_passport, st.passport), ('visa', w.exp_visa, st.visa),
                                           ('wp', w.exp_wp, st.wp), ('d90', w.next_90, st.next90), ('mou', w.exp_mou, st.mou)) k(kind, dt, win))
  select it.line_group_id, it.tk, it.tname, it.tok, it.cid, it.wname, it.ename, it.kind, it.dt, (it.dt - td.d)::int
    from it cross join td
   where it.dt is not null and it.dt >= td.d and (it.dt - td.d) <= it.win
     and not exists (select 1 from public.line_doc_alert_log l
                      where l.line_group_id = it.line_group_id and l.customer_id = it.cid and l.kind = it.kind and l.expiry = it.dt)
   order by it.line_group_id, it.dt, it.wname, it.cid, it.kind;
$$;

-- -------------------------------------------------------------
-- D) ข้อความที่จะส่ง (1 แถวต่อกลุ่ม LINE)
--    card  = ข้อมูลสำหรับการ์ด LINE (Flex) — Edge Function สร้างการ์ดจากตรงนี้ · CRM ใช้แสดงตัวอย่าง
--    parts = ข้อความธรรมดา (สำรอง ถ้าส่งการ์ดไม่ผ่าน) แบ่งเป็นชิ้นละไม่เกิน ~4,500 ตัวอักษร
--    p_share_base เช่น 'https://rungfa.com' (ระบบจริง) · 'https://rungfa.com/st' (ระบบทดสอบ)
-- -------------------------------------------------------------
drop function if exists public.line_doc_alert_messages(text, boolean, text);
create or replace function public.line_doc_alert_messages(p_line_group_id text default null, p_include_disabled boolean default false,
                                                          p_share_base text default 'https://rungfa.com')
returns table (line_group_id text, target_name text, item_count integer, items jsonb, parts text[], card jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  g        record;
  r        record;
  v_lines  text[];
  v_cur    text;
  v_parts  text[];
  v_head   text;
  v_foot   text;
  v_items  jsonb;
  v_n      integer;
  v_last   bigint;
  v_no     integer;
  v_line   text;
  v_lbl    text;
  v_code   text;
  v_url    text;
  v_wk     jsonb;
  v_docs   jsonb;
  v_ename  text;
  v_wname  text;
  v_tg     record;
  v_bn     jsonb;
begin
  for g in select d.line_group_id, max(d.target_name) tname, max(d.target_kind) tk, max(d.share_token) tok, count(*)::int cnt
             from public.line_doc_alert_due(p_line_group_id, p_include_disabled) d
            group by d.line_group_id order by d.line_group_id loop
    v_head := '🔔 แจ้งเตือนเอกสารใกล้หมดอายุ' || chr(10) || coalesce(g.tname,'');
    v_code := public.line_doc_alert_share_code(g.tok);
    v_url  := case when v_code is not null then rtrim(coalesce(p_share_base,'https://rungfa.com'),'/') || '/s/' || v_code end;
    -- รูปพื้นหลังหน้าลิงก์ (share_banner) — เหมือนหน้าลิงก์: กลุ่มใช้ของกลุ่มก่อน ไม่มีค่อยใช้รูปล่าสุดของนายจ้างในกลุ่ม
    select x.employer_id, x.group_id into v_tg from public.line_doc_alert_targets x where x.line_group_id = g.line_group_id;
    v_bn := null;
    if v_tg.employer_id is not null then
      select jsonb_build_object('id', d.id, 'bucket', coalesce(d.storage_bucket,'customer-documents'), 'path', d.storage_path) into v_bn
        from public.documents d where d.owner_type = 'employer' and d.owner_id = v_tg.employer_id and d.doc_type = 'share_banner'
         and d.storage_path is not null order by d.created_at desc limit 1;
    elsif v_tg.group_id is not null then
      select jsonb_build_object('id', d.id, 'bucket', coalesce(d.storage_bucket,'customer-documents'), 'path', d.storage_path) into v_bn
        from public.documents d where d.owner_type = 'group' and d.owner_id = v_tg.group_id and d.doc_type = 'share_banner'
         and d.storage_path is not null order by d.created_at desc limit 1;
      if v_bn is null then
        select jsonb_build_object('id', d.id, 'bucket', coalesce(d.storage_bucket,'customer-documents'), 'path', d.storage_path) into v_bn
          from public.documents d where d.owner_type = 'employer' and d.doc_type = 'share_banner' and d.storage_path is not null
           and d.owner_id in (select c.employer_id from public.customers c where c.group_id = v_tg.group_id and c.deleted_at is null)
         order by d.created_at desc limit 1;
      end if;
    end if;
    v_foot := chr(10) ||
              case when v_url is not null then 'ดูรายละเอียด: ' || v_url || chr(10) else '' end ||
              'สอบถาม/ต่อเอกสาร: บริษัท รุ่งฟ้า รุ่งฟ้า จำกัด โทร 096-823-4891';
    v_lines := array[]::text[]; v_items := '[]'::jsonb; v_last := null; v_no := 0; v_wk := '[]'::jsonb; v_docs := '[]'::jsonb;
    for r in select * from public.line_doc_alert_due(g.line_group_id, p_include_disabled) d
              order by d.worker_name, d.customer_id, d.expiry, d.kind loop
      if v_last is distinct from r.customer_id then
        if v_last is not null then
          v_wk := v_wk || jsonb_build_array(jsonb_build_object('name', v_wname, 'employer', v_ename, 'docs', v_docs));
        end if;
        v_docs := '[]'::jsonb; v_wname := r.worker_name;
        v_ename := case when g.tk = 'group' and coalesce(r.employer_name,'') <> '' then r.employer_name end;
        v_no := v_no + 1; v_last := r.customer_id;
        v_lines := v_lines || (chr(10) || v_no || '. ' || r.worker_name ||
                               case when g.tk = 'group' and coalesce(r.employer_name,'') <> '' then ' (' || r.employer_name || ')' else '' end);
      end if;
      v_lbl := case r.kind when 'passport' then 'พาสปอร์ต หมด' when 'visa' then 'วีซ่า หมด' when 'wp' then 'ใบอนุญาตทำงาน หมด'
                           when 'd90' then 'รายงานตัว 90 วัน ครบ' else 'MOU หมด' end;
      v_line := '   • ' || v_lbl || ' ' || public.line_doc_alert_thdate(r.expiry) ||
                case when r.days_left = 0 then ' (วันนี้)' else ' (อีก ' || r.days_left || ' วัน)' end;
      v_lines := v_lines || v_line;
      v_items := v_items || jsonb_build_object('customer_id', r.customer_id, 'kind', r.kind, 'expiry', r.expiry);
      v_docs  := v_docs  || jsonb_build_array(jsonb_build_object('kind', r.kind,
                              'label', case r.kind when 'passport' then 'พาสปอร์ต' when 'visa' then 'วีซ่า' when 'wp' then 'ใบอนุญาตทำงาน'
                                                   when 'd90' then 'รายงานตัว 90 วัน' else 'MOU' end,
                              'date', public.line_doc_alert_thdate(r.expiry), 'days', r.days_left));
    end loop;
    if v_last is not null then
      v_wk := v_wk || jsonb_build_array(jsonb_build_object('name', v_wname, 'employer', v_ename, 'docs', v_docs));
    end if;

    -- แบ่งข้อความ (LINE รับข้อความละไม่เกิน 5,000 ตัวอักษร)
    v_parts := array[]::text[]; v_cur := v_head;
    foreach v_line in array v_lines loop
      if length(v_cur) + length(v_line) + 1 > 4500 then
        v_parts := v_parts || v_cur; v_cur := '(ต่อ) ' || coalesce(g.tname,'');
      end if;
      v_cur := v_cur || chr(10) || v_line;
    end loop;
    v_cur := v_cur || chr(10) || v_foot;
    v_parts := v_parts || v_cur;

    line_group_id := g.line_group_id; target_name := g.tname; item_count := g.cnt; items := v_items; parts := v_parts;
    card := jsonb_build_object('target', coalesce(g.tname,''), 'target_kind', g.tk, 'url', v_url, 'count', g.cnt, 'workers', v_wk, 'banner', v_bn);
    return next;
  end loop;
end;
$$;

-- -------------------------------------------------------------
-- E) บันทึกว่าเตือนแล้ว (Edge Function เรียกหลังส่งสำเร็จ)
-- -------------------------------------------------------------
create or replace function public.line_doc_alert_mark(p_line_group_id text, p_items jsonb, p_skipped boolean default false)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_n integer;
begin
  if jsonb_typeof(p_items) <> 'array' then return 0; end if;
  insert into public.line_doc_alert_log (line_group_id, customer_id, kind, expiry, skipped)
  select p_line_group_id, (x->>'customer_id')::bigint, x->>'kind', (x->>'expiry')::date, coalesce(p_skipped,false)
    from jsonb_array_elements(p_items) x
   where x->>'kind' in ('passport','visa','wp','d90','mou')
  on conflict on constraint line_doc_alert_log_once do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- audit จาก Edge Function — จำนวนเท่านั้น
create or replace function public.line_doc_alert_audit(p_detail jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
  values ('system', 'line-doc-alert', 'system', 'line.doc_alert.send', 'line_group', 'daily',
          jsonb_build_object('groups', p_detail->'groups', 'sent', p_detail->'sent', 'items', p_detail->'items', 'failed', p_detail->'failed'));
$$;

-- -------------------------------------------------------------
-- F) token (Vault) + สั่งทำงาน
-- -------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'line_doc_alert_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'line_doc_alert_token');
  end if;
end $$;

create or replace function public.line_doc_alert_check_token(p_token text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(length(p_token) >= 32, false)
     and exists (select 1 from vault.decrypted_secrets s where s.name = 'line_doc_alert_token' and s.decrypted_secret = p_token);
$$;

-- p_line_group_id null = ทุกกลุ่มที่เปิดแจ้งเตือนและมีรายการ (ใช้กับตั้งเวลา) — เรียก Edge Function ทีละกลุ่ม (กันเกินเวลา CPU)
-- ระบุกลุ่ม = ส่งเฉพาะกลุ่มนั้น (ปุ่ม "ส่งตอนนี้") · คืนค่า = id คำขอล่าสุด (0 = ไม่มีกลุ่มที่ต้องส่ง)
create or replace function public.line_doc_alert_kick(p_line_group_id text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_url text; v_token text; v_id bigint := 0; g record;
begin
  select decrypted_secret into v_url   from vault.decrypted_secrets where name = 'line_doc_alert_url';
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'line_doc_alert_token';
  if v_url is null or v_token is null then raise exception 'line_doc_alert_not_configured'; end if;
  for g in select x.line_group_id from public.line_doc_alert_targets x
            where x.enabled and (p_line_group_id is null or x.line_group_id = p_line_group_id)
              and (p_line_group_id is not null or exists (select 1 from public.line_doc_alert_due(x.line_group_id, false)))
            order by x.line_group_id loop
    v_id := net.http_post(
      url     := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-alert-token', v_token),
      body    := jsonb_build_object('group', g.line_group_id),
      timeout_milliseconds := 60000
    );
  end loop;
  return v_id;
end;
$$;

-- -------------------------------------------------------------
-- G) RPC สำหรับหน้าจอ CRM (admin เท่านั้น)
-- -------------------------------------------------------------
create or replace function public.app_line_alert_admin(p_user_id text, p_username text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_role text;
begin
  select u.role into v_role from public.app_users u
   where u.id::text = p_user_id and u.username = p_username and coalesce(u.is_active, true) and u.role is not null limit 1;
  if v_role is distinct from 'admin' then raise exception 'unauthorized' using errcode = 'P0001'; end if;
  return p_username;
end;
$$;

-- รายชื่อกลุ่ม LINE ที่บอทอยู่ + ผูกกับใคร + เปิด/ปิด + รายการที่รอเตือน
create or replace function public.app_line_alert_groups(p_user_id text, p_username text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public.app_line_alert_admin(p_user_id, p_username);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'line_group_id', b.group_id,
            'name', coalesce(nullif(btrim(b.display_label),''), nullif(btrim(b.group_name),''), 'กลุ่มไม่มีชื่อ'),
            'group_type', b.group_type,
            'joined_at', b.joined_at,
            'employer_id', x.employer_id, 'group_id', x.group_id,
            'target_name', coalesce(e.name, g.name),
            'enabled', coalesce(x.enabled, false),
            'pending', case when x.line_group_id is null then 0
                            else (select count(*) from public.line_doc_alert_due(b.group_id, true)) end,
            'last_sent', (select max(l.sent_at) from public.line_doc_alert_log l where l.line_group_id = b.group_id and not l.skipped))
          order by (x.line_group_id is null), coalesce(nullif(btrim(b.display_label),''), b.group_name)), '[]'::jsonb)
          from public.line_bot_groups b
          left join public.line_doc_alert_targets x on x.line_group_id = b.group_id
          left join public.employers e on e.id = x.employer_id
          left join public.groups g on g.id = x.group_id
         where b.is_active);
end;
$$;

-- ผูก/เปลี่ยน/เลิกผูก + เปิด/ปิด  (employer_id และ group_id ว่างทั้งคู่ = เลิกผูก)
create or replace function public.app_line_alert_save(p_user_id text, p_username text, p_line_group_id text,
                                                      p_employer_id bigint default null, p_group_id bigint default null,
                                                      p_enabled boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user text;
begin
  v_user := public.app_line_alert_admin(p_user_id, p_username);
  if not exists (select 1 from public.line_bot_groups b where b.group_id = p_line_group_id and b.is_active) then
    return jsonb_build_object('ok', false, 'error', 'group_not_found');
  end if;
  if p_employer_id is null and p_group_id is null then
    delete from public.line_doc_alert_targets where line_group_id = p_line_group_id;
  else
    if p_employer_id is not null and p_group_id is not null then return jsonb_build_object('ok', false, 'error', 'choose_one'); end if;
    if p_employer_id is not null and not exists (select 1 from public.employers e where e.id = p_employer_id) then
      return jsonb_build_object('ok', false, 'error', 'employer_not_found');
    end if;
    if p_group_id is not null and not exists (select 1 from public.groups g where g.id = p_group_id) then
      return jsonb_build_object('ok', false, 'error', 'group_not_found');
    end if;
    insert into public.line_doc_alert_targets (line_group_id, employer_id, group_id, enabled, updated_by_code)
    values (p_line_group_id, p_employer_id, p_group_id, coalesce(p_enabled,false), v_user)
    on conflict (line_group_id) do update
       set employer_id = excluded.employer_id, group_id = excluded.group_id, enabled = excluded.enabled,
           updated_at = now(), updated_by_code = excluded.updated_by_code;
  end if;
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (v_user, v_user, 'admin', 'line.doc_alert.target', 'line_group', p_line_group_id,
            jsonb_build_object('employer_id', p_employer_id, 'group_id', p_group_id, 'enabled', coalesce(p_enabled,false)));
  exception when others then null; end;
  return jsonb_build_object('ok', true);
end;
$$;

-- ดูตัวอย่างข้อความที่จะส่ง (ไม่ส่งจริง)
create or replace function public.app_line_alert_preview(p_user_id text, p_username text, p_line_group_id text,
                                                         p_share_base text default 'https://rungfa.com')
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public.app_line_alert_admin(p_user_id, p_username);
  return coalesce((select jsonb_build_object('count', m.item_count, 'parts', to_jsonb(m.parts), 'card', m.card)
                     from public.line_doc_alert_messages(p_line_group_id, true, p_share_base) m limit 1),
                  jsonb_build_object('count', 0, 'parts', '[]'::jsonb));
end;
$$;

-- ส่งตอนนี้ (เฉพาะกลุ่มที่เปิดแจ้งเตือน)
create or replace function public.app_line_alert_send_now(p_user_id text, p_username text, p_line_group_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public.app_line_alert_admin(p_user_id, p_username);
  if not exists (select 1 from public.line_doc_alert_targets x where x.line_group_id = p_line_group_id and x.enabled) then
    return jsonb_build_object('ok', false, 'error', 'not_enabled');
  end if;
  if not exists (select 1 from vault.secrets where name = 'line_doc_alert_url') then
    return jsonb_build_object('ok', false, 'error', 'url_not_set');   -- ยังไม่ได้รันบรรทัด "ตั้งค่า URL" ท้ายไฟล์ SQL
  end if;
  return jsonb_build_object('ok', true, 'request_id', public.line_doc_alert_kick(p_line_group_id));
end;
$$;

-- ข้ามรายการที่ค้างอยู่ตอนนี้ (บันทึกว่า "เตือนแล้ว" โดยไม่ส่ง) — ใช้ตอนเริ่มใช้ ถ้าไม่อยากให้ส่งของเก่าทั้งหมด
create or replace function public.app_line_alert_skip(p_user_id text, p_username text, p_line_group_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user text; v_n integer;
begin
  v_user := public.app_line_alert_admin(p_user_id, p_username);
  v_n := public.line_doc_alert_mark(p_line_group_id,
           coalesce((select jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'kind', d.kind, 'expiry', d.expiry))
                       from public.line_doc_alert_due(p_line_group_id, true) d), '[]'::jsonb), true);
  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (v_user, v_user, 'admin', 'line.doc_alert.skip', 'line_group', p_line_group_id, jsonb_build_object('items', v_n));
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'skipped', v_n);
end;
$$;

-- -------------------------------------------------------------
-- H) สิทธิ์
-- -------------------------------------------------------------
revoke all on function public.line_doc_alert_share_code(text)                      from public, anon, authenticated;
revoke all on function public.line_doc_alert_thdate(date)                          from public, anon, authenticated;
revoke all on function public.line_doc_alert_due(text, boolean)                    from public, anon, authenticated;
revoke all on function public.line_doc_alert_messages(text, boolean, text)         from public, anon, authenticated;
revoke all on function public.line_doc_alert_mark(text, jsonb, boolean)            from public, anon, authenticated;
revoke all on function public.line_doc_alert_audit(jsonb)                          from public, anon, authenticated;
revoke all on function public.line_doc_alert_check_token(text)                     from public, anon, authenticated;
revoke all on function public.line_doc_alert_kick(text)                            from public, anon, authenticated;
revoke all on function public.app_line_alert_admin(text, text)                     from public, anon, authenticated;
grant execute on function public.line_doc_alert_messages(text, boolean, text) to service_role;
grant execute on function public.line_doc_alert_mark(text, jsonb, boolean)    to service_role;
grant execute on function public.line_doc_alert_audit(jsonb)                  to service_role;
grant execute on function public.line_doc_alert_check_token(text)             to service_role;

revoke all on function public.app_line_alert_groups(text, text)                         from public;
revoke all on function public.app_line_alert_save(text, text, text, bigint, bigint, boolean) from public;
revoke all on function public.app_line_alert_preview(text, text, text, text)            from public;
revoke all on function public.app_line_alert_send_now(text, text, text)                 from public;
revoke all on function public.app_line_alert_skip(text, text, text)                     from public;
grant execute on function public.app_line_alert_groups(text, text)                         to anon, authenticated;
grant execute on function public.app_line_alert_save(text, text, text, bigint, bigint, boolean) to anon, authenticated;
grant execute on function public.app_line_alert_preview(text, text, text, text)            to anon, authenticated;
grant execute on function public.app_line_alert_send_now(text, text, text)                 to anon, authenticated;
grant execute on function public.app_line_alert_skip(text, text, text)                     to anon, authenticated;

-- -------------------------------------------------------------
-- I) ตั้งเวลา: ทุกวัน 02:00 UTC = 09:00 น. เวลาไทย
-- -------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'line-doc-alert-daily';
select cron.schedule('line-doc-alert-daily', '0 2 * * *', $$select public.line_doc_alert_kick(null);$$);

-- ---------- ตรวจผล — ควรได้ tbl_ok = 2, fn_ok = 14, token_ok = true, cron_ok = 1, anon_internal = 0, media_ok = 1 ----------
select
  (select count(*) from storage.buckets where id = 'line-alert-media' and public)                                             as media_ok,
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('line_doc_alert_targets','line_doc_alert_log') and c.relrowsecurity)         as tbl_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'line\_doc\_alert\_%' or p.proname like 'app\_line\_alert\_%'))              as fn_ok,
  exists (select 1 from vault.secrets where name = 'line_doc_alert_token')                                                    as token_ok,
  (select count(*) from cron.job where jobname = 'line-doc-alert-daily')                                                      as cron_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'line\_doc\_alert\_%' and has_function_privilege('anon', p.oid, 'execute'))  as anon_internal,
  exists (select 1 from vault.secrets where name = 'line_doc_alert_url')                                                      as url_ok;

-- ---------- ตั้งค่า URL (รันครั้งเดียวต่อ environment — เลือกบรรทัดที่ตรงกับโปรเจกต์ที่เปิดอยู่) ----------
-- STAGING:    select vault.create_secret('https://bzwtknqvhvdmatangzqf.supabase.co/functions/v1/line-doc-alert', 'line_doc_alert_url');
-- PRODUCTION: select vault.create_secret('https://magwqolbjmwymqxelizl.supabase.co/functions/v1/line-doc-alert', 'line_doc_alert_url');

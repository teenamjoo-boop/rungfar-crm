-- =============================================================
-- STAGE PARCEL-001 — ระบบรายรับ-รายจ่าย ขนส่งพัสดุ (เว็บแยกจาก CRM)
--
--   เว็บขนส่ง (Netlify) → Edge Function `parcel-api` (service_role) → public.parcel_api(...)
--   * หน้าเว็บไม่มีกุญแจฐานข้อมูล · ทุกตารางในไฟล์นี้: RLS เปิด + 0 policy + ไม่ให้ anon/authenticated
--   * ผู้ใช้ร้านขนส่งเก็บใน parcel_users แยกจาก app_users → ล็อกอินเข้า CRM ไม่ได้ เห็นแต่ข้อมูลขนส่ง
--   * เจ้าของ (admin ของ CRM) ล็อกอินเว็บขนส่งด้วยบัญชี CRM เดิม → สิทธิ์ owner
--   * ลิงก์ดูอย่างเดียว (แบบหน้าลิงก์นายจ้าง): parcel_share_links (รหัสสั้น 11 ตัว ยกเลิกได้)
--   * ลบ = soft delete (เก็บร่องรอย) · audit_logs เฉพาะเหตุการณ์สำคัญ (ไม่มีรหัสผ่าน/token)
-- รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

-- ---------- ตาราง ----------
create table if not exists public.parcel_carriers (
  id         bigserial primary key,
  name       text not null unique,
  active     boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.parcel_users (
  id            bigserial primary key,
  username      text not null unique,
  full_name     text,
  password_hash text not null,
  active        boolean not null default true,
  created_by    text,
  created_at    timestamptz not null default now()
);

create table if not exists public.parcel_sessions (
  token_hash   text primary key,
  user_kind    text not null check (user_kind in ('owner','clerk')),
  user_id      bigint not null,
  username     text not null,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  expires_at   timestamptz not null
);

create table if not exists public.parcel_login_attempts (
  id         bigserial primary key,
  username   text not null,
  ok         boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists parcel_login_attempts_u on public.parcel_login_attempts (username, created_at);

create table if not exists public.parcel_shipments (
  id            bigserial primary key,
  ship_date     date not null,
  carrier_id    bigint references public.parcel_carriers(id),
  tracking_no   text,
  customer_name text,
  cost          numeric(12,2) not null default 0 check (cost >= 0),
  price         numeric(12,2) not null default 0 check (price >= 0),
  pay_method    text not null check (pay_method in ('cash','transfer')),
  note          text,
  created_by    text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  deleted_at    timestamptz,
  deleted_by    text
);
create index if not exists parcel_shipments_date on public.parcel_shipments (ship_date) where deleted_at is null;

create table if not exists public.parcel_topups (
  id          bigserial primary key,
  topup_date  date not null,
  carrier_id  bigint not null references public.parcel_carriers(id),
  amount      numeric(12,2) not null check (amount > 0),
  pay_method  text not null check (pay_method in ('cash','transfer')),
  note        text,
  created_by  text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  deleted_at  timestamptz,
  deleted_by  text
);
create index if not exists parcel_topups_date on public.parcel_topups (topup_date) where deleted_at is null;

create table if not exists public.parcel_expenses (
  id          bigserial primary key,
  exp_date    date not null,
  item        text not null,
  amount      numeric(12,2) not null check (amount > 0),
  pay_method  text not null check (pay_method in ('cash','transfer')),
  note        text,
  created_by  text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  deleted_at  timestamptz,
  deleted_by  text
);
create index if not exists parcel_expenses_date on public.parcel_expenses (exp_date) where deleted_at is null;

create table if not exists public.parcel_settings (
  key        text primary key,
  value      jsonb not null,
  updated_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.parcel_share_links (
  id             bigserial primary key,
  code           text not null unique,
  created_by     text not null,
  created_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  revoked_by     text,
  view_count     integer not null default 0,
  last_viewed_at timestamptz
);

do $$
declare t text;
begin
  foreach t in array array['parcel_carriers','parcel_users','parcel_sessions','parcel_login_attempts',
                           'parcel_shipments','parcel_topups','parcel_expenses','parcel_settings','parcel_share_links']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

insert into public.parcel_carriers (name, sort)
select v.name, v.sort
from (values ('Flash Express',1),('Kerry Express',2),('J&T Express',3),('ไปรษณีย์ไทย',4),('SPX Express',5),('Best Express',6)) v(name, sort)
where not exists (select 1 from public.parcel_carriers);

insert into public.parcel_settings (key, value)
values ('opening', '{"cash":0,"transfer":0}'::jsonb)
on conflict (key) do nothing;

-- ---------- ตัวช่วย ----------
create or replace function public.parcel_num(p jsonb, k text, p_min numeric, p_max numeric)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v numeric;
begin
  begin v := (p ->> k)::numeric; exception when others then raise exception 'invalid_%', k using errcode = 'P0003'; end;
  if v is null or v < p_min or v > p_max then raise exception 'invalid_%', k using errcode = 'P0003'; end if;
  return round(v, 2);
end $$;

create or replace function public.parcel_txt(p jsonb, k text, p_max integer)
returns text language sql immutable set search_path = '' as $$
  select nullif(left(btrim(coalesce(p ->> k, '')), p_max), '');
$$;

-- สรุปตัวเลข (ใช้ทั้งในแอปและลิงก์ดูอย่างเดียว)
create or replace function public.parcel_summary(p_year integer, p_month integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  with s as (select * from public.parcel_shipments where deleted_at is null),
       t as (select * from public.parcel_topups   where deleted_at is null),
       e as (select * from public.parcel_expenses where deleted_at is null),
       op as (select coalesce((value->>'cash')::numeric,0) cash, coalesce((value->>'transfer')::numeric,0) tr
              from public.parcel_settings where key = 'opening'),
       mon as (
         select m,
           (select count(*)                 from s where date_part('year',ship_date)=p_year and date_part('month',ship_date)=m) cnt,
           (select coalesce(sum(price),0)   from s where date_part('year',ship_date)=p_year and date_part('month',ship_date)=m) price,
           (select coalesce(sum(cost),0)    from s where date_part('year',ship_date)=p_year and date_part('month',ship_date)=m) cost,
           (select coalesce(sum(price),0)   from s where date_part('year',ship_date)=p_year and date_part('month',ship_date)=m and pay_method='cash') cash_in,
           (select coalesce(sum(price),0)   from s where date_part('year',ship_date)=p_year and date_part('month',ship_date)=m and pay_method='transfer') transfer_in,
           (select coalesce(sum(amount),0)  from t where date_part('year',topup_date)=p_year and date_part('month',topup_date)=m) topup,
           (select coalesce(sum(amount),0)  from e where date_part('year',exp_date)=p_year and date_part('month',exp_date)=m) expense
         from generate_series(1,12) m)
  select jsonb_build_object(
    'year', p_year, 'month', p_month,
    'months', (select jsonb_agg(jsonb_build_object('m',m,'count',cnt,'price',price,'cost',cost,'profit',price-cost,
                     'cash_in',cash_in,'transfer_in',transfer_in,'topup',topup,'expense',expense,'net',price-cost-expense) order by m) from mon),
    'days', (select coalesce(jsonb_agg(jsonb_build_object('d',d,'count',cnt,'price',price,'profit',price-cost) order by d),'[]'::jsonb)
             from (select ship_date d, count(*) cnt, sum(price) price, sum(cost) cost from s
                   where date_part('year',ship_date)=p_year and date_part('month',ship_date)=p_month group by 1) x),
    'carriers', (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'active',c.active,
                     'topup',(select coalesce(sum(amount),0) from t where t.carrier_id=c.id),
                     'used',(select coalesce(sum(cost),0) from s where s.carrier_id=c.id),
                     'count',(select count(*) from s where s.carrier_id=c.id)) order by c.sort, c.id),'[]'::jsonb)
                 from public.parcel_carriers c),
    'money', (select jsonb_build_object(
        'cash', jsonb_build_object('opening', op.cash,
                  'in',  (select coalesce(sum(price),0) from s where pay_method='cash'),
                  'out', (select coalesce(sum(amount),0) from t where pay_method='cash') + (select coalesce(sum(amount),0) from e where pay_method='cash')),
        'transfer', jsonb_build_object('opening', op.tr,
                  'in',  (select coalesce(sum(price),0) from s where pay_method='transfer'),
                  'out', (select coalesce(sum(amount),0) from t where pay_method='transfer') + (select coalesce(sum(amount),0) from e where pay_method='transfer')))
      from op)
  );
$$;

create or replace function public.parcel_rows(p_year integer, p_month integer, p_kind text, p_limit integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'ship' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',s.id,'date',s.ship_date,'carrier_id',s.carrier_id,'carrier',c.name,'tracking_no',s.tracking_no,
               'customer_name',s.customer_name,'cost',s.cost,'price',s.price,'pay',s.pay_method,'note',s.note,'by',s.created_by,'at',s.created_at) r
        from public.parcel_shipments s left join public.parcel_carriers c on c.id=s.carrier_id
        where s.deleted_at is null and date_part('year',s.ship_date)=p_year and date_part('month',s.ship_date)=p_month
        order by s.ship_date desc, s.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
    when 'topup' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',t.id,'date',t.topup_date,'carrier_id',t.carrier_id,'carrier',c.name,'amount',t.amount,
               'pay',t.pay_method,'note',t.note,'by',t.created_by,'at',t.created_at) r
        from public.parcel_topups t left join public.parcel_carriers c on c.id=t.carrier_id
        where t.deleted_at is null and date_part('year',t.topup_date)=p_year and date_part('month',t.topup_date)=p_month
        order by t.topup_date desc, t.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
    when 'expense' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',e.id,'date',e.exp_date,'item',e.item,'amount',e.amount,'pay',e.pay_method,'note',e.note,
               'by',e.created_by,'at',e.created_at) r
        from public.parcel_expenses e
        where e.deleted_at is null and date_part('year',e.exp_date)=p_year and date_part('month',e.exp_date)=p_month
        order by e.exp_date desc, e.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
  end;
$$;

-- ---------- จุดเข้าเดียวของ Edge Function ----------
create or replace function public.parcel_api(p_action text, p_token text default null, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  a      jsonb := coalesce(p_args, '{}'::jsonb);
  v_sess public.parcel_sessions;
  v_role text;          -- owner | clerk
  v_user text;
  v_name text;
  v_id   bigint;
  v_kind text;
  v_row  jsonb;
  v_tok  text;
  v_cnt  integer;
  v_y    integer;
  v_m    integer;
  v_pay  text;
  v_date date;
  r      record;
begin
  -- ===== ไม่ต้องล็อกอิน =====
  if p_action = 'login' then
    v_user := lower(btrim(coalesce(a->>'username','')));
    if v_user = '' or coalesce(a->>'password','') = '' then return jsonb_build_object('ok',false,'error','invalid'); end if;
    select count(*) into v_cnt from public.parcel_login_attempts
     where username = v_user and not ok and created_at > now() - interval '15 minutes';
    if v_cnt >= 5 then return jsonb_build_object('ok',false,'error','locked'); end if;

    -- ผู้ใช้ร้านขนส่ง
    select u.id, u.username, coalesce(u.full_name, u.username) into v_id, v_user, v_name
      from public.parcel_users u
     where lower(u.username) = v_user and u.active
       and u.password_hash = extensions.crypt(a->>'password', u.password_hash);
    if v_id is not null then
      v_role := 'clerk';
    else
      -- เจ้าของ = admin ของ CRM
      select u.id, u.username, coalesce(u.full_name, u.username) into v_id, v_user, v_name
        from public.app_users u
       where lower(u.username) = lower(btrim(a->>'username')) and coalesce(u.is_active,true) and u.role = 'admin'
         and u.password_hash = extensions.crypt(a->>'password', u.password_hash);
      if v_id is not null then v_role := 'owner'; end if;
    end if;

    insert into public.parcel_login_attempts (username, ok) values (lower(btrim(a->>'username')), v_id is not null);
    delete from public.parcel_login_attempts where created_at < now() - interval '30 days';
    if v_id is null then return jsonb_build_object('ok',false,'error','invalid'); end if;

    v_tok := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.parcel_sessions (token_hash, user_kind, user_id, username, expires_at)
    values (encode(extensions.digest(v_tok,'sha256'),'hex'), v_role, v_id, v_user, now() + interval '30 days');
    delete from public.parcel_sessions where expires_at < now();
    return jsonb_build_object('ok',true,'token',v_tok,'user',jsonb_build_object('username',v_user,'name',v_name,'role',v_role));
  end if;

  if p_action = 'share_view' then
    update public.parcel_share_links l set view_count = l.view_count + 1, last_viewed_at = now()
     where l.code = coalesce(a->>'c','') and l.revoked_at is null
    returning l.id into v_id;
    if v_id is null then return jsonb_build_object('ok',false,'error','invalid'); end if;
    v_y := coalesce(nullif(a->>'year','')::int, date_part('year', now() at time zone 'Asia/Bangkok')::int);
    v_m := coalesce(nullif(a->>'month','')::int, date_part('month', now() at time zone 'Asia/Bangkok')::int);
    if v_m not between 1 and 12 or v_y not between 2000 and 2100 then return jsonb_build_object('ok',false,'error','invalid_month'); end if;
    return jsonb_build_object('ok',true,'readonly',true,'summary',public.parcel_summary(v_y,v_m),
      'ship',public.parcel_rows(v_y,v_m,'ship',2000),'topup',public.parcel_rows(v_y,v_m,'topup',2000),'expense',public.parcel_rows(v_y,v_m,'expense',2000),
      'generated_at', now());
  end if;

  -- ===== ต้องล็อกอิน =====
  select * into v_sess from public.parcel_sessions s
   where s.token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at > now();
  if v_sess.token_hash is null then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  -- ผู้ใช้ถูกปิด → ออกทันที
  if v_sess.user_kind = 'clerk' and not exists (select 1 from public.parcel_users u where u.id = v_sess.user_id and u.active) then
    delete from public.parcel_sessions where token_hash = v_sess.token_hash;
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  if v_sess.user_kind = 'owner' and not exists (select 1 from public.app_users u where u.id = v_sess.user_id and coalesce(u.is_active,true) and u.role='admin') then
    delete from public.parcel_sessions where token_hash = v_sess.token_hash;
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  v_role := v_sess.user_kind; v_user := v_sess.username;
  if v_sess.last_used_at < now() - interval '1 hour' then
    update public.parcel_sessions set last_used_at = now(), expires_at = now() + interval '30 days' where token_hash = v_sess.token_hash;
  end if;

  if p_action = 'logout' then
    delete from public.parcel_sessions where token_hash = v_sess.token_hash;
    return jsonb_build_object('ok',true);
  end if;

  if p_action = 'boot' then
    return jsonb_build_object('ok',true,
      'user', jsonb_build_object('username',v_user,'role',v_role),
      'carriers', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active) order by sort, id),'[]'::jsonb) from public.parcel_carriers),
      'opening', (select value from public.parcel_settings where key='opening'));
  end if;

  if p_action in ('summary','list') then
    v_y := nullif(a->>'year','')::int; v_m := nullif(a->>'month','')::int;
    if v_y is null or v_m is null or v_m not between 1 and 12 or v_y not between 2000 and 2100 then
      return jsonb_build_object('ok',false,'error','invalid_month');
    end if;
    if p_action = 'summary' then
      return jsonb_build_object('ok',true,'summary',public.parcel_summary(v_y,v_m));
    end if;
    v_kind := a->>'kind';
    if v_kind not in ('ship','topup','expense') then return jsonb_build_object('ok',false,'error','invalid_kind'); end if;
    return jsonb_build_object('ok',true,'rows',public.parcel_rows(v_y,v_m,v_kind,2000));
  end if;

  if p_action = 'save' then
    v_kind := a->>'kind'; v_row := coalesce(a->'row','{}'::jsonb);
    v_id := nullif(v_row->>'id','')::bigint;
    v_pay := v_row->>'pay';
    if v_pay not in ('cash','transfer') then return jsonb_build_object('ok',false,'error','invalid_pay'); end if;
    begin v_date := (v_row->>'date')::date; exception when others then v_date := null; end;
    if v_date is null or v_date < date '2000-01-01' or v_date > (now() at time zone 'Asia/Bangkok')::date + 1 then
      return jsonb_build_object('ok',false,'error','invalid_date');
    end if;
    if v_kind in ('ship','topup') and not exists (select 1 from public.parcel_carriers c where c.id = nullif(v_row->>'carrier_id','')::bigint) then
      return jsonb_build_object('ok',false,'error','invalid_carrier');
    end if;
    -- แก้ไข: พนักงานแก้ได้เฉพาะรายการของตัวเองที่ลงภายใน 7 วัน · เจ้าของแก้ได้ทุกรายการ
    if v_id is not null then
      execute format('select created_by, created_at from public.%I where id = $1 and deleted_at is null',
                     case v_kind when 'ship' then 'parcel_shipments' when 'topup' then 'parcel_topups' when 'expense' then 'parcel_expenses' end)
        into r using v_id;
      if r is null then return jsonb_build_object('ok',false,'error','not_found'); end if;
      if v_role <> 'owner' and (r.created_by <> v_user or r.created_at < now() - interval '7 days') then
        return jsonb_build_object('ok',false,'error','forbidden');
      end if;
    end if;

    if v_kind = 'ship' then
      if v_id is null then
        insert into public.parcel_shipments (ship_date, carrier_id, tracking_no, customer_name, cost, price, pay_method, note, created_by)
        values (v_date, (v_row->>'carrier_id')::bigint, public.parcel_txt(v_row,'tracking_no',60), public.parcel_txt(v_row,'customer_name',120),
                public.parcel_num(v_row,'cost',0,1000000), public.parcel_num(v_row,'price',0,1000000), v_pay, public.parcel_txt(v_row,'note',300), v_user)
        returning id into v_id;
      else
        update public.parcel_shipments set ship_date=v_date, carrier_id=(v_row->>'carrier_id')::bigint,
               tracking_no=public.parcel_txt(v_row,'tracking_no',60), customer_name=public.parcel_txt(v_row,'customer_name',120),
               cost=public.parcel_num(v_row,'cost',0,1000000), price=public.parcel_num(v_row,'price',0,1000000),
               pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    elsif v_kind = 'topup' then
      if v_id is null then
        insert into public.parcel_topups (topup_date, carrier_id, amount, pay_method, note, created_by)
        values (v_date, (v_row->>'carrier_id')::bigint, public.parcel_num(v_row,'amount',0.01,1000000), v_pay, public.parcel_txt(v_row,'note',300), v_user)
        returning id into v_id;
      else
        update public.parcel_topups set topup_date=v_date, carrier_id=(v_row->>'carrier_id')::bigint,
               amount=public.parcel_num(v_row,'amount',0.01,1000000), pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    elsif v_kind = 'expense' then
      if public.parcel_txt(v_row,'item',120) is null then return jsonb_build_object('ok',false,'error','invalid_item'); end if;
      if v_id is null then
        insert into public.parcel_expenses (exp_date, item, amount, pay_method, note, created_by)
        values (v_date, public.parcel_txt(v_row,'item',120), public.parcel_num(v_row,'amount',0.01,1000000), v_pay, public.parcel_txt(v_row,'note',300), v_user)
        returning id into v_id;
      else
        update public.parcel_expenses set exp_date=v_date, item=public.parcel_txt(v_row,'item',120),
               amount=public.parcel_num(v_row,'amount',0.01,1000000), pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    else
      return jsonb_build_object('ok',false,'error','invalid_kind');
    end if;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  if p_action = 'delete' then
    v_kind := a->>'kind'; v_id := nullif(a->>'id','')::bigint;
    if v_kind not in ('ship','topup','expense') or v_id is null then return jsonb_build_object('ok',false,'error','invalid'); end if;
    execute format('select created_by, created_at from public.%I where id = $1 and deleted_at is null',
                   case v_kind when 'ship' then 'parcel_shipments' when 'topup' then 'parcel_topups' else 'parcel_expenses' end)
      into r using v_id;
    if r is null then return jsonb_build_object('ok',false,'error','not_found'); end if;
    if v_role <> 'owner' and (r.created_by <> v_user or r.created_at < now() - interval '7 days') then
      return jsonb_build_object('ok',false,'error','forbidden');
    end if;
    execute format('update public.%I set deleted_at = now(), deleted_by = $2 where id = $1',
                   case v_kind when 'ship' then 'parcel_shipments' when 'topup' then 'parcel_topups' else 'parcel_expenses' end)
      using v_id, v_user;
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (v_user, v_user, 'parcel_'||v_role, 'parcel.'||v_kind||'.delete', 'parcel_'||v_kind, v_id::text, '{}'::jsonb);
    exception when others then null; end;
    return jsonb_build_object('ok',true);
  end if;

  -- ===== เฉพาะเจ้าของ =====
  if v_role <> 'owner' then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  if p_action = 'carrier_save' then
    v_id := nullif(a->>'id','')::bigint; v_name := public.parcel_txt(a,'name',60);
    if v_name is null then return jsonb_build_object('ok',false,'error','invalid_name'); end if;
    if v_id is null then
      insert into public.parcel_carriers (name, sort) values (v_name, (select coalesce(max(sort),0)+1 from public.parcel_carriers))
      on conflict (name) do update set active = true returning id into v_id;
    else
      update public.parcel_carriers set name = v_name, active = coalesce((a->>'active')::boolean, active) where id = v_id;
    end if;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  if p_action = 'opening_save' then
    insert into public.parcel_settings (key, value, updated_by, updated_at)
    values ('opening', jsonb_build_object('cash', public.parcel_num(a,'cash',-10000000,10000000), 'transfer', public.parcel_num(a,'transfer',-10000000,10000000)), v_user, now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    return jsonb_build_object('ok',true);
  end if;

  if p_action = 'users_list' then
    return jsonb_build_object('ok',true,'users',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'username',username,'name',full_name,'active',active,'created_at',created_at) order by id),'[]'::jsonb) from public.parcel_users));
  end if;

  if p_action = 'user_save' then
    v_id := nullif(a->>'id','')::bigint;
    v_name := lower(btrim(coalesce(a->>'username','')));
    if v_id is null then
      if v_name !~ '^[a-z0-9._-]{3,30}$' then return jsonb_build_object('ok',false,'error','invalid_username'); end if;
      if exists (select 1 from public.parcel_users where lower(username)=v_name) or exists (select 1 from public.app_users where lower(username)=v_name) then
        return jsonb_build_object('ok',false,'error','username_exists');
      end if;
      if length(coalesce(a->>'password','')) < 6 then return jsonb_build_object('ok',false,'error','password_short'); end if;
      insert into public.parcel_users (username, full_name, password_hash, created_by)
      values (v_name, public.parcel_txt(a,'full_name',80), extensions.crypt(a->>'password', extensions.gen_salt('bf',10)), v_user)
      returning id into v_id;
    else
      update public.parcel_users set full_name = coalesce(public.parcel_txt(a,'full_name',80), full_name),
             active = coalesce((a->>'active')::boolean, active) where id = v_id;
      if coalesce(a->>'password','') <> '' then
        if length(a->>'password') < 6 then return jsonb_build_object('ok',false,'error','password_short'); end if;
        update public.parcel_users set password_hash = extensions.crypt(a->>'password', extensions.gen_salt('bf',10)) where id = v_id;
        delete from public.parcel_sessions where user_kind = 'clerk' and user_id = v_id;
      end if;
      if (a->>'active')::boolean is false then delete from public.parcel_sessions where user_kind = 'clerk' and user_id = v_id; end if;
    end if;
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (v_user, v_user, 'parcel_owner', 'parcel.user.save', 'parcel_user', v_id::text, jsonb_build_object('active', a->'active'));
    exception when others then null; end;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  if p_action in ('share_get','share_create','share_revoke') then
    if p_action in ('share_create','share_revoke') then
      update public.parcel_share_links set revoked_at = now(), revoked_by = v_user where revoked_at is null;
    end if;
    if p_action = 'share_create' then
      loop
        v_tok := (select string_agg(substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (get_byte(b, i) % 62) + 1, 1), '')
                  from (select extensions.gen_random_bytes(11) b) x, generate_series(0,10) i);
        exit when not exists (select 1 from public.parcel_share_links where code = v_tok);
      end loop;
      insert into public.parcel_share_links (code, created_by) values (v_tok, v_user);
    end if;
    if p_action <> 'share_get' then
      begin
        insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
        values (v_user, v_user, 'parcel_owner', 'parcel.'||p_action, 'parcel_share', 'current', '{}'::jsonb);
      exception when others then null; end;
    end if;
    return jsonb_build_object('ok',true,'link',(select jsonb_build_object('code',code,'created_at',created_at,'created_by',created_by,
                     'view_count',view_count,'last_viewed_at',last_viewed_at) from public.parcel_share_links where revoked_at is null order by id desc limit 1));
  end if;

  return jsonb_build_object('ok',false,'error','unknown_action');
end;
$$;

-- ---------- สิทธิ์: service_role เท่านั้น ----------
do $$
declare f text;
begin
  foreach f in array array['parcel_num(jsonb,text,numeric,numeric)','parcel_txt(jsonb,text,integer)','parcel_summary(integer,integer)',
                           'parcel_rows(integer,integer,text,integer)','parcel_api(text,text,jsonb)']
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;

-- ---------- ตรวจผล — ควรได้ tables_ok = 9, fn_ok = 5, carriers >= 6, anon_exec = 0 ----------
select
  (select count(*) from information_schema.tables where table_schema='public' and table_name like 'parcel\_%' and table_name in
     ('parcel_carriers','parcel_users','parcel_sessions','parcel_login_attempts','parcel_shipments','parcel_topups','parcel_expenses','parcel_settings','parcel_share_links')) as tables_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
     and p.proname in ('parcel_num','parcel_txt','parcel_summary','parcel_rows','parcel_api'))                                                            as fn_ok,
  (select count(*) from public.parcel_carriers)                                                                                                          as carriers,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'parcel\_%'
     and has_function_privilege('anon', p.oid, 'execute'))                                                                                               as anon_exec;

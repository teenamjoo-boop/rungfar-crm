-- =============================================================
-- STAGE PARCEL-BRANCH — หลายสาขา (ปทุมธานี / ระยอง) ในระบบเดียว ลิงก์เดียว
--   * parcel_branches: รายชื่อสาขา (seed: ปทุมธานี, ระยอง)
--   * ทุกรายการ (ส่งพัสดุ / เติมเงิน / รายจ่ายอื่น) มี branch_id — ข้อมูลเดิมทั้งหมด = ปทุมธานี
--   * เครดิต PayPoint, เงินสด, เงินในบัญชีขนส่ง, ยอดตั้งต้น แยกตามสาขา
--   * พนักงาน (parcel_users) ผูกสาขา → เห็น/ลงได้เฉพาะสาขาตัวเอง · เจ้าของเลือกสาขาหรือ "รวมทุกสาขา"
--   * ลิงก์ดูอย่างเดียวแยกตามสาขา หรือแบบรวมทุกสาขา (branch_id null)
--   * เลขรายการ PayPoint ห้ามซ้ำ "ภายในสาขาเดียวกัน" (แต่ละสาขาเป็นบัญชี PayPoint แยก)
--   ฟังก์ชันใหม่ทั้งชุด: parcel_rows(5), parcel_summary(3), parcel_import(4), parcel_api
--   Edge Function parcel-api ไม่ต้องแก้ (คำสั่งเดิมทั้งหมด · จัดการสาขาผ่าน save kind='branch')
-- ต้องรันหลัง 20261021d_parcel_topup_company.sql · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

create table if not exists public.parcel_branches (
  id         bigserial primary key,
  name       text not null unique,
  sort       integer not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.parcel_branches enable row level security;
revoke all on public.parcel_branches from anon, authenticated;

insert into public.parcel_branches (name, sort)
select v.name, v.sort from (values ('ปทุมธานี',1),('ระยอง',2)) v(name, sort)
where not exists (select 1 from public.parcel_branches);

do $$
declare v_b1 bigint; t text;
begin
  select id into v_b1 from public.parcel_branches order by sort, id limit 1;
  foreach t in array array['parcel_shipments','parcel_topups','parcel_expenses','parcel_users'] loop
    execute format('alter table public.%I add column if not exists branch_id bigint references public.parcel_branches(id)', t);
    execute format('update public.%I set branch_id = $1 where branch_id is null', t) using v_b1;
    execute format('alter table public.%I alter column branch_id set not null', t);
  end loop;
  alter table public.parcel_share_links add column if not exists branch_id bigint references public.parcel_branches(id);
  -- ลิงก์เดิมที่ยังใช้อยู่ = ของปทุมธานี (ข้อมูลเดิมทั้งหมดเป็นของปทุมธานี)
  update public.parcel_share_links set branch_id = v_b1 where branch_id is null and revoked_at is null
     and not exists (select 1 from public.parcel_settings where key = 'branches_migrated');
  -- ยอดตั้งต้นเดิม → ของปทุมธานี
  insert into public.parcel_settings (key, value, updated_by, updated_at)
  select 'opening:'||v_b1, value, updated_by, now() from public.parcel_settings where key = 'opening'
  on conflict (key) do nothing;
  insert into public.parcel_settings (key, value) values ('branches_migrated', 'true'::jsonb) on conflict (key) do nothing;
end $$;

create index if not exists parcel_shipments_branch_date on public.parcel_shipments (branch_id, ship_date) where deleted_at is null;
create index if not exists parcel_topups_branch_date    on public.parcel_topups (branch_id, topup_date) where deleted_at is null;
create index if not exists parcel_expenses_branch_date  on public.parcel_expenses (branch_id, exp_date) where deleted_at is null;
drop index if exists public.parcel_shipments_ext_ref_u;
create unique index if not exists parcel_shipments_branch_ext_ref_u on public.parcel_shipments (branch_id, ext_ref)
  where ext_ref is not null and deleted_at is null;

-- ---------- รายการ (กรองตามสาขา · null = ทุกสาขา) ----------
drop function if exists public.parcel_rows(integer, integer, text, integer);
create or replace function public.parcel_rows(p_year integer, p_month integer, p_kind text, p_limit integer, p_branch bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'ship' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',s.id,'date',s.ship_date,'carrier_id',s.carrier_id,'carrier',c.name,'tracking_no',s.tracking_no,
               'customer_name',s.customer_name,'cost',s.cost,'price',s.price,'pay',s.pay_method,'note',s.note,'by',s.created_by,'at',s.created_at,
               'branch_id',s.branch_id,'branch',b.name) r
        from public.parcel_shipments s left join public.parcel_carriers c on c.id=s.carrier_id left join public.parcel_branches b on b.id=s.branch_id
        where s.deleted_at is null and (p_branch is null or s.branch_id=p_branch)
          and date_part('year',s.ship_date)=p_year and date_part('month',s.ship_date)=p_month
        order by s.ship_date desc, s.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
    when 'topup' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',t.id,'date',t.topup_date,'carrier_id',t.carrier_id,'carrier',c.name,'amount',t.amount,
               'pay',t.pay_method,'note',t.note,'by',t.created_by,'at',t.created_at,'branch_id',t.branch_id,'branch',b.name) r
        from public.parcel_topups t left join public.parcel_carriers c on c.id=t.carrier_id left join public.parcel_branches b on b.id=t.branch_id
        where t.deleted_at is null and (p_branch is null or t.branch_id=p_branch)
          and date_part('year',t.topup_date)=p_year and date_part('month',t.topup_date)=p_month
        order by t.topup_date desc, t.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
    when 'expense' then (select coalesce(jsonb_agg(r order by r->>'date' desc, (r->>'id')::bigint desc),'[]'::jsonb) from (
        select jsonb_build_object('id',e.id,'date',e.exp_date,'item',e.item,'amount',e.amount,'pay',e.pay_method,'note',e.note,
               'by',e.created_by,'at',e.created_at,'branch_id',e.branch_id,'branch',b.name) r
        from public.parcel_expenses e left join public.parcel_branches b on b.id=e.branch_id
        where e.deleted_at is null and (p_branch is null or e.branch_id=p_branch)
          and date_part('year',e.exp_date)=p_year and date_part('month',e.exp_date)=p_month
        order by e.exp_date desc, e.id desc limit greatest(1,least(coalesce(p_limit,500),2000))) x)
  end;
$$;

-- ---------- สรุปตัวเลข (กรองตามสาขา · null = รวมทุกสาขา) ----------
drop function if exists public.parcel_summary(integer, integer);
create or replace function public.parcel_summary(p_year integer, p_month integer, p_branch bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  with br as (select * from public.parcel_branches where p_branch is null or id = p_branch),
       s as (select * from public.parcel_shipments where deleted_at is null and branch_id in (select id from br)),
       t as (select * from public.parcel_topups   where deleted_at is null and branch_id in (select id from br)),
       e as (select * from public.parcel_expenses where deleted_at is null and branch_id in (select id from br)),
       c as (select x.*, coalesce(x.wallet_id, x.id) holder from public.parcel_carriers x),
       op as (select coalesce(sum((st.value->>'cash')::numeric),0) cash, coalesce(sum((st.value->>'transfer')::numeric),0) tr
              from public.parcel_settings st where st.key in (select 'opening:'||id from br)),
       sm as (select * from s where date_part('year',ship_date)=p_year),
       mon as (
         select m,
           (select count(*)                 from sm where date_part('month',ship_date)=m) cnt,
           (select coalesce(sum(price),0)   from sm where date_part('month',ship_date)=m) price,
           (select coalesce(sum(cost),0)    from sm where date_part('month',ship_date)=m) cost,
           (select coalesce(sum(cost),0)    from sm where date_part('month',ship_date)=m and pay_method<>'self') cust_cost,
           (select count(*)                 from sm where date_part('month',ship_date)=m and pay_method='self') self_cnt,
           (select coalesce(sum(cost),0)    from sm where date_part('month',ship_date)=m and pay_method='self') self_cost,
           (select coalesce(sum(price),0)   from sm where date_part('month',ship_date)=m and pay_method='cash') cash_in,
           (select coalesce(sum(price),0)   from sm where date_part('month',ship_date)=m and pay_method='transfer') transfer_in,
           (select coalesce(sum(amount),0)  from t where date_part('year',topup_date)=p_year and date_part('month',topup_date)=m) topup,
           (select coalesce(sum(amount),0)  from e where date_part('year',exp_date)=p_year and date_part('month',exp_date)=m) expense
         from generate_series(1,12) m)
  select jsonb_build_object(
    'year', p_year, 'month', p_month, 'branch', p_branch,
    'months', (select jsonb_agg(jsonb_build_object('m',m,'count',cnt,'price',price,'cost',cost,'profit',price-cust_cost,
                     'self_count',self_cnt,'self_cost',self_cost,
                     'cash_in',cash_in,'transfer_in',transfer_in,'topup',topup,'expense',expense,'net',price-cost-expense) order by m) from mon),
    'days', (select coalesce(jsonb_agg(jsonb_build_object('d',d,'count',cnt,'price',price,'profit',price-cust_cost,'self_count',self_cnt,'self_cost',self_cost) order by d),'[]'::jsonb)
             from (select ship_date d, count(*) cnt, sum(price) price,
                          coalesce(sum(cost) filter (where pay_method<>'self'),0) cust_cost,
                          count(*) filter (where pay_method='self') self_cnt,
                          coalesce(sum(cost) filter (where pay_method='self'),0) self_cost
                   from sm where date_part('month',ship_date)=p_month group by 1) x),
    'carriers', (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'active',c.active,'is_wallet',c.is_wallet,'wallet_id',c.wallet_id,
                     'topup',(select coalesce(sum(amount),0) from t where t.carrier_id=c.id),
                     'used',(select coalesce(sum(cost),0) from s where s.carrier_id=c.id),
                     'count',(select count(*) from s where s.carrier_id=c.id)) order by c.sort, c.id),'[]'::jsonb)
                 from c),
    -- เครดิตคงเหลือ แยกตาม สาขา × ที่เก็บเครดิต (กระเป๋า PayPoint ของแต่ละสาขาเป็นคนละบัญชี)
    'credit', (select coalesce(jsonb_agg(x order by (x->>'bsort')::int, (x->>'branch_id')::bigint, (x->>'is_wallet')::boolean desc, (x->>'sort')::int, (x->>'id')::bigint),'[]'::jsonb) from (
                 select jsonb_build_object('id',h.id,'name',h.name,'is_wallet',h.is_wallet,'active',h.active,'sort',h.sort,
                     'branch_id',b.id,'branch',b.name,'bsort',b.sort,
                     'members',(select coalesce(jsonb_agg(m.name order by m.sort, m.id),'[]'::jsonb) from c m where m.wallet_id = h.id),
                     'topup',(select coalesce(sum(amount),0) from t where t.branch_id=b.id and t.carrier_id in (select id from c where holder = h.id)),
                     'used',(select coalesce(sum(cost),0) from s where s.branch_id=b.id and s.carrier_id in (select id from c where holder = h.id)),
                     'count',(select count(*) from s where s.branch_id=b.id and s.carrier_id in (select id from c where holder = h.id))) x
                 from br b cross join c h where h.wallet_id is null) y),
    -- เทียบสาขา (เดือนที่เลือก)
    'branches', (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,
                     'count',(select count(*) from sm where sm.branch_id=b.id and date_part('month',ship_date)=p_month),
                     'price',(select coalesce(sum(price),0) from sm where sm.branch_id=b.id and date_part('month',ship_date)=p_month),
                     'profit',(select coalesce(sum(price-cost) filter (where pay_method<>'self'),0) from sm where sm.branch_id=b.id and date_part('month',ship_date)=p_month),
                     'self_cost',(select coalesce(sum(cost) filter (where pay_method='self'),0) from sm where sm.branch_id=b.id and date_part('month',ship_date)=p_month),
                     'expense',(select coalesce(sum(amount),0) from e where e.branch_id=b.id and date_part('year',exp_date)=p_year and date_part('month',exp_date)=p_month))
                   order by b.sort, b.id),'[]'::jsonb) from br b),
    'money', (select jsonb_build_object(
        'cash', jsonb_build_object('opening', op.cash,
                  'in',  (select coalesce(sum(price),0) from s where pay_method='cash'),
                  'out', (select coalesce(sum(amount),0) from e where pay_method='cash')),
        'transfer', jsonb_build_object('opening', op.tr,
                  'in',  (select coalesce(sum(price),0) from s where pay_method='transfer'),
                  'out', (select coalesce(sum(amount),0) from e where pay_method='transfer')))
      from op)
  );
$$;

-- ---------- นำเข้า PayPoint (เข้าสาขาที่เลือก) ----------
drop function if exists public.parcel_import(text, text, jsonb);
create or replace function public.parcel_import(p_action text, p_user text, p_args jsonb, p_branch bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rows   jsonb := coalesce(p_args->'rows', '[]'::jsonb);
  refs   text[];
  r      jsonb;
  v_ref  text;
  v_cid  bigint;
  v_cname text;
  v_date date;
  v_pay  text;
  n_ins  integer := 0;
  n_skip integer := 0;
  n_car  integer := 0;
  bad    jsonb := '[]'::jsonb;
  idx    integer := 0;
begin
  if p_branch is null or not exists (select 1 from public.parcel_branches b where b.id = p_branch) then
    return jsonb_build_object('ok',false,'error','invalid_branch');
  end if;
  if p_action = 'import_check' then
    select array_agg(x) into refs from jsonb_array_elements_text(coalesce(p_args->'refs','[]'::jsonb)) x;
    if coalesce(array_length(refs,1),0) > 2000 then return jsonb_build_object('ok',false,'error','too_many'); end if;
    return jsonb_build_object('ok',true,'existing',
      (select coalesce(jsonb_agg(s.ext_ref),'[]'::jsonb) from public.parcel_shipments s
        where s.deleted_at is null and s.branch_id = p_branch and s.ext_ref = any(coalesce(refs, array[]::text[]))));
  end if;

  if jsonb_typeof(rows) <> 'array' or jsonb_array_length(rows) = 0 then return jsonb_build_object('ok',false,'error','no_rows'); end if;
  if jsonb_array_length(rows) > 500 then return jsonb_build_object('ok',false,'error','too_many'); end if;

  for r in select * from jsonb_array_elements(rows) loop
    idx := idx + 1;
    v_ref := nullif(left(btrim(coalesce(r->>'ext_ref','')),60),'');
    begin v_date := (r->>'date')::date; exception when others then v_date := null; end;
    v_pay := r->>'pay';
    v_cname := nullif(left(btrim(coalesce(r->>'carrier','')),60),'');
    if v_ref is null or v_date is null or v_pay not in ('cash','transfer','self') or v_cname is null
       or v_date < date '2000-01-01' or v_date > (now() at time zone 'Asia/Bangkok')::date + 1 then
      bad := bad || jsonb_build_array(idx); continue;
    end if;
    if exists (select 1 from public.parcel_shipments s where s.branch_id = p_branch and s.ext_ref = v_ref and s.deleted_at is null) then
      n_skip := n_skip + 1; continue;
    end if;
    select c.id into v_cid from public.parcel_carriers c where lower(c.name) = lower(v_cname) limit 1;
    if v_cid is null then
      insert into public.parcel_carriers (name, sort, wallet_id)
      values (v_cname, (select coalesce(max(sort),0)+1 from public.parcel_carriers),
              (select w.id from public.parcel_carriers w where w.is_wallet and lower(w.name) = 'paypoint' limit 1))
      returning id into v_cid;
      n_car := n_car + 1;
    end if;
    begin
      insert into public.parcel_shipments (ship_date, carrier_id, tracking_no, customer_name, cost, price, pay_method, note, created_by, ext_ref, source, branch_id)
      values (v_date, v_cid, public.parcel_txt(r,'tracking_no',60), public.parcel_txt(r,'customer_name',120),
              public.parcel_num(r,'cost',0,1000000), case when v_pay = 'self' then 0 else public.parcel_num(r,'price',0,1000000) end, v_pay, null, p_user, v_ref, 'paypoint', p_branch);
      n_ins := n_ins + 1;
    exception when unique_violation then n_skip := n_skip + 1;
              when others then bad := bad || jsonb_build_array(idx);
    end;
  end loop;

  begin
    insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
    values (p_user, p_user, 'parcel', 'parcel.import', 'parcel_shipments', 'paypoint',
            jsonb_build_object('inserted', n_ins, 'skipped', n_skip, 'invalid', jsonb_array_length(bad), 'carriers_added', n_car, 'branch_id', p_branch));
  exception when others then null; end;
  return jsonb_build_object('ok',true,'inserted',n_ins,'skipped',n_skip,'invalid',bad,'carriers_added',n_car);
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
  v_wid  bigint;
  v_y    integer;
  v_m    integer;
  v_pay  text;
  v_date date;
  v_ub   bigint;        -- สาขาของพนักงาน (เจ้าของ = null)
  v_br   bigint;        -- สาขาที่ใช้กับคำสั่งนี้ (null = รวมทุกสาขา — เฉพาะเจ้าของ, เฉพาะการดู)
  v_tbl  text;
  v_all  boolean;       -- ลิงก์ดูอย่างเดียวแบบรวมทุกสาขา
  r      record;
begin
  -- ===== ไม่ต้องล็อกอิน =====
  if p_action = 'login' then
    v_user := lower(btrim(coalesce(a->>'username','')));
    if v_user = '' or coalesce(a->>'password','') = '' then return jsonb_build_object('ok',false,'error','invalid'); end if;
    select count(*) into v_cnt from public.parcel_login_attempts
     where username = v_user and not ok and created_at > now() - interval '15 minutes';
    if v_cnt >= 5 then return jsonb_build_object('ok',false,'error','locked'); end if;

    select u.id, u.username, coalesce(u.full_name, u.username), u.branch_id into v_id, v_user, v_name, v_ub
      from public.parcel_users u
     where lower(u.username) = v_user and u.active
       and u.password_hash = extensions.crypt(a->>'password', u.password_hash);
    if v_id is not null then
      v_role := 'clerk';
    else
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
    return jsonb_build_object('ok',true,'token',v_tok,'user',jsonb_build_object('username',v_user,'name',v_name,'role',v_role,'branch_id',v_ub));
  end if;

  if p_action = 'share_view' then
    update public.parcel_share_links l set view_count = l.view_count + 1, last_viewed_at = now()
     where l.code = coalesce(a->>'c','') and l.revoked_at is null
    returning l.id, l.branch_id into v_id, v_br;
    if v_id is null then return jsonb_build_object('ok',false,'error','invalid'); end if;
    -- ลิงก์รวมทุกสาขา: เลือกดูทีละสาขาได้ (ส่ง branch มา) · ลิงก์ของสาขาเดียว: ล็อกสาขานั้นเสมอ
    v_all := v_br is null;
    if v_all and nullif(a->>'branch','') is not null then
      begin v_br := (a->>'branch')::bigint; exception when others then v_br := null; end;
      if v_br is not null and not exists (select 1 from public.parcel_branches b where b.id = v_br) then v_br := null; end if;
    end if;
    v_y := coalesce(nullif(a->>'year','')::int, date_part('year', now() at time zone 'Asia/Bangkok')::int);
    v_m := coalesce(nullif(a->>'month','')::int, date_part('month', now() at time zone 'Asia/Bangkok')::int);
    if v_m not between 1 and 12 or v_y not between 2000 and 2100 then return jsonb_build_object('ok',false,'error','invalid_month'); end if;
    return jsonb_build_object('ok',true,'readonly',true,'summary',public.parcel_summary(v_y,v_m,v_br),
      'ship',public.parcel_rows(v_y,v_m,'ship',2000,v_br),'topup',public.parcel_rows(v_y,v_m,'topup',2000,v_br),'expense',public.parcel_rows(v_y,v_m,'expense',2000,v_br),
      'branch',(select jsonb_build_object('id',b.id,'name',b.name) from public.parcel_branches b where b.id = v_br),
      'link_all', v_all,
      'branches', case when v_all then (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) order by b.sort, b.id),'[]'::jsonb)
                                        from public.parcel_branches b where b.active) else '[]'::jsonb end,
      'generated_at', now());
  end if;

  -- ===== ต้องล็อกอิน =====
  select * into v_sess from public.parcel_sessions s
   where s.token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at > now();
  if v_sess.token_hash is null then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  if v_sess.user_kind = 'clerk' then
    select u.branch_id into v_ub from public.parcel_users u where u.id = v_sess.user_id and u.active;
    if v_ub is null then
      delete from public.parcel_sessions where token_hash = v_sess.token_hash;
      return jsonb_build_object('ok',false,'error','unauthorized');
    end if;
  end if;
  if v_sess.user_kind = 'owner' and not exists (select 1 from public.app_users u where u.id = v_sess.user_id and coalesce(u.is_active,true) and u.role='admin') then
    delete from public.parcel_sessions where token_hash = v_sess.token_hash;
    return jsonb_build_object('ok',false,'error','unauthorized');
  end if;
  v_role := v_sess.user_kind; v_user := v_sess.username;
  if v_sess.last_used_at < now() - interval '1 hour' then
    update public.parcel_sessions set last_used_at = now(), expires_at = now() + interval '30 days' where token_hash = v_sess.token_hash;
  end if;

  -- สาขาของคำสั่ง: พนักงาน = สาขาตัวเองเสมอ · เจ้าของ = ตามที่ส่งมา (ว่าง = รวมทุกสาขา)
  if v_role = 'clerk' then
    v_br := v_ub;
  else
    begin v_br := nullif(a->>'branch','')::bigint; exception when others then return jsonb_build_object('ok',false,'error','invalid_branch'); end;
    if v_br is not null and not exists (select 1 from public.parcel_branches b where b.id = v_br) then
      return jsonb_build_object('ok',false,'error','invalid_branch');
    end if;
  end if;

  if p_action = 'logout' then
    delete from public.parcel_sessions where token_hash = v_sess.token_hash;
    return jsonb_build_object('ok',true);
  end if;

  if p_action = 'boot' then
    return jsonb_build_object('ok',true,
      'user', jsonb_build_object('username',v_user,'role',v_role,'branch_id',v_ub),
      'branches', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active) order by sort, id),'[]'::jsonb)
                   from public.parcel_branches where v_role = 'owner' or id = v_ub),
      'carriers', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'is_wallet',is_wallet,'wallet_id',wallet_id) order by sort, id),'[]'::jsonb) from public.parcel_carriers),
      'openings', (select coalesce(jsonb_object_agg(substr(key,9), value),'{}'::jsonb) from public.parcel_settings
                   where key like 'opening:%' and (v_role = 'owner' or key = 'opening:'||v_ub)));
  end if;

  if p_action in ('summary','list') then
    v_y := nullif(a->>'year','')::int; v_m := nullif(a->>'month','')::int;
    if v_y is null or v_m is null or v_m not between 1 and 12 or v_y not between 2000 and 2100 then
      return jsonb_build_object('ok',false,'error','invalid_month');
    end if;
    if p_action = 'summary' then
      return jsonb_build_object('ok',true,'summary',public.parcel_summary(v_y,v_m,v_br));
    end if;
    v_kind := a->>'kind';
    if v_kind not in ('ship','topup','expense') then return jsonb_build_object('ok',false,'error','invalid_kind'); end if;
    return jsonb_build_object('ok',true,'rows',public.parcel_rows(v_y,v_m,v_kind,2000,v_br));
  end if;

  if p_action = 'save' then
    v_kind := a->>'kind'; v_row := coalesce(a->'row','{}'::jsonb);
    v_id := nullif(v_row->>'id','')::bigint;

    -- Stage PARCEL-BRANCH: เพิ่ม/แก้ชื่อสาขา (เจ้าของเท่านั้น)
    if v_kind = 'branch' then
      if v_role <> 'owner' then return jsonb_build_object('ok',false,'error','forbidden'); end if;
      v_name := public.parcel_txt(v_row,'name',60);
      if v_name is null then return jsonb_build_object('ok',false,'error','invalid_name'); end if;
      begin
        if v_id is null then
          insert into public.parcel_branches (name, sort) values (v_name, (select coalesce(max(sort),0)+1 from public.parcel_branches)) returning id into v_id;
        else
          update public.parcel_branches set name = v_name, active = coalesce((v_row->>'active')::boolean, active) where id = v_id;
          if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
        end if;
      exception when unique_violation then return jsonb_build_object('ok',false,'error','name_exists'); end;
      return jsonb_build_object('ok',true,'id',v_id);
    end if;

    v_pay := v_row->>'pay';
    if v_pay not in ('cash','transfer') and not (v_kind = 'ship' and v_pay = 'self') then
      return jsonb_build_object('ok',false,'error','invalid_pay');
    end if;
    begin v_date := (v_row->>'date')::date; exception when others then v_date := null; end;
    if v_date is null or v_date < date '2000-01-01' or v_date > (now() at time zone 'Asia/Bangkok')::date + 1 then
      return jsonb_build_object('ok',false,'error','invalid_date');
    end if;
    if v_kind in ('ship','topup') and not exists (select 1 from public.parcel_carriers c where c.id = nullif(v_row->>'carrier_id','')::bigint) then
      return jsonb_build_object('ok',false,'error','invalid_carrier');
    end if;
    if v_kind = 'ship' and exists (select 1 from public.parcel_carriers c where c.id = nullif(v_row->>'carrier_id','')::bigint and c.is_wallet) then
      return jsonb_build_object('ok',false,'error','invalid_carrier');
    end if;
    v_tbl := case v_kind when 'ship' then 'parcel_shipments' when 'topup' then 'parcel_topups' when 'expense' then 'parcel_expenses' end;
    if v_tbl is null then return jsonb_build_object('ok',false,'error','invalid_kind'); end if;
    -- แก้ไข: พนักงานแก้ได้เฉพาะรายการของตัวเอง ในสาขาตัวเอง ที่ลงภายใน 7 วัน · เจ้าของแก้ได้ทุกรายการ (สาขาเดิมของรายการ)
    if v_id is not null then
      execute format('select created_by, created_at, branch_id from public.%I where id = $1 and deleted_at is null', v_tbl) into r using v_id;
      if r is null then return jsonb_build_object('ok',false,'error','not_found'); end if;
      if v_role <> 'owner' and (r.created_by <> v_user or r.created_at < now() - interval '7 days' or r.branch_id <> v_ub) then
        return jsonb_build_object('ok',false,'error','forbidden');
      end if;
    elsif v_br is null then
      return jsonb_build_object('ok',false,'error','choose_branch');
    end if;

    if v_kind = 'ship' then
      if v_id is null then
        insert into public.parcel_shipments (ship_date, carrier_id, tracking_no, customer_name, cost, price, pay_method, note, created_by, branch_id)
        values (v_date, (v_row->>'carrier_id')::bigint, public.parcel_txt(v_row,'tracking_no',60), public.parcel_txt(v_row,'customer_name',120),
                public.parcel_num(v_row,'cost',0,1000000), case when v_pay = 'self' then 0 else public.parcel_num(v_row,'price',0,1000000) end, v_pay, public.parcel_txt(v_row,'note',300), v_user, v_br)
        returning id into v_id;
      else
        update public.parcel_shipments set ship_date=v_date, carrier_id=(v_row->>'carrier_id')::bigint,
               tracking_no=public.parcel_txt(v_row,'tracking_no',60), customer_name=public.parcel_txt(v_row,'customer_name',120),
               cost=public.parcel_num(v_row,'cost',0,1000000), price=case when v_pay = 'self' then 0 else public.parcel_num(v_row,'price',0,1000000) end,
               pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    elsif v_kind = 'topup' then
      if v_id is null then
        insert into public.parcel_topups (topup_date, carrier_id, amount, pay_method, note, created_by, branch_id)
        values (v_date, (v_row->>'carrier_id')::bigint, public.parcel_num(v_row,'amount',0.01,1000000), v_pay, public.parcel_txt(v_row,'note',300), v_user, v_br)
        returning id into v_id;
      else
        update public.parcel_topups set topup_date=v_date, carrier_id=(v_row->>'carrier_id')::bigint,
               amount=public.parcel_num(v_row,'amount',0.01,1000000), pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    else
      if public.parcel_txt(v_row,'item',120) is null then return jsonb_build_object('ok',false,'error','invalid_item'); end if;
      if v_id is null then
        insert into public.parcel_expenses (exp_date, item, amount, pay_method, note, created_by, branch_id)
        values (v_date, public.parcel_txt(v_row,'item',120), public.parcel_num(v_row,'amount',0.01,1000000), v_pay, public.parcel_txt(v_row,'note',300), v_user, v_br)
        returning id into v_id;
      else
        update public.parcel_expenses set exp_date=v_date, item=public.parcel_txt(v_row,'item',120),
               amount=public.parcel_num(v_row,'amount',0.01,1000000), pay_method=v_pay, note=public.parcel_txt(v_row,'note',300), updated_at=now()
         where id = v_id;
      end if;
    end if;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  -- นำเข้ารายงาน PayPoint (เข้าสาขาที่เลือก — พนักงาน = สาขาตัวเอง)
  if p_action in ('import','import_check') then
    if v_br is null then return jsonb_build_object('ok',false,'error','choose_branch'); end if;
    return public.parcel_import(p_action, v_user, a, v_br);
  end if;

  if p_action = 'delete' then
    v_kind := a->>'kind'; v_id := nullif(a->>'id','')::bigint;
    v_tbl := case v_kind when 'ship' then 'parcel_shipments' when 'topup' then 'parcel_topups' when 'expense' then 'parcel_expenses' end;
    if v_tbl is null or v_id is null then return jsonb_build_object('ok',false,'error','invalid'); end if;
    execute format('select created_by, created_at, branch_id from public.%I where id = $1 and deleted_at is null', v_tbl) into r using v_id;
    if r is null then return jsonb_build_object('ok',false,'error','not_found'); end if;
    if v_role <> 'owner' and (r.created_by <> v_user or r.created_at < now() - interval '7 days' or r.branch_id <> v_ub) then
      return jsonb_build_object('ok',false,'error','forbidden');
    end if;
    execute format('update public.%I set deleted_at = now(), deleted_by = $2 where id = $1', v_tbl) using v_id, v_user;
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
    v_wid := nullif(a->>'wallet_id','')::bigint;
    if v_wid is not null and not exists (select 1 from public.parcel_carriers w where w.id = v_wid and w.is_wallet) then
      return jsonb_build_object('ok',false,'error','invalid_wallet');
    end if;
    if v_id is null then
      insert into public.parcel_carriers (name, sort, wallet_id) values (v_name, (select coalesce(max(sort),0)+1 from public.parcel_carriers), v_wid)
      on conflict (name) do update set active = true returning id into v_id;
    else
      if v_wid is not null and exists (select 1 from public.parcel_carriers c where c.id = v_id and c.is_wallet) then
        return jsonb_build_object('ok',false,'error','invalid_wallet');
      end if;
      update public.parcel_carriers set name = v_name, active = coalesce((a->>'active')::boolean, active),
             wallet_id = case when a ? 'wallet_id' then v_wid else wallet_id end
       where id = v_id;
    end if;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  if p_action = 'opening_save' then
    if v_br is null then return jsonb_build_object('ok',false,'error','choose_branch'); end if;
    insert into public.parcel_settings (key, value, updated_by, updated_at)
    values ('opening:'||v_br, jsonb_build_object('cash', public.parcel_num(a,'cash',-10000000,10000000), 'transfer', public.parcel_num(a,'transfer',-10000000,10000000)), v_user, now())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    return jsonb_build_object('ok',true);
  end if;

  if p_action = 'users_list' then
    return jsonb_build_object('ok',true,'users',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'username',u.username,'name',u.full_name,'active',u.active,
             'created_at',u.created_at,'branch_id',u.branch_id,'branch',b.name) order by u.id),'[]'::jsonb)
           from public.parcel_users u left join public.parcel_branches b on b.id = u.branch_id));
  end if;

  if p_action = 'user_save' then
    v_id := nullif(a->>'id','')::bigint;
    v_name := lower(btrim(coalesce(a->>'username','')));
    v_wid := nullif(a->>'branch_id','')::bigint;   -- สาขาของพนักงาน
    if v_wid is not null and not exists (select 1 from public.parcel_branches b where b.id = v_wid) then
      return jsonb_build_object('ok',false,'error','invalid_branch');
    end if;
    if v_id is null then
      if v_name !~ '^[a-z0-9._-]{3,30}$' then return jsonb_build_object('ok',false,'error','invalid_username'); end if;
      if exists (select 1 from public.parcel_users where lower(username)=v_name) or exists (select 1 from public.app_users where lower(username)=v_name) then
        return jsonb_build_object('ok',false,'error','username_exists');
      end if;
      if length(coalesce(a->>'password','')) < 6 then return jsonb_build_object('ok',false,'error','password_short'); end if;
      if v_wid is null then return jsonb_build_object('ok',false,'error','choose_branch'); end if;
      insert into public.parcel_users (username, full_name, password_hash, created_by, branch_id)
      values (v_name, public.parcel_txt(a,'full_name',80), extensions.crypt(a->>'password', extensions.gen_salt('bf',10)), v_user, v_wid)
      returning id into v_id;
    else
      update public.parcel_users set full_name = coalesce(public.parcel_txt(a,'full_name',80), full_name),
             active = coalesce((a->>'active')::boolean, active), branch_id = coalesce(v_wid, branch_id) where id = v_id;
      if coalesce(a->>'password','') <> '' then
        if length(a->>'password') < 6 then return jsonb_build_object('ok',false,'error','password_short'); end if;
        update public.parcel_users set password_hash = extensions.crypt(a->>'password', extensions.gen_salt('bf',10)) where id = v_id;
        delete from public.parcel_sessions where user_kind = 'clerk' and user_id = v_id;
      end if;
      if (a->>'active')::boolean is false then delete from public.parcel_sessions where user_kind = 'clerk' and user_id = v_id; end if;
    end if;
    begin
      insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
      values (v_user, v_user, 'parcel_owner', 'parcel.user.save', 'parcel_user', v_id::text, jsonb_build_object('active', a->'active', 'branch_id', v_wid));
    exception when others then null; end;
    return jsonb_build_object('ok',true,'id',v_id);
  end if;

  -- ลิงก์ดูอย่างเดียว: 1 ลิงก์ต่อ 1 ขอบเขต (สาขาที่เลือก หรือ รวมทุกสาขา)
  if p_action in ('share_get','share_create','share_revoke') then
    if p_action in ('share_create','share_revoke') then
      update public.parcel_share_links set revoked_at = now(), revoked_by = v_user where revoked_at is null and branch_id is not distinct from v_br;
    end if;
    if p_action = 'share_create' then
      loop
        v_tok := (select string_agg(substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (get_byte(b, i) % 62) + 1, 1), '')
                  from (select extensions.gen_random_bytes(11) b) x, generate_series(0,10) i);
        exit when not exists (select 1 from public.parcel_share_links where code = v_tok);
      end loop;
      insert into public.parcel_share_links (code, created_by, branch_id) values (v_tok, v_user, v_br);
    end if;
    if p_action <> 'share_get' then
      begin
        insert into public.audit_logs (actor_code, actor_name, actor_role, action, entity_type, entity_id, detail)
        values (v_user, v_user, 'parcel_owner', 'parcel.'||p_action, 'parcel_share', coalesce(v_br::text,'all'), '{}'::jsonb);
      exception when others then null; end;
    end if;
    return jsonb_build_object('ok',true,'link',(select jsonb_build_object('code',code,'created_at',created_at,'created_by',created_by,
                     'view_count',view_count,'last_viewed_at',last_viewed_at,'branch_id',branch_id) from public.parcel_share_links
                     where revoked_at is null and branch_id is not distinct from v_br order by id desc limit 1));
  end if;

  return jsonb_build_object('ok',false,'error','unknown_action');
end;
$$;

-- ---------- สิทธิ์: service_role เท่านั้น ----------
revoke all on function public.parcel_rows(integer,integer,text,integer,bigint) from public, anon, authenticated;
grant execute on function public.parcel_rows(integer,integer,text,integer,bigint) to service_role;
revoke all on function public.parcel_summary(integer,integer,bigint) from public, anon, authenticated;
grant execute on function public.parcel_summary(integer,integer,bigint) to service_role;
revoke all on function public.parcel_import(text,text,jsonb,bigint) from public, anon, authenticated;
grant execute on function public.parcel_import(text,text,jsonb,bigint) to service_role;
revoke all on function public.parcel_api(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.parcel_api(text,text,jsonb) to service_role;

-- ---------- ตรวจผล — ควรได้ branches >= 2, col_ok = 5, unassigned = 0, fn_ok = 4, anon_exec = 0 ----------
select
  (select count(*) from public.parcel_branches)                                                                                                   as branches,
  (select count(*) from information_schema.columns where table_schema='public' and column_name='branch_id'
     and table_name in ('parcel_shipments','parcel_topups','parcel_expenses','parcel_users','parcel_share_links'))                               as col_ok,
  (select (select count(*) from public.parcel_shipments where branch_id is null) + (select count(*) from public.parcel_topups where branch_id is null)
        + (select count(*) from public.parcel_expenses where branch_id is null))                                                                  as unassigned,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
     and p.proname in ('parcel_rows','parcel_summary','parcel_import','parcel_api'))                                                              as fn_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'parcel\_%'
     and has_function_privilege('anon', p.oid, 'execute'))                                                                                        as anon_exec;

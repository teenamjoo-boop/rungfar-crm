-- =============================================================
-- STAGE PARCEL-AUDIT — หน้า "ตรวจสอบ" กันการโกง (เจ้าของ + ลิงก์รวมทุกสาขาของเจ้านาย เท่านั้น)
--   1) ส่งของบริษัท: ชื่อผู้ส่งต้องเป็น "รุ่งฟ้า เชิงหลำ <ชื่อคนสั่ง>" → สรุปว่าใครสั่งส่งกี่ชิ้น เท่าไร
--      ไม่มีชื่อคนสั่ง → ขึ้นแดง · การนำเข้าตัดสิน "ส่งเอง" จากชื่อผู้ส่งที่ฐานข้อมูล (ไม่เชื่อค่าจากหน้าเว็บ)
--      พนักงานกด "ส่งเอง" ลงเองไม่ได้
--   2) ขายเท่าทุน/ขาดทุน (ราคาขาย ≤ ต้นทุน) → รายการต้องตรวจ
--   3) พนักงานส่งของตัวเอง: เจ้าของตั้งรายชื่อ (ชื่อผู้ส่งใน PayPoint) → สรุปชิ้น/จ่าย/กำไร เทียบกำไรเฉลี่ยลูกค้าทั่วไป
--      + รายจ่ายอื่นที่พนักงานลงเอง (กระทบเงินสด/เงินในบัญชี)
--   4) เช็คยอด: เครดิต PayPoint / เงินสด / เงินในบัญชี ที่ต้องตรงกับของจริง แยกสาขา + นำเข้าล่าสุด
--   ฟังก์ชันใหม่: parcel_requester, parcel_staff, parcel_audit · แก้: parcel_import, parcel_api
--   ไม่แตะตาราง ไม่แตะข้อมูลเดิม · Edge Function ไม่ต้องแก้ (ใช้คำสั่ง summary / share_view / save เดิม)
-- ต้องรันหลัง 20261021f_parcel_clerk_lock.sql · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

-- ชื่อคนสั่งจากชื่อผู้ส่ง: "รุ่งฟ้า เชิงหลำ เอิน" → "เอิน" · "รุ่งฟ้า เชิงหลำ" → "" (ไม่ระบุ)
create or replace function public.parcel_requester(p_name text)
returns text language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p_name,''),'รุ่งฟ้า|เชิงหลำ','','g'),
         '\s+',' ','g'),'^[ _.,:/()-]+|[ _.,:/()-]+$','','g'));
$$;

-- รายชื่อพนักงาน: parcel_settings 'staff_names' = ["tin tin, thin", ...] (ชื่อแรก = ชื่อที่แสดง)
create or replace function public.parcel_staff()
returns table(idx integer, label text, keys text[]) language sql stable security definer set search_path = '' as $$
  select x.o::int, btrim(split_part(x.v,',',1)),
         array(select lower(btrim(k)) from unnest(string_to_array(x.v,',')) k where btrim(k) <> '')
    from public.parcel_settings st, jsonb_array_elements_text(st.value) with ordinality x(v,o)
   where st.key = 'staff_names' and jsonb_typeof(st.value) = 'array';
$$;

create or replace function public.parcel_audit(p_year integer, p_month integer, p_branch bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  with br as (select * from public.parcel_branches where p_branch is null or id = p_branch),
       st as (select * from public.parcel_staff()),
       sm as (select s.*, c.name carrier, b.name branch, public.parcel_requester(s.customer_name) req,
                     (select st.idx from st where exists (select 1 from unnest(st.keys) k where position(k in lower(coalesce(s.customer_name,''))) > 0)
                      order by st.idx limit 1) staff_idx
                from public.parcel_shipments s
                left join public.parcel_carriers c on c.id = s.carrier_id
                join br b on b.id = s.branch_id
               where s.deleted_at is null and date_part('year',s.ship_date) = p_year and date_part('month',s.ship_date) = p_month),
       cu as (select * from sm where pay_method <> 'self'),
       jr as (select id, jsonb_build_object('date',ship_date,'carrier',carrier,'tracking_no',tracking_no,'customer_name',customer_name,
                     'price',price,'cost',cost,'pay',pay_method,'branch',branch,'by',created_by,
                     'staff',(select st.label from st where st.idx = sm.staff_idx)) j, ship_date from sm)
  select jsonb_build_object(
    -- 1) ของบริษัท (ส่งเอง) แยกตามคนสั่ง
    'company', (select coalesce(jsonb_agg(jsonb_build_object('name',req,'count',n,'cost',cost) order by (req = '') desc, cost desc, req),'[]'::jsonb)
                  from (select req, count(*) n, sum(cost) cost from sm where pay_method = 'self' group by req) x),
    'company_unnamed', (select coalesce(jsonb_agg(jr.j order by jr.ship_date desc, jr.id desc),'[]'::jsonb)
                          from jr where jr.id in (select id from sm where pay_method = 'self' and req = '' order by ship_date desc, id desc limit 100)),
    -- 2) ขายเท่าทุน/ขาดทุน
    'under_count', (select count(*) from cu where price <= cost),
    'under', (select coalesce(jsonb_agg(jr.j order by jr.ship_date desc, jr.id desc),'[]'::jsonb)
                from jr where jr.id in (select id from cu where price <= cost order by ship_date desc, id desc limit 100)),
    -- 3) พนักงานส่งของตัวเอง (ไม่นับที่ส่งในนามบริษัท)
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('label',st.label,'keys',to_jsonb(st.keys),
                 'count',(select count(*) from cu where staff_idx = st.idx),
                 'price',(select coalesce(sum(price),0) from cu where staff_idx = st.idx),
                 'cost', (select coalesce(sum(cost),0)  from cu where staff_idx = st.idx),
                 'under',(select count(*) from cu where staff_idx = st.idx and price <= cost),
                 'other_avg',(select round(avg(o.price - o.cost),2) from cu o where o.staff_idx is null
                                and o.carrier_id in (select carrier_id from cu where staff_idx = st.idx)),
                 'rows',(select coalesce(jsonb_agg(jr.j order by jr.ship_date desc, jr.id desc),'[]'::jsonb)
                           from jr where jr.id in (select id from cu where staff_idx = st.idx order by ship_date desc, id desc limit 100)))
               order by st.idx),'[]'::jsonb) from st),
    'clerk_expense', (select coalesce(jsonb_agg(jsonb_build_object('date',e.exp_date,'item',e.item,'amount',e.amount,'pay',e.pay_method,'by',e.created_by,'branch',b.name)
                        order by e.exp_date desc, e.id desc),'[]'::jsonb)
                        from public.parcel_expenses e join br b on b.id = e.branch_id
                       where e.deleted_at is null and date_part('year',e.exp_date) = p_year and date_part('month',e.exp_date) = p_month
                         and lower(e.created_by) in (select lower(u.username) from public.parcel_users u)),
    -- 4) เช็คยอด (ตอนนี้ · ทั้งหมดตั้งแต่เริ่ม) แยกสาขา
    'check', (select coalesce(jsonb_agg(jsonb_build_object('branch_id',b.id,'branch',b.name,
        'credit',(select coalesce(jsonb_agg(jsonb_build_object('name',h.name,'is_wallet',h.is_wallet,
                    'left',(select coalesce(sum(t.amount),0) from public.parcel_topups t where t.deleted_at is null and t.branch_id = b.id
                              and t.carrier_id in (select c.id from public.parcel_carriers c where coalesce(c.wallet_id,c.id) = h.id))
                         - (select coalesce(sum(s.cost),0) from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id
                              and s.carrier_id in (select c.id from public.parcel_carriers c where coalesce(c.wallet_id,c.id) = h.id)))
                    order by h.is_wallet desc, h.sort, h.id),'[]'::jsonb)
                  from public.parcel_carriers h where h.wallet_id is null and (h.is_wallet
                    or exists (select 1 from public.parcel_topups t where t.deleted_at is null and t.branch_id = b.id and t.carrier_id in (select c.id from public.parcel_carriers c where coalesce(c.wallet_id,c.id) = h.id))
                    or exists (select 1 from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id and s.carrier_id in (select c.id from public.parcel_carriers c where coalesce(c.wallet_id,c.id) = h.id)))),
        'cash', coalesce((select (st2.value->>'cash')::numeric from public.parcel_settings st2 where st2.key = 'opening:'||b.id),0)
              + (select coalesce(sum(s.price),0) from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id and s.pay_method = 'cash')
              - (select coalesce(sum(e.amount),0) from public.parcel_expenses e where e.deleted_at is null and e.branch_id = b.id and e.pay_method = 'cash'),
        'bank', coalesce((select (st2.value->>'transfer')::numeric from public.parcel_settings st2 where st2.key = 'opening:'||b.id),0)
              + (select coalesce(sum(s.price),0) from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id and s.pay_method = 'transfer')
              - (select coalesce(sum(e.amount),0) from public.parcel_expenses e where e.deleted_at is null and e.branch_id = b.id and e.pay_method = 'transfer'),
        'last_ship', (select max(s.ship_date) from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id),
        'last_import', (select max(s.created_at) from public.parcel_shipments s where s.deleted_at is null and s.branch_id = b.id and s.source = 'paypoint'))
      order by b.sort, b.id),'[]'::jsonb) from br b)
  );
$$;

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
    -- Stage PARCEL-AUDIT: ผู้ส่งชื่อ "รุ่งฟ้า" = ของบริษัท (ส่งเอง) เสมอ · ชื่ออื่นตั้งเป็นส่งเองไม่ได้
    if coalesce(r->>'customer_name','') ~ 'รุ่งฟ้า' then v_pay := 'self';
    elsif v_pay = 'self' then v_pay := 'bad'; end if;
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
      'audit', case when v_all then public.parcel_audit(v_y,v_m,v_br) else null end,   -- Stage PARCEL-AUDIT: เฉพาะลิงก์รวมทุกสาขา (ของเจ้านาย)
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
                   where key like 'opening:%' and (v_role = 'owner' or key = 'opening:'||v_ub)),
      'staff', case when v_role = 'owner' then coalesce((select value from public.parcel_settings where key = 'staff_names'),'[]'::jsonb) else '[]'::jsonb end);
  end if;

  if p_action in ('summary','list') then
    v_y := nullif(a->>'year','')::int; v_m := nullif(a->>'month','')::int;
    if v_y is null or v_m is null or v_m not between 1 and 12 or v_y not between 2000 and 2100 then
      return jsonb_build_object('ok',false,'error','invalid_month');
    end if;
    if p_action = 'summary' then
      -- Stage PARCEL-AUDIT: หน้า ตรวจสอบ — เฉพาะเจ้าของ (พนักงานไม่ได้รับข้อมูลนี้)
      return jsonb_build_object('ok',true,'summary',public.parcel_summary(v_y,v_m,v_br))
          || case when v_role = 'owner' then jsonb_build_object('audit',public.parcel_audit(v_y,v_m,v_br)) else '{}'::jsonb end;
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

    -- Stage PARCEL-AUDIT: รายชื่อพนักงานที่ส่งของตัวเอง (ชื่อผู้ส่งใน PayPoint · คั่นหลายชื่อด้วย ,) — เจ้าของเท่านั้น
    if v_kind = 'staff' then
      if v_role <> 'owner' then return jsonb_build_object('ok',false,'error','forbidden'); end if;
      if jsonb_typeof(v_row->'names') <> 'array' or jsonb_array_length(v_row->'names') > 30 then
        return jsonb_build_object('ok',false,'error','invalid');
      end if;
      insert into public.parcel_settings (key, value, updated_by, updated_at)
      values ('staff_names', (select coalesce(jsonb_agg(v order by o),'[]'::jsonb) from (
                select left(btrim(regexp_replace(x,'\s+',' ','g')),120) v, o from jsonb_array_elements_text(v_row->'names') with ordinality t(x,o)) y
              where v <> '' and btrim(split_part(v,',',1)) <> ''), v_user, now())
      on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
      return jsonb_build_object('ok',true);
    end if;

    -- Stage PARCEL-AUDIT: พนักงานลง "ส่งเอง" เองไม่ได้ (ของบริษัทต้องมาจากรายงาน PayPoint ชื่อผู้ส่ง รุ่งฟ้า… เท่านั้น)
    if v_role <> 'owner' and v_kind = 'ship' and v_id is null and coalesce(v_row->>'pay','') = 'self' then
      return jsonb_build_object('ok',false,'error','forbidden');
    end if;

    -- Stage PARCEL-LOCK: พนักงานแก้รายการเดิมไม่ได้ ยกเว้น "ส่งพัสดุ" ในสาขาตัวเอง → เปลี่ยนได้แค่ เงินสด ⇄ โอน
    if v_role <> 'owner' and v_id is not null then
      if v_kind <> 'ship' or coalesce(v_row->>'pay','') not in ('cash','transfer') then
        return jsonb_build_object('ok',false,'error','forbidden');
      end if;
      update public.parcel_shipments set pay_method = v_row->>'pay', updated_at = now()
       where id = v_id and deleted_at is null and branch_id = v_ub and pay_method in ('cash','transfer');
      if not found then return jsonb_build_object('ok',false,'error','forbidden'); end if;
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
    -- Stage PARCEL-LOCK: ลบได้เฉพาะเจ้าของ
    if v_role <> 'owner' then
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

revoke all on function public.parcel_requester(text) from public, anon, authenticated;
revoke all on function public.parcel_staff() from public, anon, authenticated;
revoke all on function public.parcel_audit(integer,integer,bigint) from public, anon, authenticated;
revoke all on function public.parcel_import(text,text,jsonb,bigint) from public, anon, authenticated;
revoke all on function public.parcel_api(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.parcel_requester(text) to service_role;
grant execute on function public.parcel_staff() to service_role;
grant execute on function public.parcel_audit(integer,integer,bigint) to service_role;
grant execute on function public.parcel_import(text,text,jsonb,bigint) to service_role;
grant execute on function public.parcel_api(text,text,jsonb) to service_role;

-- ---------- ตรวจผล — ควรได้ fn_ok = 3, audit_ok = 2, req_ok = 1, anon_exec = 0 ----------
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
     and p.proname in ('parcel_requester','parcel_staff','parcel_audit'))                                                    as fn_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
     and p.proname in ('parcel_api','parcel_import') and pg_get_functiondef(p.oid) like '%PARCEL-AUDIT%')                     as audit_ok,
  (select count(*) where public.parcel_requester('รุ่งฟ้า เชิงหลำ เอิน') = 'เอิน' and public.parcel_requester('รุ่งฟ้า เชิงหลำ') = '') as req_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'parcel\_%'
     and has_function_privilege('anon', p.oid, 'execute'))                                                                     as anon_exec;

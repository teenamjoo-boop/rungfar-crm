-- =============================================================
-- STAGE PARCEL-LOCK — พนักงานแก้/ลบรายการไม่ได้
--   * พนักงาน: บันทึกรายการใหม่ได้ตามเดิม · รายการที่มีอยู่แล้ว (รวมที่นำเข้าจาก PayPoint) ล็อกทั้งหมด
--     เปลี่ยนได้อย่างเดียว = ช่องทางรับเงินของ "ส่งพัสดุ" ในสาขาตัวเอง: เงินสด ⇄ โอน (ส่งเองแก้ไม่ได้)
--   * ลบรายการ: เจ้าของเท่านั้น
--   แก้เฉพาะ parcel_api (ส่วนอื่นเหมือน 20261021e ทุกบรรทัด) · ไม่แตะตาราง ไม่แตะข้อมูล
-- ต้องรันหลัง 20261021e_parcel_branches.sql · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

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

revoke all on function public.parcel_api(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.parcel_api(text,text,jsonb) to service_role;

-- ---------- ตรวจผล — ควรได้ lock_ok = 1, anon_exec = 0 ----------
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='parcel_api'
     and pg_get_functiondef(p.oid) like '%PARCEL-LOCK%')                                                                       as lock_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'parcel\_%'
     and has_function_privilege('anon', p.oid, 'execute'))                                                                     as anon_exec;

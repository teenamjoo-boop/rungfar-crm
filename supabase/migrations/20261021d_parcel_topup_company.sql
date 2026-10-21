-- =============================================================
-- STAGE PARCEL-COMPANY-TOPUP — เงินเติมเครดิตขนส่งเป็นเงินบริษัท
--   เงินสดในมือ / เงินในบัญชีขนส่ง = ยอดตั้งต้น + รับจากลูกค้า − รายจ่ายอื่นของร้าน
--   (ยอดเติมเครดิตไม่หักเงินร้านอีกต่อไป · เครดิตคงเหลือ PayPoint คิดเหมือนเดิม)
--   แก้เฉพาะ parcel_summary (money.cash.out / money.transfer.out) — ไม่แตะตาราง ไม่แตะข้อมูล
-- ต้องรันหลัง 20261021c_parcel_wallet_self.sql · รันซ้ำได้ · รันบน STAGING ก่อน
-- =============================================================

create or replace function public.parcel_summary(p_year integer, p_month integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  with s as (select * from public.parcel_shipments where deleted_at is null),
       t as (select * from public.parcel_topups   where deleted_at is null),
       e as (select * from public.parcel_expenses where deleted_at is null),
       c as (select x.*, coalesce(x.wallet_id, x.id) holder from public.parcel_carriers x),
       op as (select coalesce((value->>'cash')::numeric,0) cash, coalesce((value->>'transfer')::numeric,0) tr
              from public.parcel_settings where key = 'opening'),
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
    'year', p_year, 'month', p_month,
    -- profit = กำไรจากลูกค้า (ไม่รวมส่งเอง) · self_cost = ค่าส่งของตัวเอง · net = profit − self_cost − รายจ่ายอื่น
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
    -- เครดิตคงเหลือแยกตาม "ที่เก็บเครดิต": กระเป๋า (เช่น PayPoint) รวมทุกขนส่งที่ผูกไว้ · ขนส่งที่ไม่ผูกกระเป๋า = เครดิตแยก
    'credit', (select coalesce(jsonb_agg(x order by (x->>'is_wallet')::boolean desc, (x->>'sort')::int, (x->>'id')::bigint),'[]'::jsonb) from (
                 select jsonb_build_object('id',h.id,'name',h.name,'is_wallet',h.is_wallet,'active',h.active,'sort',h.sort,
                     'members',(select coalesce(jsonb_agg(m.name order by m.sort, m.id),'[]'::jsonb) from c m where m.wallet_id = h.id),
                     'topup',(select coalesce(sum(amount),0) from t where t.carrier_id in (select id from c where holder = h.id)),
                     'used',(select coalesce(sum(cost),0) from s where s.carrier_id in (select id from c where holder = h.id)),
                     'count',(select count(*) from s where s.carrier_id in (select id from c where holder = h.id))) x
                 from c h where h.wallet_id is null) y),
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

revoke all on function public.parcel_summary(integer,integer) from public, anon, authenticated;
grant execute on function public.parcel_summary(integer,integer) to service_role;

-- ---------- ตรวจผล — ควรได้ fn_ok = 1, anon_exec = 0 ----------
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='parcel_summary'
     and pg_get_functiondef(p.oid) not like '%from t where pay_method%')                                                       as fn_ok,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'parcel\_%'
     and has_function_privilege('anon', p.oid, 'execute'))                                                                     as anon_exec;

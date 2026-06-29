-- =============================================================
-- STAGE 46A-2 — Delete Safety Lock (หยุด client direct DELETE บนตารางสำคัญ)
-- เป้าหมาย:
--   * ปิดความสามารถ "ลบจริง" จากฝั่ง browser/client (anon key) สำหรับตารางสำคัญ
--     public.customers / public.documents จนกว่าจะออกแบบ SECURITY DEFINER
--     delete RPC แบบปลอดภัยใน stage ถัดไป
--   * เป็น "safety lock" — เพิกถอนสิทธิ์ (REVOKE DELETE) เป็นหลัก
--     ไม่ลบข้อมูล ไม่แก้ไขแถว ไม่แตะ storage
--
--   หลักการ: PostgreSQL จะอนุญาต DELETE ก็ต่อเมื่อ "มี privilege ระดับตาราง"
--   และ "ผ่าน RLS" ทั้งคู่ → การเพิกถอน privilege อย่างเดียวก็เพียงพอที่จะบล็อก
--   client DELETE ได้แน่นอน โดยไม่ต้องแตะ policy เดิม (ปลอดภัย/ย้อนกลับง่าย)
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ DELETE ไม่ได้อีกต่อไป (customers/documents)
--                           ✅ SELECT / INSERT / UPDATE ยังทำงานเหมือนเดิม
--   * service_role (ใช้ฝั่ง server / Edge Functions): ไม่ได้รับผลกระทบ
--     (service_role bypass privilege/RLS) → งานฝั่ง server ทำงานต่อได้ตามเดิม
--
-- ⚠️ ไม่ DROP policy / ไม่ ALTER โครงสร้างตาราง / ไม่ DELETE row / ไม่แตะ storage
-- ⚠️ ไม่แตะ delete_requests (ตารางคำขอลบยัง select/insert/update ได้ตามเดิม)
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าไม่มีสิทธิ์อยู่แล้ว)
-- =============================================================

do $$
begin
  -- ── public.customers ──────────────────────────────────────────────────────
  if to_regclass('public.customers') is not null then
    revoke delete on table public.customers from anon;
    revoke delete on table public.customers from authenticated;
    raise notice 'safety-lock: revoked DELETE on public.customers from anon, authenticated';
  else
    raise notice 'safety-lock: public.customers not found — skipped';
  end if;

  -- ── public.documents ──────────────────────────────────────────────────────
  if to_regclass('public.documents') is not null then
    revoke delete on table public.documents from anon;
    revoke delete on table public.documents from authenticated;
    raise notice 'safety-lock: revoked DELETE on public.documents from anon, authenticated';
  else
    raise notice 'safety-lock: public.documents not found — skipped';
  end if;
end$$;

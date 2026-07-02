-- =============================================================
-- STAGE 52A-1 — Revoke Direct Write on public.documents (safety lock)
-- เป้าหมาย:
--   * ปิดทาง "เขียนเอกสารแบบ browser-direct" (anon key) บน public.documents
--   * การเขียนเอกสารทั้งหมดตอนนี้ไปผ่านฝั่ง server แล้ว:
--       - customer-doc-upload Edge Function  (อัปโหลดเอกสาร → Storage + insert แถว
--         ด้วย service role — Stage 33B)
--       - customer-doc-sign Edge Function    (server-stamp signed_at/doc_status ด้วย service role)
--       - line-doc-inbox-admin Edge Function (approve เอกสารจาก LINE → insert ด้วย service role)
--       - app_update_document_metadata RPC   (แก้ metadata — SECURITY DEFINER, Stage 34 / 20260705)
--     ฝั่ง browser เหลือเฉพาะ SELECT (รายละเอียด/preview) + RPC read (app_list_documents ฯลฯ)
--     การลบเอกสารวิ่งผ่าน delete-request flow (app_create_delete_request) ไม่ใช่ direct delete
--
-- plain-language:
--   revoke INSERT/UPDATE = ปิดประตูเก่าที่ browser เขียน/แก้แถวเอกสารเองได้ตรง ๆ ด้วย anon key
--   CRM ยังทำงานได้ครบ เพราะ upload / sign / แก้ metadata วิ่งผ่าน Edge Function + RPC หมดแล้ว
--
--   หลักการ: PostgreSQL อนุญาต INSERT/UPDATE ก็ต่อเมื่อมี privilege ระดับตาราง →
--   เพิกถอน privilege อย่างเดียวก็บล็อก client write ได้แน่นอน โดยไม่แตะ RLS policy เดิม
--
--   ผลกระทบ:
--   * anon / authenticated: ❌ INSERT / UPDATE ตรงไม่ได้อีกต่อไป (documents)
--                           ❌ DELETE ถูกบล็อกไปแล้ว (20260710) — ทำซ้ำในนี้แบบ idempotent เผื่อไว้
--                           ✅ SELECT ยังทำงานเหมือนเดิม (ไม่แตะ)
--   * service_role (Edge Functions) + SECURITY DEFINER RPC: ไม่กระทบ
--     (service role bypass grant ระดับตาราง; RPC รันด้วยสิทธิ์ owner → เขียนได้ตามปกติ)
--
-- ⚠️ ไม่ revoke SELECT / ไม่แตะ RLS policy / ไม่แตะ Storage bucket rules
-- ⚠️ ไม่ DROP / ไม่ TRUNCATE / ไม่ DELETE row / ไม่ ALTER โครงสร้างตาราง
-- ⚠️ Idempotent — รันซ้ำได้ (REVOKE ไม่มีผลข้างเคียงถ้าไม่มีสิทธิ์อยู่แล้ว)
-- =============================================================

do $$
begin
  if to_regclass('public.documents') is not null then
    -- ปิดประตู browser-direct write — งานเขียนปกติต้องผ่าน Edge Function / SECURITY DEFINER RPC:
    --   upload → customer-doc-upload, sign → customer-doc-sign,
    --   metadata → app_update_document_metadata, delete → delete-request flow
    revoke insert on table public.documents from anon;
    revoke insert on table public.documents from authenticated;
    revoke update on table public.documents from anon;
    revoke update on table public.documents from authenticated;
    -- DELETE ถูก revoke ไปแล้วใน 20260710_delete_safety_lock.sql — ทำซ้ำแบบปลอดภัย (no-op ถ้าถูกถอนแล้ว)
    revoke delete on table public.documents from anon;
    revoke delete on table public.documents from authenticated;
    raise notice 'safety-lock: revoked INSERT, UPDATE (and re-asserted DELETE) on public.documents from anon, authenticated (writes now go via customer-doc-upload / customer-doc-sign Edge Functions and app_update_document_metadata RPC)';
  else
    raise notice 'safety-lock: public.documents not found — skipped';
  end if;
end$$;

# Stage ALERT-SETTINGS-DB — หน้า "ตั้งค่าแจ้งเตือน" อ่าน/บันทึกค่าจากฐานข้อมูล (ใช้ร่วมทุกเครื่อง + หน้าลิงก์ลูกค้า)
#   ยังเก็บสำเนาใน localStorage ไว้ใช้ตอนออฟไลน์/ยังไม่ได้รัน SQL (พฤติกรรมเดิม)
import sys

MARK = 'Stage ALERT-SETTINGS-DB'

FUNCS = r'''// ── Stage ALERT-SETTINGS-DB: ค่าแจ้งเตือนล่วงหน้าเก็บในฐานข้อมูล (app_alert_settings) ──
let _alertSrc='local';
async function _loadAlertSettingsDb(){
  if(typeof _shareRpc!=='function'||!curUser)return;
  const r=await _shareRpc('app_get_alert_settings',{});
  if(r.status==='ok'){
    const row=Array.isArray(r.data)?r.data[0]:r.data;
    if(row){['passport','visa','wp','next90','mou'].forEach(k=>{const v=parseInt(row[k]);if(v>0)settings[k]=v;});
      _alertSrc='db';try{localStorage.setItem('crm_settings',JSON.stringify(settings));}catch(_){}}
  }else if(r.status==='missing')_alertSrc='missing';
}
async function setSetting(k,v){
  const n=parseInt(v);
  if(!(n>=1&&n<=3650)){toast('กรุณาใส่จำนวนวัน 1–3650','err');renderSettings();return;}
  settings[k]=n;try{localStorage.setItem('crm_settings',JSON.stringify(settings));}catch(_){}
  const r=await _shareRpc('app_save_alert_settings',{p_passport:settings.passport,p_visa:settings.visa,p_wp:settings.wp,p_next90:settings.next90,p_mou:settings.mou});
  if(r.status==='ok'){_alertSrc='db';toast('บันทึกแล้ว — ใช้ร่วมกันทุกเครื่องและหน้าลิงก์ลูกค้า');}
  else if(r.status==='missing'){_alertSrc='missing';toast('บันทึกเฉพาะเครื่องนี้ — ยังไม่ได้รัน SQL ค่าตั้งเตือน','err');}
  else if(r.status==='unauthorized'){toast('เฉพาะผู้ดูแลระบบที่แก้ค่าเตือนได้','err');}
  else toast('บันทึกลงฐานข้อมูลไม่สำเร็จ (บันทึกเฉพาะเครื่องนี้)','err');
  renderSettings();
}'''

NOTE = ("'<div style=\"font-size:12px;margin:0 0 10px;padding:7px 11px;border-radius:8px;'+(_alertSrc==='db'"
        "?'background:#f0fdf4;color:#15803d\">✅ ค่านี้ใช้ร่วมกันทุกเครื่อง และใช้ในหน้าลิงก์ที่ส่งให้นายจ้าง'"
        ":'background:#fffbeb;color:#92400e\">⚠️ ตอนนี้ค่าเตือนบันทึกเฉพาะเครื่องนี้ (ยังเชื่อมฐานข้อมูลไม่ได้)')+'</div>'+")

def rep(s, old, new, path):
    n = s.count(old)
    if n != 1:
        sys.exit(f'{path}: anchor count {n} != 1 for: {old[:70]}')
    return s.replace(old, new)

def patch(path):
    s = open(path, 'rb').read().decode('utf-8')
    if MARK in s:
        print(path, ': already patched — skip'); return
    if 'Stage SHARE-001' not in s:
        sys.exit(f'{path}: needs Stage SHARE-001 (_shareRpc) first')
    nl = '\r\n' if '\r\n' in s else '\n'
    a = "settings=JSON.parse(localStorage.getItem('crm_settings')||'null')||settings;"
    s = rep(s, a, a + "try{await _loadAlertSettingsDb();}catch(_){} // " + MARK, path)
    a = "function setSetting(k,v){settings[k]=parseInt(v)||30;localStorage.setItem('crm_settings',JSON.stringify(settings));toast('บันทึกการตั้งค่าแล้ว');}"
    s = rep(s, a, FUNCS.replace('\n', nl), path)
    a = "document.getElementById('settingsContent').innerHTML=notifyHtml+readiness;"
    s = rep(s, a, "document.getElementById('settingsContent').innerHTML=" + NOTE + "notifyHtml+readiness;", path)
    open(path, 'wb').write(s.encode('utf-8'))
    print(path, ': patched')

for p in sys.argv[1:]:
    patch(p)

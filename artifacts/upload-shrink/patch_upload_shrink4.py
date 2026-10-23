# Stage UPLOAD-SHRINK-4 — แก้หน้าจอค้าง "กำลังบีบอัด PDF หน้า n/n"
#   สาเหตุจริง: showLoading() นับซ้อนทุกครั้งที่เรียก (_loading++) แต่ตอนบีบอัดเรียกทุกหน้า แล้ว hideLoading() แค่ครั้งเดียว
#               → ตัวนับค้าง > 0 หน้าจอโหลดไม่หาย (ทั้งที่บีบอัดเสร็จแล้ว)
#   แก้: เปิดหน้าจอโหลดครั้งเดียว · อัปเดตเลขหน้าด้วยการเปลี่ยนข้อความอย่างเดียว · ปิดใน finally
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage UPLOAD-SHRINK-4' in t: print('already'); sys.exit(0)
assert 'Stage UPLOAD-SHRINK-3' in t, 'run patch_upload_shrink3.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("""    if(file.size>=SHRINK_PDF_MIN){try{showLoading('กำลังบีบอัด PDF '+file.name+' …');}catch(_){}
      sh=await _shrinkTimeout(shrinkPdf(file,(i,n)=>{try{showLoading('กำลังบีบอัด PDF หน้า '+i+'/'+n+' …');}catch(_){}}),SHRINK_T_ALL+20000,_shrinkKillWorker).catch(()=>null);
      try{hideLoading();}catch(_){}}""","""    if(file.size>=SHRINK_PDF_MIN){
      // Stage UPLOAD-SHRINK-4: showLoading ครั้งเดียว (มันนับซ้อน) · เลขหน้าเปลี่ยนแค่ข้อความ · ปิดแน่นอนใน finally
      const _msg=m=>{try{const el=document.getElementById('loadingText');if(el)el.textContent=m;}catch(_){}};
      try{showLoading('กำลังบีบอัด PDF '+file.name+' …',0);}catch(_){}
      try{sh=await _shrinkTimeout(shrinkPdf(file,(i,n)=>_msg('กำลังบีบอัด PDF หน้า '+i+'/'+n+' …')),SHRINK_T_ALL+20000,_shrinkKillWorker).catch(()=>null);}
      finally{try{hideLoading();}catch(_){}}}""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

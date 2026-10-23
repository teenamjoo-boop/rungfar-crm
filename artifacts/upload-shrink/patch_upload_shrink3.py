# Stage UPLOAD-SHRINK-3 — แก้ PDF ค้างเมื่อเปิด CRM จากไฟล์ในเครื่อง (file://)
#   สาเหตุ: เปิดแบบ file:// แล้ว pdf.js ตรวจ origin ไม่ผ่าน → ไม่ใช้ Web Worker ("fake worker")
#           → ถอดรูปสแกนบน main thread · หน้าจอค้างและตัวจับเวลาทำงานไม่ได้
#   แก้: สร้าง Worker เองต่อไฟล์แล้วส่งให้ pdf.js · เสร็จ/หมดเวลา = ปิด worker ทิ้ง
#        จำกัดเวลา toBlob/รวมไฟล์ และครอบทั้งขั้นตอนอีกชั้น (ยังไงก็ไม่ค้าง → ใช้ไฟล์เดิม)
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage UPLOAD-SHRINK-3' in t: print('already'); sys.exit(0)
assert 'Stage UPLOAD-SHRINK-2' in t, 'run patch_upload_shrink2.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("""async function _shrinkPdfjs(){
  await _shrinkLoad(_SHRINK_LIB.pdfjs);const lib=window.pdfjsLib;
  if(lib&&!lib.__rfWorker){lib.__rfWorker=1;
    try{const tx=await (await fetch(_SHRINK_LIB.worker)).text();lib.GlobalWorkerOptions.workerSrc=URL.createObjectURL(new Blob([tx],{type:'text/javascript'}));}
    catch(_){lib.GlobalWorkerOptions.workerSrc=_SHRINK_LIB.worker;}}
  return lib;
}""","""async function _shrinkPdfjs(){
  await _shrinkLoad(_SHRINK_LIB.pdfjs);const lib=window.pdfjsLib;
  if(lib&&!lib.__rfWorker){lib.__rfWorker=1;
    try{const tx=await (await fetch(_SHRINK_LIB.worker)).text();lib.GlobalWorkerOptions.workerSrc=URL.createObjectURL(new Blob([tx],{type:'text/javascript'}));}
    catch(_){lib.GlobalWorkerOptions.workerSrc=_SHRINK_LIB.worker;}}
  return lib;
}
// Stage UPLOAD-SHRINK-3: Worker ใหม่ต่อไฟล์ (สร้างเอง → เปิดจาก file:// ก็ไม่ตกไปใช้ fake worker บนหน้าจอหลัก)
let _shrinkWk=null;
function _shrinkKillWorker(){try{_shrinkWk&&_shrinkWk.terminate();}catch(_){}_shrinkWk=null;}""")
rep("""    task=lib.getDocument({data:""","""    let pw;_shrinkKillWorker();try{_shrinkWk=new Worker(lib.GlobalWorkerOptions.workerSrc);pw=new lib.PDFWorker({port:_shrinkWk});}catch(e){console.warn('[upload-shrink] worker',e&&e.message);}
    task=lib.getDocument({worker:pw,data:""")
rep("""  finally{try{doc&&doc.destroy();}catch(_){}try{task&&task.destroy();}catch(_){}}""","""  finally{try{doc&&doc.destroy();}catch(_){}try{task&&task.destroy();}catch(_){}const w0=_shrinkWk;setTimeout(()=>{try{w0&&w0.terminate();}catch(_){}if(_shrinkWk===w0)_shrinkWk=null;},50);}""")
rep("""function _shrinkTimeout(pr,ms,onTo){let h;return Promise.race([pr,new Promise((_,rej)=>{h=setTimeout(()=>{try{onTo&&onTo();}catch(_){}rej(new Error('timeout'));},ms);})]).finally(()=>clearTimeout(h));}""","""function _shrinkTimeout(pr,ms,onTo){let h;return Promise.race([pr,new Promise((_,rej)=>{h=setTimeout(()=>{rej(new Error('timeout'));try{onTo&&onTo();}catch(_){}},ms);})]).finally(()=>clearTimeout(h));}""")
rep("""      const blob=await new Promise(r=>cv.toBlob(r,'image/jpeg',SHRINK_PDF_Q));""","""      const blob=await _shrinkTimeout(new Promise(r=>cv.toBlob(r,'image/jpeg',SHRINK_PDF_Q)),SHRINK_T_PAGE);""")
rep("""    const bytes=await out.save({useObjectStreams:true});""","""    const bytes=await _shrinkTimeout(out.save({useObjectStreams:true}),SHRINK_T_OPEN);""")
rep("""      sh=await shrinkPdf(file,(i,n)=>{try{showLoading('กำลังบีบอัด PDF หน้า '+i+'/'+n+' …');}catch(_){}});""","""      sh=await _shrinkTimeout(shrinkPdf(file,(i,n)=>{try{showLoading('กำลังบีบอัด PDF หน้า '+i+'/'+n+' …');}catch(_){}}),SHRINK_T_ALL+20000,_shrinkKillWorker).catch(()=>null);""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

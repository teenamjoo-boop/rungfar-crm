# Stage UPLOAD-SHRINK — บีบอัดไฟล์ก่อนอัปโหลดเข้า CRM (ยังคมชัด พิมพ์ได้ · สีเดิม ไม่แปลงขาวดำ)
#   รูปเอกสาร: ด้านยาว ≤2000px (≈170 dpi บน A4) JPEG 0.82 · ใหญ่เกิน 1.5MB ค่อยลดทีละขั้น
#   PDF ≥600KB: วาดทีละหน้าที่ 200 dpi (ด้านยาว ≤2400px) JPEG 0.8 รวมเป็น PDF ขนาดหน้าเดิม
#               ใช้ไฟล์ใหม่เฉพาะเมื่อเล็กลง ≥20% · อ่านไม่ได้/มีรหัส/เกิน 60 หน้า → ใช้ไฟล์เดิม
#   รับ PDF ต้นฉบับได้ถึง 30MB (ต้องเหลือ ≤10MB หลังบีบ) · ใช้กับ: เพิ่มเอกสารแรงงาน / คลังเอกสาร / อัปโหลดหลายไฟล์ / เอกสารนายจ้าง
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage UPLOAD-SHRINK' in t: print('already'); sys.exit(0)
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)

rep("const DOC_MAX_BYTES=1.5*1024*1024; // จำกัดต่อไฟล์หลังย่อ",
r"""const DOC_MAX_BYTES=1.5*1024*1024; // จำกัดต่อไฟล์หลังย่อ
// ── Stage UPLOAD-SHRINK: บีบอัดไฟล์ก่อนอัปโหลด — ยังคมชัด พิมพ์ได้ · สีเดิม (ไม่แปลงขาวดำ) ──
const SHRINK_IMG_PX=2000, SHRINK_IMG_Q=0.82;                  // รูปเอกสาร ≈170 dpi บน A4
const SHRINK_PDF_DPI=200, SHRINK_PDF_MAXPX=2400, SHRINK_PDF_Q=0.8;
const SHRINK_PDF_MIN=600*1024, SHRINK_PDF_MAXPAGES=60, SHRINK_PDF_RAW_MAX=30*1024*1024, PDF_MAX_BYTES_UP=10*1024*1024;
const _SHRINK_LIB={pdfjs:'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js',worker:'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js',pdflib:'https://cdnjs.cloudflare.com/ajax/libs/pdf-lib/1.17.1/pdf-lib.min.js'};
const _shrinkScripts={};
function _shrinkLoad(src){return _shrinkScripts[src]=_shrinkScripts[src]||new Promise((res,rej)=>{const s=document.createElement('script');s.src=src;s.onload=()=>res();s.onerror=()=>{delete _shrinkScripts[src];rej(new Error('load '+src));};document.head.appendChild(s);});}
async function _shrinkPdfjs(){
  await _shrinkLoad(_SHRINK_LIB.pdfjs);const lib=window.pdfjsLib;
  if(lib&&!lib.__rfWorker){lib.__rfWorker=1;
    try{const tx=await (await fetch(_SHRINK_LIB.worker)).text();lib.GlobalWorkerOptions.workerSrc=URL.createObjectURL(new Blob([tx],{type:'text/javascript'}));}
    catch(_){lib.GlobalWorkerOptions.workerSrc=_SHRINK_LIB.worker;}}
  return lib;
}
// PDF → วาดทีละหน้าเป็น JPEG แล้วรวมใหม่ · คืน {dataUrl,before,after,pages} หรือ null (= ใช้ไฟล์เดิม)
async function shrinkPdf(file,onPage){
  if(!file||file.size<SHRINK_PDF_MIN)return null;
  let doc=null;
  try{
    const lib=await _shrinkPdfjs();await _shrinkLoad(_SHRINK_LIB.pdflib);
    doc=await lib.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
    if(doc.numPages>SHRINK_PDF_MAXPAGES)return null;
    const out=await PDFLib.PDFDocument.create();
    for(let i=1;i<=doc.numPages;i++){
      if(onPage)onPage(i,doc.numPages);
      const pg=await doc.getPage(i);const v1=pg.getViewport({scale:1});
      let sc=SHRINK_PDF_DPI/72;const lng=Math.max(v1.width,v1.height)*sc;if(lng>SHRINK_PDF_MAXPX)sc*=SHRINK_PDF_MAXPX/lng;
      const vp=pg.getViewport({scale:sc});
      const cv=document.createElement('canvas');cv.width=Math.ceil(vp.width);cv.height=Math.ceil(vp.height);
      const ctx=cv.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,cv.width,cv.height);
      await pg.render({canvasContext:ctx,viewport:vp}).promise;
      const blob=await new Promise(r=>cv.toBlob(r,'image/jpeg',SHRINK_PDF_Q));
      if(!blob)throw new Error('canvas');
      const jpg=await out.embedJpg(new Uint8Array(await blob.arrayBuffer()));
      out.addPage([v1.width,v1.height]).drawImage(jpg,{x:0,y:0,width:v1.width,height:v1.height});
      cv.width=cv.height=0;pg.cleanup();
    }
    const bytes=await out.save({useObjectStreams:true});
    if(bytes.length>file.size*0.8)return null;   // เล็กลงไม่ถึง 20% → เก็บไฟล์เดิม (คมชัดที่สุด)
    return{dataUrl:await readAsDataURL(new Blob([bytes],{type:'application/pdf'})),before:file.size,after:bytes.length,pages:doc.numPages};
  }catch(e){console.warn('[upload-shrink] pdf skipped',e&&e.message);return null;}
  finally{try{doc&&doc.destroy();}catch(_){}}
}
// เตรียมไฟล์เอกสาร 1 ไฟล์ก่อนอัปโหลด → {data,type,isPdf,before,after} · โยน Error (ข้อความไทย) ถ้าใหญ่เกิน
async function prepDocUpload(file){
  const isPdf=file.type==='application/pdf'||/\.pdf$/i.test(file.name||'');
  if(file.type&&file.type.startsWith('image/')){
    let data=await compressImage(file,SHRINK_IMG_PX,SHRINK_IMG_Q);
    if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(file,1600,0.75);
    if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(file,1200,0.62);
    if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)throw new Error('รูป '+file.name+' ใหญ่เกิน 1.5MB หลังย่อ ลองถ่าย/สแกนใหม่');
    return{data,type:'image/jpeg',isPdf:false,before:file.size,after:approxBytesFromDataURL(data)};
  }
  if(isPdf){
    if(file.size>SHRINK_PDF_RAW_MAX)throw new Error('PDF '+file.name+' ใหญ่เกิน 30MB');
    let sh=null;
    if(file.size>=SHRINK_PDF_MIN){try{showLoading('กำลังบีบอัด PDF '+file.name+' …');}catch(_){}
      sh=await shrinkPdf(file,(i,n)=>{try{showLoading('กำลังบีบอัด PDF หน้า '+i+'/'+n+' …');}catch(_){}});
      try{hideLoading();}catch(_){}}
    if(sh)return{data:sh.dataUrl,type:'application/pdf',isPdf:true,before:sh.before,after:sh.after};
    if(file.size>PDF_MAX_BYTES_UP)throw new Error('PDF '+file.name+' ใหญ่เกิน 10MB และบีบอัดไม่ได้ กรุณาลดขนาดไฟล์');
    return{data:await readAsDataURL(file),type:'application/pdf',isPdf:true,before:file.size,after:file.size};
  }
  if(file.size>5*1024*1024)throw new Error('ไฟล์ '+file.name+' ใหญ่เกิน 5MB');
  return{data:await readAsDataURL(file),type:file.type||'application/octet-stream',isPdf:false,before:file.size,after:file.size};
}
const _shrinkNote=p=>p&&p.after<p.before*0.9?` (บีบอัด ${Math.round(p.before/1024)}KB → ${Math.round(p.after/1024)}KB)`:'';""")

# 1) เพิ่มเอกสารแรงงาน (หลายไฟล์ในหน้าลูกค้า)
rep("""      let dataUrl,ftype;
      const _isPdf=file.type==='application/pdf';
      if(file.type&&file.type.startsWith('image/')){
        dataUrl=await compressImage(file,1600,0.72);ftype='image/jpeg'; // เอกสาร: max 1600px, q0.72
      }else{
        const _rawLim=_isPdf?10*1024*1024:5*1024*1024;
        if(file.size>_rawLim){toast((_isPdf?'PDF':'ไฟล์')+' '+file.name+' ใหญ่เกิน '+(_isPdf?'10':'5')+'MB','err');continue;}
        dataUrl=await readAsDataURL(file);ftype=file.type||'application/octet-stream';
      }""","""      let dataUrl,ftype;
      const _isPdf=file.type==='application/pdf';
      // Stage UPLOAD-SHRINK
      let _pp;try{_pp=await prepDocUpload(file);}catch(er){toast(er&&er.message||('เพิ่มไฟล์ '+file.name+' ไม่สำเร็จ'),'err');continue;}
      dataUrl=_pp.data;ftype=_pp.type;if(_shrinkNote(_pp))toast('เพิ่ม '+file.name+_shrinkNote(_pp));""")
# 2) คลังเอกสาร (อัปโหลดทีละไฟล์)
rep("""    let dataUrl,ftype;
    const _isPdf=file.type==='application/pdf';
    if(file.type&&file.type.startsWith('image/')){
      dataUrl=await compressImage(file,1600,0.72);ftype='image/jpeg';
    }else{
      const _rawLim=_isPdf?10*1024*1024:5*1024*1024;
      if(file.size>_rawLim){toast((_isPdf?'PDF':'ไฟล์')+' '+file.name+' ใหญ่เกิน '+(_isPdf?'10':'5')+'MB','err');e.target.value='';return;}
      dataUrl=await readAsDataURL(file);ftype=file.type||'application/octet-stream';
    }""","""    let dataUrl,ftype;
    const _isPdf=file.type==='application/pdf';
    // Stage UPLOAD-SHRINK
    let _pp;try{_pp=await prepDocUpload(file);}catch(er){toast(er&&er.message||'อ่านไฟล์ไม่ได้','err');e.target.value='';return;}
    dataUrl=_pp.data;ftype=_pp.type;if(_shrinkNote(_pp))toast('พร้อมอัปโหลด'+_shrinkNote(_pp));""")
# 3) อัปโหลดหลายไฟล์ + เอกสารนายจ้าง
rep("""async function _bulkPrepare(file){
  const isPdf=file.type==='application/pdf';
  if(isPdf){if(file.size>10*1024*1024)throw new Error('PDF ใหญ่เกิน 10MB');return{data:await readAsDataURL(file),type:'application/pdf'};}
  let data=await compressImage(file,1600,0.72);
  if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)data=await compressImage(file,1200,0.6);
  if(approxBytesFromDataURL(data)>DOC_MAX_BYTES)throw new Error('รูปใหญ่เกิน 1.5MB หลังย่อ');
  return{data,type:'image/jpeg'};}""","""async function _bulkPrepare(file){   // Stage UPLOAD-SHRINK
  const p=await prepDocUpload(file);return{data:p.data,type:p.type,before:p.before,after:p.after};}""")
# 4) แบบฟอร์มเก่า (docFiles)
rep("""function handleDoc(e,k){const f=e.target.files[0];if(!f)return;if(f.size>5*1024*1024){toast('ไฟล์ใหญ่เกิน 5MB','err');return;}const r=new FileReader();r.onload=ev=>{docFiles[k]={data:ev.target.result,name:f.name,type:f.type};renderDocGrid();};r.readAsDataURL(f);}""",
"""async function handleDoc(e,k){const f=e.target.files[0];if(!f)return;   // Stage UPLOAD-SHRINK
  try{const p=await prepDocUpload(f);docFiles[k]={data:p.data,name:f.name,type:p.type};renderDocGrid();}catch(er){toast(er&&er.message||'เพิ่มไฟล์ไม่สำเร็จ','err');}}""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

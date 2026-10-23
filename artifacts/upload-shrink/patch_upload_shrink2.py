# Stage UPLOAD-SHRINK-2 — กัน PDF ค้างตอนบีบอัด
#   * จำกัดเวลา: เปิดไฟล์ ≤20 วิ · ต่อหน้า ≤25 วิ · ทั้งไฟล์ ≤120 วิ → เกินเวลา = ยกเลิกแล้วใช้ไฟล์เดิม (ถ้า ≤10MB)
#   * ให้ pdf.js มีข้อมูลฟอนต์/CMap (เอกสารที่มีตัวหนังสือแบบไม่ฝังฟอนต์) · พักให้หน้าจออัปเดตระหว่างหน้า
#   * แจ้งผลให้รู้: บีบไม่ได้/เกินเวลา → "อัปโหลดไฟล์เดิม"
import sys
p=sys.argv[1]; t=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in t
if crlf: t=t.replace('\r\n','\n')
if 'Stage UPLOAD-SHRINK-2' in t: print('already'); sys.exit(0)
assert 'Stage UPLOAD-SHRINK' in t, 'run patch_upload_shrink.py first'
def rep(a,b):
    global t
    assert t.count(a)==1,(a[:80],t.count(a)); t=t.replace(a,b)
rep("""const _shrinkScripts={};""","""const _shrinkScripts={};
// Stage UPLOAD-SHRINK-2: จำกัดเวลา (กันค้าง)
const SHRINK_T_OPEN=20000, SHRINK_T_PAGE=25000, SHRINK_T_ALL=120000;
const _shrinkCdn='https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/';
function _shrinkTimeout(pr,ms,onTo){let h;return Promise.race([pr,new Promise((_,rej)=>{h=setTimeout(()=>{try{onTo&&onTo();}catch(_){}rej(new Error('timeout'));},ms);})]).finally(()=>clearTimeout(h));}""")
rep("""async function shrinkPdf(file,onPage){
  if(!file||file.size<SHRINK_PDF_MIN)return null;
  let doc=null;
  try{
    const lib=await _shrinkPdfjs();await _shrinkLoad(_SHRINK_LIB.pdflib);
    doc=await lib.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
    if(doc.numPages>SHRINK_PDF_MAXPAGES)return null;""","""async function shrinkPdf(file,onPage){
  if(!file||file.size<SHRINK_PDF_MIN)return null;
  let doc=null,task=null;const t0=Date.now();
  try{
    const lib=await _shrinkTimeout(_shrinkPdfjs(),SHRINK_T_OPEN);await _shrinkTimeout(_shrinkLoad(_SHRINK_LIB.pdflib),SHRINK_T_OPEN);
    task=lib.getDocument({data:new Uint8Array(await file.arrayBuffer()),cMapUrl:_shrinkCdn+'cmaps/',cMapPacked:true,standardFontDataUrl:_shrinkCdn+'standard_fonts/'});
    doc=await _shrinkTimeout(task.promise,SHRINK_T_OPEN,()=>task.destroy());
    if(doc.numPages>SHRINK_PDF_MAXPAGES)return null;""")
rep("""      if(onPage)onPage(i,doc.numPages);
      const pg=await doc.getPage(i);const v1=pg.getViewport({scale:1});""","""      if(onPage)onPage(i,doc.numPages);
      await new Promise(r=>setTimeout(r,0));   // ให้หน้าจออัปเดตข้อความ
      if(Date.now()-t0>SHRINK_T_ALL)throw new Error('timeout');
      const pg=await _shrinkTimeout(doc.getPage(i),SHRINK_T_PAGE);const v1=pg.getViewport({scale:1});""")
rep("""      await pg.render({canvasContext:ctx,viewport:vp}).promise;""","""      const rt=pg.render({canvasContext:ctx,viewport:vp});
      await _shrinkTimeout(rt.promise,SHRINK_T_PAGE,()=>rt.cancel());""")
rep("""  }catch(e){console.warn('[upload-shrink] pdf skipped',e&&e.message);return null;}
  finally{try{doc&&doc.destroy();}catch(_){}}""","""  }catch(e){console.warn('[upload-shrink] pdf skipped',e&&e.message);try{toast((e&&e.message==='timeout'?'บีบอัด PDF นานเกินไป':'บีบอัด PDF ไม่ได้')+' — ใช้ไฟล์เดิม','err');}catch(_){}return null;}
  finally{try{doc&&doc.destroy();}catch(_){}try{task&&task.destroy();}catch(_){}}""")
if crlf: t=t.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(t); print('patched',p,len(t),'crlf' if crlf else 'lf')

# แยกรูป base64 ในเว็บบริษัทออกเป็นไฟล์ img/ (ไบต์เดิมทุกไฟล์ ไม่บีบอัด) + lazy-load รูปที่อยู่ล่าง ๆ
import re,base64,hashlib,os,sys
src,outdir=sys.argv[1],sys.argv[2]
s=open(src,encoding='utf-8').read()
os.makedirs(os.path.join(outdir,'img'),exist_ok=True)
seen={}; n=[0]
def rep(m):
    ext={'webp':'webp','png':'png','jpeg':'jpg','jpg':'jpg','svg+xml':'svg','gif':'gif'}[m.group(1)]
    b=base64.b64decode(m.group(2)); h=hashlib.sha1(b).hexdigest()[:10]
    if h not in seen:
        n[0]+=1; name='img/%02d-%s.%s'%(n[0],h,ext); seen[h]=name
        open(os.path.join(outdir,name),'wb').write(b)
    return '/'+seen[h]
s=re.sub(r'data:image/([a-z+]+);base64,([A-Za-z0-9+/=]+)',rep,s)
# lazy: ทุก <img ยกเว้นโลโก้หัวเว็บและสไลด์แรก
cnt=[0]
def lazy(m):
    cnt[0]+=1
    return m.group(0) if cnt[0]<=2 else '<img loading="lazy" decoding="async" '
s=re.sub(r'<img ',lazy,s)
logo=seen[sorted(seen)[0]] if False else None
# favicon = โลโก้หัวเว็บ
first=re.search(r'class="brand"[^>]*><img src="([^"]+)"',s).group(1)
s=s.replace('</title>','</title>\n<link rel="icon" href="%s" />'%first,1)
open(os.path.join(outdir,'index.html'),'w',encoding='utf-8').write(s)
print('images',len(seen),'html',len(s.encode()),'lazy',cnt[0]-2)

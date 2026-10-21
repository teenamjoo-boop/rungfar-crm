import sys
D=sys.argv[1]
t=open(D+'/parcel.tpl.html',encoding='utf-8').read(); logo=open(D+'/logo.txt').read().strip()
def mk(fn,banner,stg):
    return t.replace('__LOGO__',logo).replace('__FN_URL__',fn).replace('__STAGING_BANNER__',banner).replace('__IS_STG__','true' if stg else 'false')
prod=mk('https://magwqolbjmwymqxelizl.supabase.co/functions/v1/parcel-api','',False)
stg=mk('https://bzwtknqvhvdmatangzqf.supabase.co/functions/v1/parcel-api','<div style="background:#B91C1C;color:#fff;text-align:center;font-weight:700;font-size:12px;padding:4px">STAGING — ข้อมูลทดสอบ</div>',True)
assert 'bzwtknqvhvdmatangzqf' not in prod and 'magwqolbjmwymqxelizl' not in stg and '__LOGO__' not in prod and '__IS_STG__' not in stg
open(D+'/parcel.html','w',encoding='utf-8').write(prod); open(D+'/parcel-staging.html','w',encoding='utf-8').write(stg)
print(len(prod),len(stg))

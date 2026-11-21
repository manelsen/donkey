"""List modules under src/ unreachable from src/donkey.nim. Run from the repo root."""
import os,re,sys
root='src'
mods={}
for d,_,fs in os.walk(root):
    for f in fs:
        if f.endswith('.nim'): mods[os.path.join(d,f)]=open(os.path.join(d,f)).read()
imp=re.compile(r'^[ \t]*(?:import|from|include)[ \t]+(.+?)(?:[ \t]+import\b.*)?$',re.M)
def targets(path,src):
    out=set(); base=os.path.dirname(path)
    for m in imp.finditer(src):
        spec=m.group(1).split('#')[0]
        # expand a/[b,c]
        parts=[]
        for item in re.split(r',(?![^\[]*\])',spec):
            item=item.strip().split(' as ')[0].strip()
            mm=re.match(r'(.*)/\[(.*)\]',item)
            if mm:
                for x in mm.group(2).split(','): parts.append(mm.group(1)+'/'+x.strip())
            else: parts.append(item)
        for p in parts:
            p=p.strip().strip('"')
            if p.startswith('std/') or not p: continue
            cands=[os.path.normpath(os.path.join(base,p+'.nim')), os.path.normpath(os.path.join('src',p+'.nim'))]
            for c in cands:
                if c in mods: out.add(c)
    return out
edges={p:targets(p,s) for p,s in mods.items()}
seen=set(); stack=['src/donkey.nim']+[p for p in mods if os.path.basename(p) in ('donkey_ctl.nim',)]
# also any file with isMainModule entry outside src/donkey.nim
while stack:
    p=stack.pop()
    if p in seen: continue
    seen.add(p); stack+=list(edges.get(p,()))
dead=sorted(p for p in mods if p not in seen)
tot=sum(mods[p].count('\n') for p in dead)
print(len(dead),'unreachable modules,',tot,'lines')
for p in dead: print(mods[p].count('\n'),p)

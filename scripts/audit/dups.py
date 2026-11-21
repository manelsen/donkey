"""Group files under src/ that share duplicated 8-line windows (normalized). Run from the repo root."""
import os,re,collections
W=8
blocks=collections.defaultdict(list)
for d,_,fs in os.walk('src'):
    for f in fs:
        if not f.endswith('.nim'): continue
        p=os.path.join(d,f)
        lines=open(p).read().split('\n')
        norm=[]
        for i,l in enumerate(lines):
            t=l.strip()
            if not t or t.startswith('#') or t.startswith('##') or t.startswith('import') : continue
            t=re.sub(r'"[^"]*"','S',t); t=re.sub(r'\b\d+\b','N',t)
            norm.append((i+1,t))
        for k in range(len(norm)-W+1):
            win=norm[k:k+W]
            key='\n'.join(x[1] for x in win)
            if len(key)<200: continue
            blocks[key].append((p,win[0][0]))
groups=[]
for key,locs in blocks.items():
    files={p for p,_ in locs}
    if len(locs)>1: groups.append((len(locs),locs,key))
# collapse overlapping windows: keep by file-pair first line
seen=set(); out=[]
for n,locs,key in sorted(groups,key=lambda g:-g[0]):
    sig=tuple(sorted((p,ln//15) for p,ln in locs))
    if sig in seen: continue
    seen.add(sig); out.append((n,locs,key))
pairs=collections.Counter()
for n,locs,key in out:
    fs=tuple(sorted({p for p,_ in locs}))
    pairs[fs]+=1
print("file groups sharing duplicated 8-line windows (count of distinct windows):")
for fs,c in pairs.most_common(35): print(c, ' | '.join(x.replace('src/donkey/','') for x in fs))

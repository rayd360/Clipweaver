#!/usr/bin/env python3
"""Validate ClipWeaver edit.json against its review manifest. Standard library only."""
import json, math, pathlib, sys

RATES = {'source','24000/1001','23.976','24','25','30000/1001','29.97','30','48','50','60000/1001','59.94','60','120000/1001','120'}
def finite(x): return isinstance(x,(int,float)) and not isinstance(x,bool) and math.isfinite(x)
def rate(s):
    a = str(s).split('/')
    return float(a[0]) / (float(a[1]) if len(a)==2 else 1)
def validate(edit, manifest):
    if isinstance(edit,list):
        errors=[]
        if len(edit)!=3: errors.append('Return exactly three creative choices')
        titles=[e.get('title') for e in edit if isinstance(e,dict)]
        if len(set(titles))!=3: errors.append('Use three distinct titles')
        for i,e in enumerate(edit):
            errors += [f'Choice {i+1}: {msg}' for msg in validate(e,manifest)]
            if isinstance(e,dict) and (e.get('aspect','source')!='source' or e.get('fps','source')!='source' or e.get('music') is not None): errors.append('New choices must use source shape and fps and omit music')
        return errors
    errors=[]
    def check(ok,message):
        if not ok: errors.append(message)
    def keys(obj,allowed,label):
        check(isinstance(obj,dict),f'{label} must be an object')
        if isinstance(obj,dict): check(not set(obj)-set(allowed),f'{label} has unknown fields: {sorted(set(obj)-set(allowed))}')
    keys(edit,['schema_version','project_id','title','aspect','fps','clips','music','notes','overlays','end_card','caption_styles','captions','logo_placements','transition_style'],'edit')
    if not isinstance(edit,dict): return errors
    check(type(edit.get('schema_version')) is int and edit['schema_version'] in (1,2,3,4),'schema_version must be 1, 2, 3 or 4')
    check(edit.get('project_id')==manifest.get('project_id'),'project_id does not match manifest')
    check(isinstance(edit.get('title'),str) and 1<=len(edit['title'].strip())<=200,'title must contain 1–200 characters')
    check(edit.get('aspect','source') in ['source','portrait','landscape','square'],'invalid aspect')
    check(isinstance(edit.get('fps','source'),str) and edit.get('fps','source') in RATES,'invalid output fps; use source')
    if 'notes' in edit: check(isinstance(edit['notes'],str),'notes must be a string')
    clips=edit.get('clips',[])
    check(isinstance(clips,list) and 1<=len(clips)<=100,'clips must contain 1–100 selections')
    if not isinstance(clips,list): return errors
    if edit.get('schema_version')==4:
        kind=edit.get('transition_style');check(kind in ['cut','cross_dissolve'],'transition_style must be cut or cross_dissolve')
        for c in clips[1:]:
            if not isinstance(c,dict):continue
            t=c.get('transition',0)
            check(finite(t) and (t==0 if kind=='cut' else .5<=t<=.8),'All clips after first must follow one transition style; dissolves must be .5–.8 seconds')
    if manifest.get('captions_enabled') is False:
        check(not edit.get('captions') and not edit.get('caption_styles') and not edit.get('overlays'),'Captions are disabled for this project; omit captions, styles and overlays')
    sources={s['id']:s for s in manifest['sources']}
    duration=0
    for i,c in enumerate(clips):
        label=f'clip {i+1}'
        keys(c,['source_id','start','end','volume','transition','framing','focus_x','focus_y','note'],label)
        if not isinstance(c,dict): continue
        sid=c.get('source_id'); s=sources.get(sid) if isinstance(sid,str) else None
        check(s is not None,f'{label}: unknown source_id')
        start,end=c.get('start'),c.get('end')
        valid=finite(start) and finite(end) and 0<=start<end
        check(valid,f'{label}: invalid start/end')
        if valid:
            if isinstance(sid,str) and sid.startswith('COMBINED_'):
                for part in manifest.get('combined_parts',[])[:-1]:
                    boundary=part.get('end')
                    if finite(boundary):check(not (start<boundary-.000001 and end>boundary+.000001),f'{label}: crosses original-video boundary at {boundary}; split into explicit selections')
            length=end-start
            duration+=length
            if s:
                check(end<=s['duration']+0.002,f'{label}: end exceeds source duration')
                check(length>=1/rate(s['original_fps']),f'{label}: shorter than one original frame')
            t=c.get('transition',0); nxt=clips[i+1].get('transition',0) if i+1<len(clips) and isinstance(clips[i+1],dict) else 0
            if finite(t) and finite(nxt): check(t+nxt<length,f'{label}: crossfades consume entire selection')
        t=c.get('transition',0)
        check(finite(t) and 0<=t<=2 and (i>0 or t==0),f'{label}: invalid transition')
        if i>0 and finite(t): duration-=t
        for field,default,hi in [('volume',1,2),('focus_x',0.5,1),('focus_y',0.5,1)]:
            value=c.get(field,default);check(finite(value) and 0<=value<=hi,f'{label}: invalid {field}')
        check(c.get('framing','fit') in ['fit','fill'],f'{label}: invalid framing')
        if 'note' in c: check(isinstance(c['note'],str),f'{label}: note must be a string')
    card=edit.get('end_card')
    if card is not None:
        keys(card,['duration','text','filename','background','transition'],'end_card')
        if isinstance(card,dict):
            d=card.get('duration');check(finite(d) and .25<=d<=15,'end_card duration must be .25–15 seconds')
            t=card.get('transition',0)
            check(finite(t) and finite(d) and 0<=t<d and t<=2,'invalid end-card transition')
            if edit.get('schema_version')==4:check(finite(t) and (t==0 if edit.get('transition_style')=='cut' else .5<=t<=.8),'end card must follow uniform transition style')
            if finite(d) and finite(t):duration+=d-t
            if clips and isinstance(clips[-1],dict) and finite(t):
                last=clips[-1];a,b=last.get('start'),last.get('end');incoming=last.get('transition',0)
                if all(finite(v) for v in [a,b,incoming]):check(incoming+t<b-a,'last clip too short for end-card dissolve')
    overlays=edit.get('overlays',[])
    check(isinstance(overlays,list) and len(overlays)<=100,'overlays must be an array of at most 100 entries')
    if 'overlays' in edit or 'end_card' in edit:check(edit.get('schema_version') in (2,3,4),'overlays/end_card require schema_version 2 or later')
    def basename(name):return isinstance(name,str) and 0<len(name)<=200 and name not in ['.','..'] and '/' not in name and '\\' not in name and not any(ord(c)<32 or ord(c)==127 for c in name)
    def color(value):
        if not isinstance(value,str) or len(value) not in (7,9) or not value.startswith('#'):return False
        try:int(value[1:],16);return True
        except ValueError:return False
    visual=list(overlays) if isinstance(overlays,list) else []
    if isinstance(card,dict):visual.append(card)
    for o in visual:
        if not isinstance(o,dict):check(False,'overlay must be an object');continue
        is_card=o is card
        if not is_card:
            keys(o,['start','end','text','filename','x','y','width','height','font_size','color','background','alignment'],'overlay')
            start,end=o.get('start'),o.get('end');check(finite(start) and finite(end) and 0<=start<end<=duration+.002,'overlay times must fit finished video')
        check(('text' in o) != ('filename' in o),'visual needs exactly one of text or filename')
        if 'text' in o:check(isinstance(o['text'],str) and 1<=len(o['text'].strip())<=500,'text needs 1–500 characters')
        if 'filename' in o:check(basename(o['filename']) and pathlib.Path(o['filename']).suffix.lower() in ['.png','.jpg','.jpeg'],'invalid image filename')
        x,y,w,h=[o.get(k,d) for k,d in [('x',.1),('y',.72),('width',.8),('height',.18)]]
        check(all(finite(v) for v in [x,y,w,h]) and x>=0 and y>=0 and w>0 and h>0 and x+w<=1.00001 and y+h<=1.00001,'overlay rectangle must fit frame')
        fs=o.get('font_size',.05);check(finite(fs) and .015<=fs<=.15,'font_size must be .015–.15')
        check(o.get('alignment','center') in ['left','center','right'],'invalid alignment')
        for key in ['color','background']:
            if key in o:check(color(o[key]),'colors must be #RRGGBB or #RRGGBBAA')
    check(0<duration<=3600,'final runtime must be positive and at most one hour')
    m=edit.get('music')
    if m is not None:
        keys(m,['filename','start','volume','fade_in','fade_out','duck','loop'],'music')
        if isinstance(m,dict):
            name=m.get('filename');check(basename(name),'music needs a basename, not a path')
            for field,default,upper in [('start',0,float('inf')),('volume',0.2,2),('fade_in',min(0.5,duration),duration),('fade_out',min(1,duration),duration)]:
                v=m.get(field,default);check(finite(v) and 0<=v<=upper,f'music: invalid {field}')
            for field in ['duck','loop']:
                if field in m:check(isinstance(m[field],bool),f'music: {field} must be boolean')
    # Native rendering also checks measured glyph bounds and line wrapping.
    if any(k in edit for k in ['caption_styles','captions','logo_placements']):
        check(edit.get('schema_version') in (3,4),'captions/logo require schema_version 3 or later')
    def number(v,lo,hi):return finite(v) and lo<=v<=hi
    def safe(o,defaults):
        x,y,w,h=[o.get(k,d) for k,d in zip(['x','y','width','height'],defaults)]
        return all(finite(v) for v in [x,y,w,h]) and x>=.08-1e-6 and y>=.12-1e-6 and w>0 and h>0 and x+w<=.86+1e-6 and y+h<=.80+1e-6
    def entrance(e,visible):
        keys(e,['type','direction','duration','distance'],'entrance')
        if not isinstance(e,dict):return
        t=e.get('type','none');check(t in ['none','fade','slide'],'invalid entrance type')
        if t=='none':check(not any(k in e for k in ['direction','duration','distance']),'none cannot have motion fields')
        else:
            check(number(e.get('duration',.25),.05,min(.8,visible)),'invalid entrance duration')
            if t=='fade':check(not any(k in e for k in ['direction','distance']),'fade cannot have slide fields')
            if t=='slide':
                check(e.get('direction','up') in ['left','right','up','down'],'invalid slide direction')
                check(number(e.get('distance',.025),.005,.08),'invalid slide distance')
    styles=edit.get('caption_styles',{})
    check(isinstance(styles,dict) and len(styles)<=12,'at most 12 caption styles')
    if not isinstance(styles,dict):styles={}
    for name,st in styles.items():
        check(1<=len(name)<=40,'invalid style name');keys(st,['font_size','emphasis_scale','emphasis_color','entrance','contrast_backing'],'caption style')
        if not isinstance(st,dict):continue
        fs,scale=st.get('font_size',.052),st.get('emphasis_scale',1.45)
        check(number(fs,.018,.07) and number(scale,1.1,1.6) and fs*scale<=.10,'invalid caption style size')
        check(st.get('emphasis_color','#363B43').upper() in ['#30343B','#363B43','#464B52','#E8E9EC'],'invalid charcoal tint')
        if 'contrast_backing' in st:check(isinstance(st['contrast_backing'],bool),'contrast_backing must be boolean')
        if 'entrance' in st:entrance(st['entrance'],3600)
    captions=edit.get('captions',[]);check(isinstance(captions,list) and len(captions)<=80,'at most 80 captions')
    events=[];spans=[];total=0
    for c in captions if isinstance(captions,list) else []:
        keys(c,['style','x','y','width','height','alignment','words'],'caption')
        if not isinstance(c,dict):continue
        check('style' not in c or c['style'] in styles,'unknown caption style')
        st=styles.get(c.get('style'),{});st=st if isinstance(st,dict) else {}
        check(safe(c,[.1,.36,.76,.32]),'caption outside safe area')
        check(c.get('alignment','center') in ['left','center','right'],'invalid caption alignment')
        words=c.get('words',[]);check(isinstance(words,list) and 1<=len(words)<=60,'caption needs 1–60 segments')
        for w in words if isinstance(words,list) else []:
            total+=1;keys(w,['text','start','end','style','font_size','x','y','line_break_before','entrance'],'word')
            if not isinstance(w,dict):continue
            text=w.get('text');check(isinstance(text,str) and 1<=len(text.strip()) and len(text)<=80 and '\n' not in text and '\r' not in text,'invalid word text')
            a,b=w.get('start'),w.get('end');valid=finite(a) and finite(b) and 0<=a<b<=duration+.002
            check(valid,'word times must fit finished video')
            if valid:events.extend([(a,1),(b,-1)]);spans.append((a,b))
            kind=w.get('style','normal');check(kind in ['normal','emphasis'],'invalid word style')
            fs=st.get('font_size',.052);scale=st.get('emphasis_scale',1.45)
            if finite(fs) and finite(scale):
                size=w.get('font_size',fs*(scale if kind=='emphasis' else 1))
                check(number(size,.018,.10) and (kind!='emphasis' or size>fs),'invalid word font size')
            check(('x' in w)==('y' in w),'word placement needs x and y')
            if 'x' in w:check(number(w['x'],.08,.859999) and number(w.get('y'),.12,.799999),'unsafe word position')
            if 'line_break_before' in w:check(isinstance(w['line_break_before'],bool),'line_break_before must be boolean')
            entrance(w.get('entrance',st.get('entrance',{})),b-a if valid else 0)
    check(total<=400,'at most 400 caption segments')
    active=0
    for _,delta in sorted(events):active+=delta;check(active<=80,'at most 80 simultaneously visible segments')
    logos=edit.get('logo_placements',[]);check(isinstance(logos,list) and len(logos)<=30,'at most 30 logo placements')
    if logos:check(bool(manifest.get('project_logo')),'logo placements require the requested project_logo in the review manifest')
    for l in logos if isinstance(logos,list) else []:
        keys(l,['start','end','x','y','width','height','opacity'],'logo placement')
        if not isinstance(l,dict):continue
        a,b=l.get('start'),l.get('end');valid=finite(a) and finite(b) and 0<=a<b<=duration+.002
        check(valid,'logo times must fit finished video')
        if valid:spans.append((a,b))
        check(safe(l,[None]*4) and number(l.get('opacity',1),0,1),'invalid logo position or opacity')
    if spans:check(max(b for a,b in spans)-min(a for a,b in spans)<=600,'caption/logo span limited to ten minutes')
    return errors

if __name__=='__main__':
    try:
        if len(sys.argv)!=3: raise ValueError('Usage: validate_edit.py edit.json manifest.json')
        edit=json.loads(pathlib.Path(sys.argv[1]).read_text());manifest=json.loads(pathlib.Path(sys.argv[2]).read_text())
        errors=validate(edit,manifest)
        if errors:
            print('\n'.join('ERROR: '+e for e in errors));sys.exit(1)
        for choice in edit if isinstance(edit,list) else [edit]:
            duration=sum(c['end']-c['start'] for c in choice['clips'])-sum(c.get('transition',0) for c in choice['clips'][1:])+(choice.get('end_card') or {}).get('duration',0)-(choice.get('end_card') or {}).get('transition',0)
            print(f'Valid ClipWeaver edit: {choice["title"]}, {duration:.3f}s')
    except (OSError,ValueError,KeyError,TypeError,ZeroDivisionError) as e:
        print(f'ERROR: {e}',file=sys.stderr);sys.exit(1)

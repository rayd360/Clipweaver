#!/usr/bin/env python3
import array,json,math,pathlib,struct,subprocess,sys
base=pathlib.Path(sys.argv[1]);r=json.loads((base/'realistic-results.json').read_text())
ff='/Users/jonathandouglas/Applications/ClipWeaver.app/Contents/Resources/bin/ffmpeg'
def run(args): return subprocess.check_output([ff,'-hide_banner','-loglevel','error',*args])
def pixels(file,t): return run(['-ss',str(t),'-i',str(file),'-frames:v','1','-vf','scale=160:90','-pix_fmt','gray','-f','rawvideo','pipe:1'])
def rms(file,t):
 raw=run(['-ss',str(t),'-i',str(file),'-t','0.03','-vn','-ar','48000','-ac','1','-f','f32le','pipe:1']);a=array.array('f');a.frombytes(raw)
 assert a, 'No audio samples'
 return math.sqrt(sum(v*v for v in a)/len(a))
source=base/'Original-60s-1080p-24fps.mp4';social=pathlib.Path(r['social_path']);website=pathlib.Path(r['website_path']);review=pathlib.Path(r['review_path'])
checks=[]
for dest,origin in [(0.5,4.75),(8.5,20.75),(16.5,45.75)]:
 a=pixels(social,dest);b=pixels(source,origin);assert len(a)==len(b)==14400
 error=sum(abs(x-y) for x,y in zip(a,b))/len(a)
 assert error<8, f'Incorrect source timestamp: output {dest}, source {origin}, error {error}'
 checks.append({'output_time':dest,'source_time':origin,'mean_pixel_error':round(error,3)})
raw=run(['-i',str(social),'-frames:v','24','-an','-vf','scale=160:90','-f','framemd5','pipe:1']).decode()
hashes=[line.split(',')[-1].strip() for line in raw.splitlines() if not line.startswith('#')]
assert len(hashes)==24 and len(set(hashes))==24,'Output repeats frames as an 8 fps source would'
for f in [social,website]:
 for pulse,silent in [(0.78,0.25),(8.78,8.25),(16.78,16.25)]:
  on,off=rms(f,pulse),rms(f,silent)
  assert on>0.08 and off<0.003,f'Audio cut timing incorrect for {f.name}: {on}, {off}'
assert rms(review,0.03)>0.08 and rms(review,0.4)<0.003,'Review audio shifted'
boxes=[]
with website.open('rb') as f:
 while True:
  header=f.read(8)
  if len(header)<8:break
  size,kind=struct.unpack('>I4s',header);head=8
  if size==1:size=struct.unpack('>Q',f.read(8))[0];head=16
  boxes.append(kind.decode('ascii'))
  if size==0:break
  f.seek(size-head,1)
assert boxes.index('moov')<boxes.index('mdat'),'Website MP4 is not fast-start'
subprocess.run([sys.executable,'/Users/jonathandouglas/.codex/skills/clipweaver-editor/scripts/validate_edit.py',str(base/'edit.json'),str(base/'For AI/manifest.json')],check=True)
result={'passed':True,'source_frame_comparisons':checks,'distinct_frames_in_first_second':len(set(hashes)),'audio_pulse_alignment':'passed in review, social, and website outputs','website_fast_start':True}
(base/'independent-verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))

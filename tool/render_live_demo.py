"""Render the three local Android recordings into the captioned 1.75x demo. See docs/DEMO.md."""
from pathlib import Path
import subprocess,re,json
root=Path.cwd();work=root/'build/live_demo';ff=next((root/'.venv/Lib/site-packages/imageio_ffmpeg/binaries').glob('ffmpeg*.exe'));names=['01-facebook-final','02-playlist-good','03-history-settings'];dur=[]
for n in names:
 r=subprocess.run([str(ff),'-hide_banner','-i',str(work/(n+'.mp4'))],capture_output=True,text=True,errors='replace');m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',r.stderr);assert m,(n,r.stderr);dur.append(int(m[1])*3600+int(m[2])*60+float(m[3]))
dur[0]=min(dur[0],100);speed=1.75;offsets=[0,dur[0]/speed,(dur[0]+dur[1])/speed];total=sum(dur)/speed
ass='''[Script Info]\nScriptType: v4.00+\nPlayResX: 720\nPlayResY: 1280\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\nStyle: Main,Tajawal,22,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,2,15,15,15,1\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'''
def stamp(t):return f'{int(t)//3600}:{int(t)//60%60:02}:{t%60:05.2f}'
# Arabic strings read from a UTF-8 source file rather than legacy shell stdin.
labels=json.loads((root/'docs/live-captions.json').read_text(encoding='utf-8'))
for i,label in enumerate(labels['chapters']):
 end=offsets[i+1] if i+1<len(offsets) else total
 ass+=f'Dialogue: 0,{stamp(offsets[i])},{stamp(end)},Main,,0,0,0,,{{\\an2\\pos(360,1260)}}{label}\n'
ass+=f'Dialogue: 0,0:00:00.00,{stamp(total)},Main,,0,0,0,,{{\\an8\\pos(360,4)}}'+labels['banner']+'\n'
(work/'live.ass').write_text(ass,encoding='utf-8')
args=[str(ff),'-hide_banner','-loglevel','error','-y']
for n in names:args+=['-i',str(work/(n+'.mp4'))]
filters=';'.join(f'[{i}:v]fps=25,tpad=stop_mode=clone:stop_duration=60,trim=duration={d},setpts=PTS-STARTPTS[v{i}]' for i,d in enumerate(dur))
filters+=';[v0][v1][v2]concat=n=3:v=1:a=0,setpts=PTS/1.75,fps=25,drawbox=x=0:y=0:w=iw:h=36:color=0x0b1020:t=fill,drawbox=x=0:y=1210:w=iw:h=70:color=0x0b1020:t=fill,ass=build/live_demo/live.ass:fontsdir=assets/fonts[out]'
args+=['-filter_complex',filters,'-map','[out]','-c:v','libx264','-preset','fast','-crf','24','-pix_fmt','yuv420p','-movflags','+faststart','-metadata','title=Nazzelha 1.1.3 - live Android 7 demo - 1.75x',str(root/'docs/media/Nazzelha-Live-Demo-Android.mp4')]
subprocess.run(args,check=True)
(work/'live-timing.json').write_text(json.dumps({'seconds':total,'speed':speed,'chapter_start_seconds':offsets,'raw_source_seconds':dur},indent=2))
print(json.dumps({'seconds':round(total,2),'speed':speed,'chapters':offsets,'bytes':(root/'docs/media/Nazzelha-Live-Demo-Android.mp4').stat().st_size}))

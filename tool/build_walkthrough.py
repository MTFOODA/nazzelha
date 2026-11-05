"""Build the Arabic annotated guide and captioned walkthrough from UI captures.

This renders documentation, not a live screen recording. Requires Pillow and
FFmpeg with libass. Existing captures live in docs/media; no app state changes.
"""
import argparse
import html
import json
import os
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
MEDIA = DOCS / 'media'
WORK = ROOT / 'build/walkthrough'


def render_guide(data):
    parts = []
    for section in data['sections']:
        pins, labels = [], []
        for i, item in enumerate(section['controls'], 1):
            x, y, title, detail = item
            ident = f"{section['id']}-{i}"
            pins.append(f'<a class="pin" href="#{ident}" style="left:{x / 12}%;top:{y / 9}%" '
                        f'aria-label="{html.escape(title)}">{i}</a>')
            labels.append(f'<li id="{ident}"><b>{i}. {html.escape(title)}</b><p>{html.escape(detail)}</p></li>')
        parts.append(f'<section id="{section["id"]}"><h2>{html.escape(section["title"])}</h2>'
                     f'<div class="figure"><img src="media/{section["image"]}" alt="{html.escape(section["title"])}">'
                     + ''.join(pins) + '</div><p class="muted">لقطة واجهة ببيانات عرض؛ اضغط الرقم لقراءة وظيفته.</p><ol>'
                     + ''.join(labels) + '</ol></section>')
    page = '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>نزلها — دليل الأزرار</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b1020;color:#e8edff;font:18px/1.8 system-ui,sans-serif}
header,main,footer{max-width:1160px;margin:auto;padding:28px}header{padding-top:55px}h1{font-size:42px;margin:0}
a{color:#a9c5ff}nav{display:flex;gap:14px;flex-wrap:wrap;margin-top:22px}nav a{padding:8px 15px;border:1px solid #364367;border-radius:12px;text-decoration:none}
section{margin:25px 0 48px;padding:24px;background:#152037;border:1px solid #2a3956;border-radius:24px}
.figure{position:relative;line-height:0;border-radius:14px;overflow:hidden}.figure img{width:100%;height:auto}
.pin{position:absolute;transform:translate(-50%,-50%);display:grid;place-items:center;background:#e03f51;color:#fff;width:30px;height:30px;border:2px solid white;border-radius:50%;font:bold 15px/1 system-ui;text-decoration:none;box-shadow:0 2px 8px #0008}
.pin:hover,.pin:focus{background:#075cce;outline:4px solid #51d7fa}.muted{color:#adbad6;font-size:14px}
ol{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}li{padding:14px;background:#0d1629;border-radius:12px;scroll-margin-top:20px}li:target{outline:3px solid #51d7fa}li p{margin:5px 0 0;color:#c4cfe7;font-size:16px}
.notice{border-right:4px solid #51d7fa;padding:14px 20px;background:#152037;border-radius:12px}.platforms{display:flex;gap:12px;flex-wrap:wrap}.platforms span{border:1px solid #4a5e89;padding:8px 16px;border-radius:40px}video{width:100%;border-radius:20px;background:#050a12}button{font:inherit;border:0;background:#3453dc;color:white;border-radius:10px;padding:8px 15px;cursor:pointer}
@media(max-width:600px){header,main,footer{padding:18px}h1{font-size:30px}section{padding:12px}.pin{width:23px;height:23px;font-size:11px}ol{grid-template-columns:1fr}}@media print{body{background:white;color:black}section{background:white;break-inside:avoid}li{background:#f1f5fb;color:black}li p,.muted{color:#334}nav,video,button{display:none}a{color:#234}.notice{background:#eee}}
</style><header><p>Nazzelha · Mohamed Fooda</p><h1>كل زر له وظيفة واضحة</h1><p>دليل نزلها المصور: الروابط الفردية، بلايليست يوتيوب، السجل وتنزيل التطبيق.</p>
<div class="platforms"><span>Android 7+</span><span>Windows x64</span><span>Web</span><span>iPhone: Web</span></div>
<nav><a href="#queue">نزلها</a><a href="#playlist">البلايليست</a><a href="#history">السجل</a><a href="#developer">عن المطور</a><a href="USER_GUIDE_AR.md">الدليل الكامل</a><button onclick="window.print()">طباعة / حفظ PDF</button></nav></header><main>
<p class="notice">الحد الأدنى Android 7. اختبرنا التثبيت والترقية على 7 و17، وليس كل إصدار بينهما. الويب له حدود استضافة ولا يعادل خدمة التنزيل الخلفية في تطبيق Android المثبت. لا يوجد تطبيق iOS أصلي.</p>
<h2>الشرح المصور</h2><video controls preload="metadata" poster="media/queue.png"><source src="media/Nazzelha-Walkthrough-AR.mp4" type="video/mp4"></video>
<p class="muted">فيديو بتعليقات عربية من لقطات واجهة، وليس تسجيل تفاعل حي جديد. بعض البيانات توضيحية؛ نتائج التنزيل الفعلية موثقة منفصلة.</p>
''' + ''.join(parts) + '''<section><h2>المميزات وحدود المقارنة</h2><p>جودة مستقلة لكل كارت، مجلد عربي للبلايليست، استئناف واستبعاد كل عنصر، سجل القوائم، خدمة Android خلفية، محرك Windows مرفق، وترجمة ومظهر موحد. هذه نقاط قوة للمشروع، وليست ادعاءات حصرية مقارنة بكل المنافسين.</p><p><a href="USER_GUIDE_AR.md">شرح الحالات والأخطاء وحدود الويب وكل الأزرار</a> · <a href="verification-1.1.3.json">نتائج التحقق</a></p></section></main><footer><a href="https://nazzelha.mohamed-fooda-mtf.workers.dev/">الموقع الرسمي</a> · <a href="https://github.com/MTFOODA/nazzelha/releases/latest">تحميل النسخ الرسمية</a><p class="muted">صور توضيحية من واجهة التطبيق؛ الأرقام والإحصائيات الظاهرة ليست بيانات الموقع الحية.</p></footer></html>'''
    (DOCS / 'guide-ar.html').write_text(page, encoding='utf-8')


def ass_time(seconds):
    return f'{int(seconds) // 3600}:{int(seconds) // 60 % 60:02}:{int(seconds) % 60:02}.00'


def render_video(data, ffmpeg):
    WORK.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(ROOT / 'assets/fonts/Poppins-SemiBold.ttf'), 25)
    small = ImageFont.truetype(str(ROOT / 'assets/fonts/Poppins-Regular.ttf'), 16)
    ass = ['''[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
WrapStyle: 2
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,Tajawal,38,&H00FFFFFF,&H00FFFFFF,&H0020100B,&H00000000,1,0,0,0,100,100,0,0,1,0,0,9,30,30,30,1
Style: Body,Tajawal,29,&H00E6D8C9,&H00FFFFFF,&H0020100B,&H00000000,0,0,0,0,100,100,0,0,1,0,0,9,30,30,30,1
Style: Foot,Tajawal,21,&H00C8BDB0,&H00FFFFFF,&H0020100B,&H00000000,0,0,0,0,100,100,0,0,1,0,0,2,30,30,22,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
''']
    concat = []
    elapsed = 0
    chapters = ['# توقيت فصول فيديو نزلها', '', 'شرح مصور صامت بتعليقات عربية؛ ليس تسجيل شاشة حي جديد.', '']
    for index, scene in enumerate(data['scenes']):
        duration = scene.get('seconds', 9)
        frame = Image.new('RGB', (1280, 720), '#0b1020')
        draw = ImageDraw.Draw(frame)
        draw.rounded_rectangle((18, 94, 794, 654), 20, fill='#18253f', outline='#304366', width=2)
        image = Image.open(MEDIA / scene['image']).convert('RGB')
        image.thumbnail((748, 526), Image.Resampling.LANCZOS)
        frame.paste(image, (406 - image.width // 2, 374 - image.height // 2))
        draw.text((28, 22), 'Nazzelha', font=font, fill='#ffffff')
        draw.text((29, 60), 'Android 7+   /   Windows   /   Web', font=small, fill='#7ee4f1')
        draw.text((830, 630), f'{index + 1:02} / {len(data["scenes"]):02}', font=font, fill='#7ee4f1')
        draw.rounded_rectangle((830, 600, 1244, 608), 4, fill='#26344d')
        draw.rounded_rectangle((830, 600, 830 + int(414 * (index + 1) / len(data['scenes'])), 608), 4, fill='#51d7fa')
        if scene.get('point'):
            # Diagram overlay: the underlying screenshot remains unchanged.
            x, y = scene['point']
            original = Image.open(MEDIA / scene['image'])
            scale = image.width / original.width
            px = 406 - image.width // 2 + x * scale
            py = 374 - image.height // 2 + y * scale
            draw.ellipse((px - 17, py - 17, px + 17, py + 17), outline='#eb485c', width=5)
            draw.line((px + 18, py, min(px + 75, 785), py - 32), fill='#eb485c', width=4)
        frame.save(WORK / f'frame-{index:02}.png')
        concat.extend([f"file 'frame-{index:02}.png'", f'duration {duration}'])
        start, end = ass_time(elapsed), ass_time(elapsed + duration)
        title = scene['title'].replace('\n', r'\N')
        body = scene['text'].replace('\n', r'\N')
        ass.extend([f'Dialogue: 0,{start},{end},Title,,0,0,0,,{{\\an9\\pos(1240,145)}}{title}\n',
                    f'Dialogue: 0,{start},{end},Body,,0,0,0,,{{\\an9\\pos(1240,245)}}{body}\n',
                    f'Dialogue: 0,{start},{end},Foot,,0,0,0,,شرح مصور من لقطات الواجهة · بيانات عرض · النتائج الفعلية موثقة في الدليل\n'])
        chapters.append(f'{int(elapsed) // 60:02}:{int(elapsed) % 60:02} — {scene["title"].replace(chr(10), " ")}')
        elapsed += duration
    concat.append(f"file 'frame-{len(data['scenes']) - 1:02}.png'")
    (WORK / 'frames.txt').write_text('\n'.join(concat), encoding='utf-8')
    (WORK / 'captions.ass').write_text(''.join(ass), encoding='utf-8')
    (DOCS / 'DEMO_CHAPTERS_AR.md').write_text('\n'.join(chapters) + '\n', encoding='utf-8')
    fonts = (ROOT / 'assets/fonts').relative_to(ROOT).as_posix()
    # All filter paths are relative: no Windows drive-colon escaping ambiguity.
    subprocess.run([str(ffmpeg), '-hide_banner', '-loglevel', 'warning', '-y',
                    '-f', 'concat', '-safe', '0', '-i', 'build/walkthrough/frames.txt',
                    '-vf', f'ass=build/walkthrough/captions.ass:fontsdir={fonts},fps=25',
                    '-t', str(elapsed), '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                    '-metadata', 'title=Nazzelha - Arabic illustrated walkthrough',
                    str(MEDIA / 'Nazzelha-Walkthrough-AR.mp4')], cwd=ROOT, check=True)
    print(f'Walkthrough: {elapsed}s, {len(data["scenes"])} chapters')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--html-only', action='store_true')
    parser.add_argument('--ffmpeg', default=os.environ.get('FFMPEG_BINARY') or shutil.which('ffmpeg'))
    args = parser.parse_args()
    data = json.loads((DOCS / 'walkthrough.json').read_text(encoding='utf-8'))
    render_guide(data)
    if not args.html_only:
        ffmpeg = args.ffmpeg
        if not ffmpeg:
            ffmpeg = next((ROOT / '.venv/Lib/site-packages/imageio_ffmpeg/binaries').glob('ffmpeg*.exe'), None)
        if not ffmpeg:
            raise SystemExit('Provide --ffmpeg with a build that includes libass.')
        render_video(data, ffmpeg)

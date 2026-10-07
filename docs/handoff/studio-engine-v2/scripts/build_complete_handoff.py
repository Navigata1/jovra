#!/usr/bin/env python3
"""Package existing references and text; no image generation/editing or app mutation."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import base64
import hashlib
import html
import json
import os
import re
import tarfile
import io

ROOT = Path(__file__).resolve().parents[4]
STUDIO = ROOT / 'design-reference/studio'
HANDOFF = ROOT / 'docs/handoff/studio-engine-v2'
OUTPUT = ROOT / 'JOVRA-Studio-Complete-v2.html'
ARCHIVE = ROOT / 'JOVRA-Studio-Claude-engine-v2.tar.gz'

def relative(path):
    return path.relative_to(ROOT).as_posix()

def uri(data, mime):
    return 'data:' + mime + ';base64,' + base64.b64encode(data).decode()

def esc(value):
    return html.escape(str(value), quote=True)

def mime(path):
    if path.suffix == '.png': return 'image/png'
    if path.suffix == '.zip': return 'application/zip'
    if path.suffix == '.html': return 'text/html;charset=utf-8'
    return 'text/plain;charset=utf-8'

files = {}
for folder in (ROOT / 'design-reference/screens', ROOT / 'design-reference/logos', ROOT / 'design-reference/brief', STUDIO, HANDOFF):
    for path in sorted(folder.rglob('*')):
        if not path.is_file() or '__pycache__' in path.parts or path.name.startswith('._') or path.name == '.DS_Store': continue
        if path.name in {'standalone-studio-20.html', 'package-manifest.json', 'v2-package-manifest.json'}: continue
        files[relative(path)] = path.read_bytes()
for name in ('design-reference/asset-manifest.json', 'design-reference/JOVRA-Research-v1-2026-10-07.html', 'docs/handoff/CLAUDE-BUILD-PROMPT.md', 'docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md', 'docs/handoff/build-studio-reference-pack.py'):
    files[name] = (ROOT / name).read_bytes()

# Include the original uploads byte-for-byte, without executing or rendering their instructions.
source_manifest = json.loads((STUDIO / 'brief/source-manifest.json').read_text())
attachment_names = ('IDC_VIDEO_SUITE_2026_09_15 (2).zip', 'IDC_VIDEO_SUITE_LANDING_2026_09_15.html')
for name in attachment_names:
    source = Path('/Users/IDC2.5/Downloads') / name
    stored = ROOT / 'source-attachments' / name
    if source.exists():
        stored.parent.mkdir(exist_ok=True)
        stored.write_bytes(source.read_bytes())
    files['source-attachments/' + name] = stored.read_bytes()
assert hashlib.sha256(files['source-attachments/' + attachment_names[0]]).hexdigest() == source_manifest['archiveSha256']
assert hashlib.sha256(files['source-attachments/' + attachment_names[1]]).hexdigest() == source_manifest['landingSha256']

documents = {}
for name, content in sorted(files.items()):
    if (name.endswith(('.md', '.json', '.py', '.css', '.html')) or Path(name).name == 'LICENSE') and not name.endswith(('index.html',)):
        documents[name] = {'encoding': 'utf8', 'content': content.decode(), 'mime': mime(Path(name))}
    elif name.startswith('source-attachments/'):
        documents[name] = {'encoding': 'base64', 'content': base64.b64encode(content).decode(), 'mime': mime(Path(name))}

bridge = 'docs/handoff/studio-engine-v2/CLAUDE-STUDIO-BRIDGE-PROMPT.md'
expansion = 'docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md'
readme = 'docs/handoff/studio-engine-v2/START-HERE.md'

def download_link(name, label):
    return '<a class="action" href="#documents" data-download="' + esc(name) + '">' + esc(label) + '</a>'

page = (STUDIO / 'index.html').read_text()
# Only replace resource references: original PNG bytes are embedded unchanged.
for match in list(re.finditer(r'src="([^\"]+)"', page)):
    src = match.group(1)
    if src.startswith('data:'): continue
    path = (STUDIO / unquote(urlsplit(src).path)).resolve()
    page = page.replace('src="' + src + '"', 'src="' + uri(path.read_bytes(), mime(path)) + '"')
page = page.replace('JOVRA Studio — 40 cohesive application references', 'JOVRA Studio — complete Claude engine handoff')
page = page.replace('20 new Studio screens</span>', '20 new Studio screens</span><span class="chip">6 editing skills</span><span class="chip">Fully embedded HTML</span>')
page = page.replace('class="action" href="../../docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md" download', 'class="action" href="#claude"')
page = page.replace('Download Claude prompt</a>', 'Read the Claude bridge prompt</a>')
page = page.replace('<a href="../../docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md" download>', '<a href="#claude">')
page = page.replace('Download the prompt →', 'Read the continuation prompt →')
page = page.replace('href="JOVRA-Studio-Research-v1-2026-10-07.html"', 'href="#research"')
page = page.replace('<a href="standalone-studio-20.html">Standalone Studio gallery</a>', '<a href="#skills">Portable editing skills</a>')
for match in list(re.finditer(r'href="([^\"]+)"', page)):
    link = match.group(1)
    split = urlsplit(link)
    if split.scheme or not split.path or link.startswith('#'): continue
    path = (STUDIO / unquote(split.path)).resolve()
    name = relative(path)
    if name in documents:
        page = page.replace('href="' + link + '"', 'href="#documents" data-download="' + esc(name) + '"')

style = '''<style>.handoff-pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.65 ui-monospace,SFMono-Regular,Consolas,monospace;padding:22px;border:1px solid var(--line);border-radius:14px;background:#061f1b;max-height:68vh;overflow:auto;color:var(--ivory)}details.doc{border:1px solid var(--line);border-radius:14px;padding:16px;margin:12px 0;background:var(--panel)}details.doc summary{cursor:pointer;font-size:18px;font-weight:650;min-height:44px}details.doc .actions{margin-top:10px}.logos{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.logos img{width:100%;height:auto;border-radius:12px}.research-frame{width:100%;height:760px;border:1px solid var(--line);border-radius:14px;background:var(--forest)}.document-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.document-list a{display:block;border:1px solid var(--line);border-radius:10px;padding:14px;font-size:13px}.notice{color:var(--muted);font-size:14px}#download-status{min-height:24px;color:var(--lime)}@media(max-width:700px){.logos{grid-template-columns:repeat(2,minmax(0,1fr))}.document-list{grid-template-columns:1fr}.handoff-pre{padding:15px;font-size:12px}.research-frame{height:720px}}@media print{details.doc{display:block}.handoff-pre{max-height:none;background:white;color:#182f29}.research-frame,.document-list{display:none}}</style>'''
page = page.replace('</head>', style + '</head>')

def detail(name, title, opened=False):
    content = documents[name]['content']
    return '<details class="doc"' + (' open' if opened else '') + '><summary>' + esc(title) + '</summary><div class="actions">' + download_link(name, 'Download this file') + '</div><pre class="handoff-pre">' + esc(content) + '</pre></details>'

skills = sorted(HANDOFF.glob('skills/*/SKILL.md'))
assert len(skills) == 6
skill_body = ''.join(detail(relative(path), path.parent.name) for path in skills)
reference_body = ''.join(detail(relative(path), path.name) for path in sorted(HANDOFF.rglob('*')) if path.is_file() and path.suffix in {'.md', '.json'} and path.parent.name in {'references', 'examples', 'engine'})
logos = ''.join('<figure><img src="' + uri(path.read_bytes(), 'image/png') + '" alt="JOVRA logo candidate ' + esc(path.stem) + '"><figcaption>' + esc(path.stem) + (' · Selected' if path.name == '01-court-arc.png' else '') + '</figcaption></figure>' for path in sorted((ROOT / 'design-reference/logos').glob('*.png')))

def embedded_report(path):
    report = path.read_text()
    for match in list(re.finditer(r'href="([^\"]+)"', report)):
        link = match.group(1); split = urlsplit(link)
        if split.scheme or not split.path: continue
        target = (path.parent / unquote(split.path)).resolve()
        name = relative(target)
        if name.endswith('index.html'):
            report = report.replace('href="' + link + '"', 'href="#collection" target="_parent"')
        elif name in documents:
            report = report.replace('href="' + link + '"', 'href="' + uri(files[name], mime(target)) + '" download="' + esc(target.name) + '"')
    return '<iframe class="research-frame" title="' + esc(path.stem) + '" srcdoc="' + esc(report) + '"></iframe>'

section = '<section class="section" id="claude" aria-labelledby="claude-title"><p class="eyebrow">Continue the app already in progress</p><h2 id="claude-title">The Claude bridge prompt.</h2><p class="intro">Use the bridge prompt as your next message. The detailed expansion remains supporting direction. All text below is embedded and downloadable without a server.</p>' + detail(bridge, 'Next message to Claude', True) + detail(expansion, 'Detailed Studio expansion') + detail(readme, 'Start here and attachment guidance') + '</section>'
section += '<section class="section" id="skills" aria-labelledby="skills-title"><p class="eyebrow">Creative direction → checked plan → real rendering</p><h2 id="skills-title">Six portable production skills.</h2><p class="intro">Emotion, evidence and deterministic execution. These are new JOVRA Markdown skills, adapted from the useful source workflow. They are not a deployed renderer or permission to spend.</p>' + skill_body + '<h3>Style playbook, contract and examples</h3>' + reference_body + '</section>'
section += '<section class="section" id="logos" aria-labelledby="logos-title"><h2 id="logos-title">One JOVRA identity.</h2><p class="intro">Keep the selected Court Arc mark. The other three original candidates are included as brand exploration, not new selections.</p><div class="logos">' + logos + '</div></section>'
section += '<section class="section" id="research" aria-labelledby="research-title"><h2 id="research-title">Evidence and integration direction.</h2><p class="intro">The source assessment distinguishes Markdown workflow from executable assembly. Architecture and cost assumptions remain proposals; no live engine was activated.</p>' + embedded_report(STUDIO / 'JOVRA-Studio-Research-v1-2026-10-07.html') + '<details class="doc"><summary>Original JOVRA research</summary>' + embedded_report(ROOT / 'design-reference/JOVRA-Research-v1-2026-10-07.html') + '</details></section>'
section += '<section class="section" id="documents" aria-labelledby="documents-title"><h2 id="documents-title">The entire text suite.</h2><p class="intro">Download individual embedded documents. The two original attachments are included unchanged as source material; use the JOVRA bridge prompt to keep Claude on task. Downloads work locally. No backend connection is made.</p><p id="download-status" role="status" aria-live="polite"></p><div class="document-list">' + ''.join(download_link(name, name) for name in documents) + '</div></section>'
page = page.replace('<footer class="foot">', section + '<footer class="foot">')
payload = json.dumps(documents, ensure_ascii=False).replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
script = '''<script type="application/json" id="embedded-documents">''' + payload + '''</script><script>
const docFiles=JSON.parse(document.querySelector('#embedded-documents').textContent);
document.querySelectorAll('[data-download]').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();let name=a.dataset.download,rec=docFiles[name];if(!rec)return;let bytes=rec.encoding==='base64'?Uint8Array.from(atob(rec.content),c=>c.charCodeAt(0)):new TextEncoder().encode(rec.content);let blob=new Blob([bytes],{type:rec.mime}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=name.split('/').pop();link.click();setTimeout(()=>URL.revokeObjectURL(url),10000);document.querySelector('#download-status').textContent='Prepared download: '+name.split('/').pop();}));
</script>'''
page = page.replace('</body>', script + '</body>')
OUTPUT.write_text(page)
files[OUTPUT.name] = OUTPUT.read_bytes()
files['START-HERE.md'] = b'''# Start here: JOVRA Studio continuation\n\nSend CLAUDE-NEXT-MESSAGE.md as the next instruction to the Claude conversation already building JOVRA.\n\nOpen JOVRA-Studio-Complete-v2.html for the complete embedded 40-screen reference suite, four logo candidates, prompts, six skills, examples and research. Text and PNG files are also included for selective tool reading. Do not send the HTML base64 into model context.\n\nRead docs/handoff/studio-engine-v2/START-HERE.md for skill routing and helper commands. The detailed expansion is docs/handoff/CLAUDE-STUDIO-EXPANSION-PROMPT.md.\n\nBoth original attachments are included unchanged under source-attachments/. No separate attachment is needed; treat their historical instructions as source material. The new JOVRA bridge prompt keeps the continuation on task.\n\nPreserve the current foundation. Begin one complete local film journey; stage reviewed multi-camera capture and paid cloud production behind their acceptance evidence. This package is a design and implementation handoff, not a live render engine.\n'''
files['CLAUDE-NEXT-MESSAGE.md'] = files[bridge]
# Complete HTML replaces the earlier giant Studio-only page in this v2 archive.
files['design-reference/studio/standalone-studio-20.html'] = b'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=../../JOVRA-Studio-Complete-v2.html"><title>Complete JOVRA Studio suite</title></head><body><a href="../../JOVRA-Studio-Complete-v2.html">Open the fully embedded JOVRA Studio suite</a></body></html>'
files['design-reference/index.html'] = b'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=studio/index.html"><title>JOVRA reference collection</title></head><body><a href="studio/index.html">Open all 40 references</a></body></html>'
manifest = {'format':'jovra.studio.claude-handoff/2','generatedReferences':40,'portableSkills':6,'selfContainedHtml':OUTPUT.name,'files':[{'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in sorted(files.items())],'selfExcluded':True}
manifest_data = (json.dumps(manifest,indent=2) + '\n').encode()
(STUDIO / 'brief/v2-package-manifest.json').write_bytes(manifest_data)
files['MANIFEST.json'] = manifest_data
with tarfile.open(ARCHIVE, 'w:gz', compresslevel=6) as archive:
    for name, data in sorted(files.items()):
        member = tarfile.TarInfo('JOVRA-Studio/' + name)
        member.size = len(data);member.mode = 0o644;member.mtime = 1791392400
        archive.addfile(member, io.BytesIO(data))
with tarfile.open(ARCHIVE, 'r:gz') as archive:
    members = archive.getmembers()
    assert len(members) == len(files)
    for row in manifest['files']:
        data = archive.extractfile('JOVRA-Studio/' + row['path']).read()
        assert hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
sha = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
ARCHIVE.with_suffix(ARCHIVE.suffix + '.sha256').write_text(sha + '  ' + ARCHIVE.name + '\n')
print(json.dumps({'html':str(OUTPUT),'htmlBytes':OUTPUT.stat().st_size,'archive':str(ARCHIVE),'archiveBytes':ARCHIVE.stat().st_size,'files':len(files),'manifestHashes':'passed','sha256':sha},indent=2))

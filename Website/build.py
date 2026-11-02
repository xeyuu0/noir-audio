#!/usr/bin/env python3
"""Build NOIR's dependency-free multipage site from shared chrome and page bodies."""
from pathlib import Path
from html import escape
import math

ROOT = Path(__file__).resolve().parent
PUBLIC = ROOT / 'public'
ORIGIN = 'https://noir-audio-orpin.vercel.app'
PAGES = {
    'index': ('NOIR Audio — Sound, on your terms.', 'A native audio studio for Mac. Shape your voice, build your mix, and send it wherever it belongs.', 'home'),
    'studio': ('The studio — NOIR Audio', 'Mix, trigger clips, record, and replay in a focused native macOS audio workspace.', 'studio'),
    'effects': ('Voice & effects — NOIR Audio', 'Explore 15 reverb environments, 42 voice masks, and a reorderable voice processing chain.', 'effects'),
    'routing': ('Audio routing — NOIR Audio', 'Connect microphones, apps, clips, and virtual audio devices through four independent stereo buses.', 'routing'),
    'download': ('Download for Mac — NOIR Audio', 'Download the NOIR Audio 0.1.0 Apple Silicon preview, virtual audio drivers, matching source, and checksums.', 'download'),
    'install': ('Getting started — NOIR Audio', 'Install NOIR Audio, set up its virtual devices, and route your microphone, clips, and applications.', 'guide'),
    'release': ('Release notes — NOIR Audio', 'What is included, tested, and still unverified in the NOIR Audio 0.1.0 development preview.', 'guide'),
    '404': ('Signal not found — NOIR Audio', 'This page is not connected. Return to the NOIR Audio studio.', 'error'),
}

def brand():
    return '<a class="brand" href="/" aria-label="NOIR Audio home"><img src="/assets/mark.svg" alt="" width="34" height="34"><span>NOIR<span class="brand-sub">AUDIO</span></span></a>'

def header(active):
    links = [('studio', 'Studio'), ('effects', 'Effects'), ('routing', 'Routing'), ('install', 'Guide')]
    nav = ''.join(f'<a href="/{slug}"' + (' aria-current="page"' if active == slug or (slug == 'install' and active == 'guide') else '') + f'>{label}</a>' for slug, label in links)
    return f'''<a class="skip-link" href="#main">Skip to content</a>
<header class="header-shell"><div class="site-header glass">{brand()}
<button class="menu-toggle" aria-expanded="false" aria-controls="site-nav" aria-label="Open navigation"><span></span><span></span></button>
<nav id="site-nav" aria-label="Main navigation">{nav}<a class="nav-download" href="/download"{' aria-current="page"' if active == 'download' else ''}>Download <span aria-hidden="true">↗</span></a></nav>
</div></header>'''

def footer():
    return f'''<footer class="site-footer wrap"><div class="footer-top">{brand()}<p>Sound, with intention.</p><a class="back-top" href="#main">Back to top <span aria-hidden="true">↑</span></a></div>
<div class="footer-bottom"><p>© 2026 NOIR Audio contributors<br><span>Independent software. Open source.</span></p><nav aria-label="Footer navigation"><a href="/install">Getting started</a><a href="/release">Release notes</a><a href="/downloads/NOIR-Audio-0.1.0-source.tar.gz" download>Source code ↗</a></nav><span class="footer-caption">MADE FOR macOS</span></div></footer>'''

def sculpture():
    """Original projected wave sculpture. Static SVG; motion is pointer-driven in CSS."""
    paths=[]
    for j in range(100):
        u=2*math.pi*j/100
        points=[]
        for k in range(121):
            v=2*math.pi*k/120
            radius=175+32*math.sin(u*3)
            tube=65+15*math.cos(u*3)
            x=(radius+tube*math.cos(v))*math.cos(u)
            y=(radius+tube*math.cos(v))*math.sin(u)
            z=tube*math.sin(v)+35*math.cos(u*3)
            # Tilt an irregular torus toward the viewer, then rotate in its plane.
            yy=y*.64-z*.768; zz=y*.768+z*.64
            xx=x*.94+yy*.342; yy=-x*.342+yy*.94
            perspective=950/(950-zz)
            points.append((330+xx*perspective,330+yy*perspective))
        d='M'+' L'.join(f'{x:.2f},{y:.2f}' for x,y in points)+' Z'
        opacity=.28+.6*((math.sin(u)+1)/2)
        paths.append((math.sin(u),f'<path d="{d}" opacity="{opacity:.3f}"/>'))
    paths.sort()
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 660" fill="none"><defs><linearGradient id="metal" x1="10%" y1="5%" x2="85%" y2="100%"><stop stop-color="#fff"/><stop offset=".3" stop-color="#f4f4f4"/><stop offset=".51" stop-color="#555"/><stop offset=".72" stop-color="#eee"/><stop offset="1" stop-color="#444"/></linearGradient></defs><g stroke="url(#metal)" stroke-width="1.05">'+''.join(p for _,p in paths)+'</g></svg>'

def build():
    (PUBLIC/'assets'/'sculpture.svg').write_text(sculpture())
    for name,(title,description,active) in PAGES.items():
        route='/' if name == 'index' else '/'+name
        body=(ROOT/'pages'/f'{name}.html').read_text()
        document=name in ('install','release')
        if document:
            body='<div class="document-layout wrap"><aside class="document-nav"><p class="eyebrow">THE FIELD GUIDE</p><a href="/install"'+(' aria-current="page"' if name=='install' else '')+'>Getting started</a><a href="/release"'+(' aria-current="page"' if name=='release' else '')+'>Release notes</a><a href="/download">Downloads ↗</a><span>NOIR AUDIO · 0.1.0</span></aside><article class="document">'+body+'</article></div>'
        html=f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="theme-color" content="#050505">
<title>{escape(title)}</title><meta name="description" content="{escape(description)}"><meta property="og:title" content="{escape(title)}"><meta property="og:description" content="{escape(description)}"><meta property="og:type" content="website"><meta property="og:url" content="{ORIGIN+route}"><meta property="og:image" content="{ORIGIN}/assets/mixer.png"><link rel="canonical" href="{ORIGIN+route}">
<link rel="icon" href="/assets/mark.svg" type="image/svg+xml"><link rel="stylesheet" href="/style.css"><script src="/app.js" defer></script></head>
<body class="page-{name}"><div class="ambient" aria-hidden="true"></div>{header(active)}<main id="main" tabindex="-1">{body}</main>{footer()}</body></html>'''
        (PUBLIC/f'{name}.html').write_text(html)
    (PUBLIC/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join(f'<url><loc>{ORIGIN+("/" if p=="index" else "/"+p)}</loc></url>' for p in PAGES if p!='404')+'</urlset>\n')
    print(f'Built {len(PAGES)} static pages and original wave sculpture.')

if __name__=='__main__': build()

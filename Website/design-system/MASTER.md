# NOIR Audio website

User-requested UI/UX Pro Max workflow, applied to a native macOS audio product.

The broad design-system lookup returned an unsuitable lavender/neumorphic direction. It was rejected. The narrower style lookup verified **Minimalism & Swiss Style**; the `html-tailwind` responsive-layout lookup verified mobile gutters, responsive images and a consistent DOM across breakpoints. This document records the curated application of those results, not the rejected output. The requested redesign adds verified Glassmorphism guidance (translucent layers, 20px blur, reflections, thin borders) and Reduced Motion / Excessive Motion guidance. The user’s monochrome constraint takes precedence over the generic glass style’s colorful-background suggestion.

- Palette: background `#050505`, surface `#101010`, elevated `#191919`, text `#FFFFFF`, secondary `#A8A8A8`, translucent white borders. No chromatic accents.
- Typography: system sans for headlines/body, system mono for short labels and technical facts. Fluid display scale; body at least 16px. Short balanced headings, readable line lengths.
- Layout: 1240px maximum content width; 24px mobile / 48px desktop minimum gutters; generous spacing and fine rules. Seven focused pages share floating navigation and a footer. An original projected SVG wave sculpture leads the homepage; real product screenshots anchor the Studio and Effects pages.
- Interaction: one primary action per section, 44px control targets, clear white focus outline, keyboard-operable studio/effect/workflow tabs, native FAQ disclosures, a mobile navigation disclosure with Escape/focus return, current-page indication, and native browser history. All download links address real same-origin files.
- Motion: 180ms feedback, 420ms panel changes, 460ms native document transitions, 750ms one-time scroll reveals, and a finite 850ms hero entrance. The sculpture follows fine-pointer movement slightly; no continuous autoplay or sound. Reduced motion disables all introductions, reveals, parallax, transitions, and smooth scrolling. No-JavaScript content and links remain visible and functional. Browser support falls back to normal page navigation.
- Glass: translucent charcoal with 20px backdrop blur, light top-edge reflection, subtle inner shadows, and 1px white borders. Opaque fallback for browsers without backdrop filters. Increase surface opacity under prefers-contrast: more.
- Performance: static HTML, local SVG and compact PNG screenshots, compositor-friendly opacity/transform motion, IntersectionObserver unobserves completed reveals, a single requestAnimationFrame for pointer updates, and no persistent animation loop.
- Accessibility: skip link, semantic landmarks, heading order, image descriptions, explicit tab state, sufficient contrast. Do not convey status by color alone.
- Content: verified app features and real screenshots only. Label 0.1.0 as an unnotarized Apple Silicon preview. Link matching GPL source, driver installer, installation instructions, release limitations and SHA-256 checksums.
- Implementation: static HTML/CSS/JavaScript, no framework runtime, external fonts, trackers or cookies. Serve only `public/` on Vercel.

## Implementation references

- [Chrome: cross-document view transitions](https://developer.chrome.com/docs/web-platform/view-transitions/cross-document): same-origin pages opt in with `@view-transition { navigation: auto; }`. Navigation remains native; no router intercepts anchors.
- UI/UX Pro Max focused results: `glassmorphism --domain style -n 1`; `reduced motion --domain ux -n 2`. All styling remains grayscale.

# NOIR Audio website

Eight static pages with a shared liquid-glass interface, using the app's exact grayscale palette. Home, Studio, Effects, Routing, Download, Mac Setup, Windows Setup, and Release Notes have distinct URLs and purposes. A matching custom 404 completes the site. The screenshots are captured from the real packaged app. No external fonts, framework runtime, analytics, account system or cookies are used.

Design decisions from the user-requested UI/UX Pro Max skill are in `design-system/MASTER.md`.

## Local preview and verification

From the repository root:

```sh
python3 Website/build.py
python3 Website/serve.py
```

Open `http://127.0.0.1:4173`. The server supports the same extensionless HTML links used by Vercel.

`Website/build.py` combines bodies in `Website/pages/` with shared navigation, metadata, and footer, and generates the original SVG wave sculpture and sitemap. Edit those source bodies and rerun the builder; `public/*.html` are generated files. CSS and JavaScript live directly in `public/`. There are no Python package dependencies.

`Website/test.mjs` exercises all eight pages, native document transitions, browser Back, reduced motion, pointer response, mobile navigation and focus, every tab family, FAQ disclosures, six responsive widths, no-JavaScript fallback, internal links, the sitemap, console errors, and real download integrity. It also saves full desktop/mobile screenshots. Set `PLAYWRIGHT_MODULE` to a local Playwright or playwright-core module path; `SITE_URL` defaults to the local preview. If needed, set `BROWSER_EXECUTABLE` to an installed Chromium executable. The test never interacts with the native audio engine.

## Release files

Build the website with `python3 Website/build.py`, build and package the app, then run `bash Scripts/prepare-website.sh`. This copies the Mac disk image and app ZIP, Windows setup and portable ZIP, Mac driver package, matching source archive and freshly generated checksums into `public/downloads`.

Only `public/` is served; `vercel.json` provides routing, content policy and cache settings. Deploy this Website directory to the user's `noir-audio` Vercel project. Do not deploy the repository root or any Build directory, local certificates, recordings or session files.

Public URL: https://noir-audio-orpin.vercel.app

Project ID: `prj_8cAeB5fLFoBGWQYW3K8hofI2P0s9`. The authenticated Vercel connector uploads explicit files and deploys them into the user's connected team. Reuse this project for updates. There are no deployment tokens or environment secrets in the repository.

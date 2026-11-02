/* Native links and semantic controls remain usable without JavaScript. */
(() => {
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  document.documentElement.classList.add('has-js');

  const toggle = document.querySelector('.menu-toggle');
  const nav = document.querySelector('#site-nav');
  const mobile = matchMedia('(max-width: 800px)');
  function setMenu(open, restoreFocus = false) {
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    nav.classList.toggle('is-open', open);
    if (restoreFocus) toggle.focus();
  }
  toggle.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') setMenu(false, true);
  });
  document.addEventListener('click', event => {
    if (!event.target.closest('.site-header')) setMenu(false);
  });
  document.querySelector('.site-header').addEventListener('focusout', event => {
    if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget)) setMenu(false);
  });
  nav.addEventListener('click', event => { if (event.target.closest('a')) setMenu(false); });
  mobile.addEventListener('change', () => setMenu(false));
  window.addEventListener('pageshow', () => setMenu(false));

  document.querySelectorAll('[role="tablist"]').forEach(list => {
    const tabs = [...list.querySelectorAll('[role="tab"]')];
    function activate(tab, focus = false) {
      tabs.forEach(item => {
        const selected = item === tab;
        item.setAttribute('aria-selected', String(selected));
        item.tabIndex = selected ? 0 : -1;
        document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
      });
      if (focus) tab.focus();
    }
    tabs.forEach((tab, index) => {
      tab.addEventListener('click', () => activate(tab));
      tab.addEventListener('keydown', event => {
        let target;
        if (event.key === 'ArrowRight') target = (index + 1) % tabs.length;
        if (event.key === 'ArrowLeft') target = (index - 1 + tabs.length) % tabs.length;
        if (event.key === 'Home') target = 0;
        if (event.key === 'End') target = tabs.length - 1;
        if (target !== undefined) { event.preventDefault(); activate(tabs[target], true); }
      });
    });
  });

  const reveals = [...document.querySelectorAll('.reveal')];
  let observer;
  if ('IntersectionObserver' in window && !motion.matches) {
    observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.08, rootMargin: '0px 0px 20px 0px' });
    // Only hide content below the first viewport; initial render never flashes blank.
    const belowFold = reveals.filter(item => item.getBoundingClientRect().top > innerHeight - 20);
    belowFold.forEach(item => { item.classList.add('reveal-pending'); observer.observe(item); });
  }
  // Keyboard navigation must never land on an invisible reveal target.
  document.addEventListener('focusin', event => event.target.closest('.reveal')?.classList.add('is-visible'));

  const art = document.querySelector('[data-parallax]');
  const pointer = matchMedia('(pointer: fine)');
  let frame;
  if (art) {
    art.addEventListener('pointermove', event => {
      if (motion.matches || !pointer.matches) return;
      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const rect = art.getBoundingClientRect();
        art.style.setProperty('--pointer-x', `${((event.clientX - rect.left) / rect.width - .5) * 18}px`);
        art.style.setProperty('--pointer-y', `${((event.clientY - rect.top) / rect.height - .5) * 18}px`);
      });
    });
    art.addEventListener('pointerleave', resetArt);
  }
  function resetArt() {
    if (frame) cancelAnimationFrame(frame);
    if (art) { art.style.removeProperty('--pointer-x'); art.style.removeProperty('--pointer-y'); }
  }
  motion.addEventListener('change', () => {
    resetArt();
    if (motion.matches) { observer?.disconnect(); reveals.forEach(item => item.classList.add('is-visible')); }
  });
})();

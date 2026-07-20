// Scroll-spy for the left-hand sidebar on API pages. Highlights the
// sidebar link whose target section is currently visible, replacing the
// cue the (removed) "On this page" sidebar used to provide.
(function() {
  function init() {
    if (!document.body.classList.contains('api-page')) return;

    const sidebar = document.querySelector('.bd-sidebar-primary');
    if (!sidebar) return;

    const currentPath = window.location.pathname;
    // Find sidebar links that point to an anchor on the current page.
    const items = [...sidebar.querySelectorAll('a[href*="#"]')]
      .map(link => {
        const href = link.getAttribute('href');
        const hashIdx = href.indexOf('#');
        if (hashIdx < 0) return null;
        const pagePart = href.substring(0, hashIdx);
        const hash = href.substring(hashIdx + 1);
        if (!hash) return null;

        let absolutePath;
        try {
          absolutePath = pagePart
            ? new URL(pagePart, window.location.href).pathname
            : currentPath;
        } catch (e) {
          return null;
        }
        if (absolutePath !== currentPath) return null;
        const target = document.getElementById(hash);
        if (!target) return null;
        return { link, target };
      })
      .filter(Boolean);

    if (!items.length) return;

    // Sort by document order so "last past the probe" works correctly.
    items.sort((a, b) => {
      const pos = a.target.compareDocumentPosition(b.target);
      if (pos & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
      if (pos & Node.DOCUMENT_POSITION_PRECEDING) return 1;
      return 0;
    });

    function setActive(idx) {
      items.forEach((item, i) => {
        item.link.classList.toggle('current-section', i === idx);
      });
    }

    function update() {
      const scrollY = window.scrollY;
      const viewportH = window.innerHeight;
      const docH = document.documentElement.scrollHeight;

      // Bottom of the page: pick the last section regardless of probe.
      if (scrollY + viewportH >= docH - 4) {
        setActive(items.length - 1);
        return;
      }

      // Probe line at ~1/3 down the viewport (below the fixed navbar).
      // A section activates as soon as its top crosses this line, so
      // headings light up the sidebar as they enter the upper portion of
      // the visible area rather than only once they've scrolled past the
      // very top.
      const probe = scrollY + Math.max(viewportH * 0.33, 140);
      let activeIdx = -1;
      items.forEach((item, i) => {
        const top = item.target.getBoundingClientRect().top + scrollY;
        if (top <= probe) activeIdx = i;
      });
      // Before the first section has crossed the probe, keep the first
      // one highlighted so the sidebar is never blank.
      if (activeIdx < 0) activeIdx = 0;
      setActive(activeIdx);
    }

    update();
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

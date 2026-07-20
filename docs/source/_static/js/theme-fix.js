// Override pydata-sphinx-theme's 3-state theme switcher to toggle only
// between light and dark (skip "auto" mode) with a single click.
(function() {
  function applyMode(mode) {
    document.documentElement.dataset.mode = mode;
    document.documentElement.dataset.theme = mode;
    try {
      localStorage.setItem('mode', mode);
      localStorage.setItem('theme', mode);
    } catch (e) {}
    document.querySelectorAll('.dropdown-menu').forEach(el => {
      if (mode === 'dark') el.classList.add('dropdown-menu-dark');
      else el.classList.remove('dropdown-menu-dark');
    });
  }

  function toggleTheme(e) {
    if (e) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
    const current = document.documentElement.dataset.theme || 'light';
    applyMode(current === 'dark' ? 'light' : 'dark');
  }

  function attach() {
    // If the auto mode is currently active, flip to light/dark first
    if (document.documentElement.dataset.mode === 'auto') {
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      applyMode(prefersDark ? 'dark' : 'light');
    }
    // Turn pydata's Bootstrap dropdown switcher into a plain toggle:
    // strip the dropdown trigger so a click just flips light<->dark.
    document.querySelectorAll('.theme-switch-button').forEach(btn => {
      btn.removeAttribute('data-bs-toggle');   // kill the Bootstrap dropdown
      btn.classList.remove('dropdown-toggle'); // and its caret
      // Clone node to strip existing listeners, then wire ours
      const fresh = btn.cloneNode(true);
      btn.parentNode.replaceChild(fresh, btn);
      fresh.addEventListener('click', toggleTheme);
    });
    // Remove the three-option menu and the dropdown container behavior.
    document.querySelectorAll('.theme-switch-container').forEach(c => {
      c.classList.remove('dropdown');
      const menu = c.querySelector('.dropdown-menu');
      if (menu) menu.remove();
    });
  }

  // Close the mobile sidebar drawer when any nav link inside it is clicked
  // (including a link to the current page, which would otherwise leave the
  // drawer open since no navigation occurs).
  function wireSidebarDismissal() {
    const modals = ['#pst-primary-sidebar-modal', '#pst-secondary-sidebar-modal'];
    modals.forEach(sel => {
      const modal = document.querySelector(sel);
      if (!modal) return;
      modal.addEventListener('click', (e) => {
        const link = e.target.closest('a');
        if (link && modal.contains(link) && modal.open) {
          modal.close();
        }
      });
    });
  }

  // Sync the heights of the landing-page code cards so all three match
  // the tallest one (row 1 auto-aligns via grid, but row 2's card is in
  // its own track and otherwise shorter).
  function syncCodeCardHeights() {
    const cards = document.querySelectorAll('.code-grid .code-card');
    if (!cards.length) return;
    cards.forEach(c => c.style.minHeight = '');
    const max = [...cards].reduce((m, c) => Math.max(m, c.offsetHeight), 0);
    if (max > 0) cards.forEach(c => c.style.minHeight = max + 'px');
  }

  // Style the header nav links as rounded chips:  [Tutorials]  API:
  // [SingleCell] [Pseudobulk] [DE]. The three API classes are grouped under an
  // "API:" label; Tutorials is chipped in place. pydata marks the current
  // section's <li> with .current/.active (on the page and its subpages), but
  // grouping moves the API <a>s out of their <li>, so mirror that state onto
  // the link itself so the active outline (CSS) persists. Desktop header only;
  // the mobile drawer keeps the flat list.
  function chip(a, li) {
    a.classList.add('api-nav-chip');
    if (li.classList.contains('current')) a.classList.add('current');
    if (li.classList.contains('active')) a.classList.add('active');
  }
  function groupApiNav() {
    document.querySelectorAll('.bd-header .bd-navbar-elements.navbar-nav')
      .forEach(ul => {
        if (ul.querySelector('.api-nav-group')) return;
        const lis = [...ul.children].filter(el => el.matches('li.nav-item'));
        // API entries point into the API reference; everything else
        // (Installation, Tutorials, ...) is a standalone chip. Detect via the
        // resolved absolute href so it works at any page depth, then chip the
        // non-API links in place.
        const isApi = li => {
          const a = li.querySelector('a.nav-link');
          return !!a && /\/(singlecell|pseudobulk|de)(\/|$)/.test(
            new URL(a.href, location.href).pathname);
        };
        lis.filter(li => !isApi(li)).forEach(li => {
          const a = li.querySelector('a.nav-link');
          if (a) chip(a, li);
        });
        const apiLis = lis.filter(isApi);
        const links = apiLis.map(li => li.querySelector('a.nav-link'));
        if (!apiLis.length || links.some(a => !a)) return;
        const group = document.createElement('li');
        group.className = 'nav-item api-nav-group';
        const label = document.createElement('span');
        label.className = 'api-nav-fix';
        label.textContent = 'API:';
        group.appendChild(label);
        links.forEach((a, i) => {
          chip(a, apiLis[i]);
          group.appendChild(a);
        });
        apiLis[apiLis.length - 1].after(group);
        apiLis.forEach(li => li.remove());
      });
  }

  // Run after pydata-sphinx-theme's own listeners are attached
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => setTimeout(() => {
      attach();
      wireSidebarDismissal();
      syncCodeCardHeights();
      groupApiNav();
    }, 0));
  } else {
    setTimeout(() => {
      attach();
      wireSidebarDismissal();
      syncCodeCardHeights();
      groupApiNav();
    }, 0);
  }
  window.addEventListener('resize', () => {
    clearTimeout(window.__codeCardResize);
    window.__codeCardResize = setTimeout(syncCodeCardHeights, 120);
  });
})();

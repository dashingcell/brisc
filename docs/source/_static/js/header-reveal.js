// Mobile auto-hiding header ("headroom" pattern): hide the top bar while
// scrolling down (maximising reading space) and reveal it while scrolling up,
// so the site-navigation hamburger stays reachable from anywhere on a long
// page instead of only at the very top. On wide screens the header is always
// visible and this does nothing. Degrades safely: if the header can't be found
// or the browser lacks the needed APIs, the header just stays pinned.
(function () {
  "use strict";
  var header = document.querySelector(".bd-header");
  if (!header || !window.matchMedia || !window.requestAnimationFrame) return;

  var mq = window.matchMedia("(max-width: 959.98px)");
  var THRESHOLD = 6; // px of movement before we react, to ignore jitter
  var lastY = window.scrollY || window.pageYOffset || 0;
  var headerH = header.offsetHeight;
  var ticking = false;

  // A nav drawer being open (the hamburger menu / secondary TOC) should never
  // leave the header hidden underneath it.
  function drawerOpen() {
    return !!document.querySelector(
      "#pst-primary-sidebar-modal[open], #pst-secondary-sidebar-modal[open]"
    );
  }

  function update() {
    ticking = false;
    var y = Math.max(0, window.scrollY || window.pageYOffset || 0);
    // Wide screen, near the top, or a drawer open -> always show.
    if (!mq.matches || y <= headerH || drawerOpen()) {
      header.classList.remove("bd-header--hidden");
      lastY = y;
      return;
    }
    var dy = y - lastY;
    if (Math.abs(dy) < THRESHOLD) return; // sub-threshold: keep reference point
    if (dy > 0) header.classList.add("bd-header--hidden");    // scrolling down
    else header.classList.remove("bd-header--hidden");        // scrolling up
    lastY = y;
  }

  function onScroll() {
    if (!ticking) {
      ticking = true;
      window.requestAnimationFrame(update);
    }
  }
  window.addEventListener("scroll", onScroll, { passive: true });

  function onLayoutChange() {
    headerH = header.offsetHeight;
    update();
  }
  window.addEventListener("resize", onLayoutChange, { passive: true });
  if (mq.addEventListener) mq.addEventListener("change", onLayoutChange);
  else if (mq.addListener) mq.addListener(onLayoutChange);
})();

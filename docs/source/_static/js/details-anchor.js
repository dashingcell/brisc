// Deep links into collapsible boxes. sphinx-design dropdowns render as
// <details> elements; a browser scrolls to a <details> that is the target of an
// in-page "#id" link but does not expand it (and when the box is only a line or
// two away, the scroll is imperceptible). This opens the targeted box — and any
// box enclosing it — and scrolls it clear of the sticky header, so a reference
// like "see the box above" actually reveals the box. Degrades safely: links
// that don't point into a <details> are left entirely to the browser.
(function () {
  "use strict";

  // Height to clear when a header is pinned at the top of the viewport; 0 when
  // the header scrolls away or is hidden (e.g. the mobile auto-hiding header).
  function headerOffset() {
    var header = document.querySelector(".bd-header");
    if (!header) return 0;
    var position = getComputedStyle(header).position;
    if (position !== "fixed" && position !== "sticky") return 0;
    var rect = header.getBoundingClientRect();
    return rect.bottom > 0 ? rect.height + 8 : 0;
  }

  function idFromHash(hash) {
    if (!hash || hash.length < 2) return "";
    try { return decodeURIComponent(hash.slice(1)); }
    catch (e) { return hash.slice(1); }
  }

  // Open the element with this id and every <details> around it, then bring it
  // into view below the header. Returns false if no such element exists.
  function reveal(id) {
    var el = id && document.getElementById(id);
    if (!el) return false;
    for (var node = el; node; node = node.parentElement) {
      if (node.tagName === "DETAILS") node.open = true;
    }
    window.requestAnimationFrame(function () {
      var top = el.getBoundingClientRect().top + window.scrollY - headerOffset();
      window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
    });
    return true;
  }

  // Intercept only clicks on in-page links that point into a box; this also
  // covers re-clicking the current fragment, which fires no "hashchange".
  document.addEventListener("click", function (event) {
    var link = event.target.closest && event.target.closest('a[href^="#"]');
    if (!link) return;
    var id = idFromHash(link.getAttribute("href"));
    var target = id && document.getElementById(id);
    if (!target || !target.closest("details")) return;
    if (reveal(id)) {
      event.preventDefault();
      try { history.pushState(null, "", link.getAttribute("href")); }
      catch (e) { /* History API may be restricted; the reveal already ran */ }
    }
  });

  // Fragment navigation and deep links arriving on page load.
  window.addEventListener("hashchange", function () {
    reveal(idFromHash(window.location.hash));
  });
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      reveal(idFromHash(window.location.hash));
    });
  } else {
    reveal(idFromHash(window.location.hash));
  }
})();

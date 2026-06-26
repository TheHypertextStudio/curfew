/* Curfew landing — scroll reveals.
 *
 * Lifts each `.reveal` section in once as it enters the viewport. Subtle and
 * one-shot; the sky (sky.js) carries the atmosphere, this only nudges the
 * content. Under Reduce Motion the CSS already shows everything, so we simply
 * reveal all sections immediately and skip the observer.
 */
(function () {
  "use strict";

  var sections = document.querySelectorAll(".reveal");
  if (!sections.length) return;

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce || !("IntersectionObserver" in window)) {
    sections.forEach(function (el) {
      el.classList.add("in");
    });
    return;
  }

  var observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        }
      });
    },
    { rootMargin: "0px 0px -12% 0px", threshold: 0.1 }
  );

  sections.forEach(function (el) {
    observer.observe(el);
  });
})();

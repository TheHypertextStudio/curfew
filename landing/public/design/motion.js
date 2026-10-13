/* Content is visible before JS and after cancellation; motion never gates access. */
const preference = matchMedia("(prefers-reduced-motion: reduce)");
const active = new Set();
const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      if (preference.matches) continue;
      const styles = getComputedStyle(document.documentElement);
      const animation = entry.target.animate(
        [
          {
            opacity: 0,
            transform: `translateY(${styles.getPropertyValue("--motion-enter-distance").trim()})`,
          },
          { opacity: 1, transform: "translateY(0)" },
        ],
        {
          duration: parseFloat(
            styles.getPropertyValue("--motion-enter-duration"),
          ),
          easing: styles.getPropertyValue("--motion-enter-easing").trim(),
        },
      );
      active.add(animation);
      const remove = () => active.delete(animation);
      animation.addEventListener("finish", remove, { once: true });
      animation.addEventListener("cancel", remove, { once: true });
    }
  },
  { threshold: 0, rootMargin: "0px 0px 48px 0px" },
);
document
  .querySelectorAll(
    ".product-heading, .product-capture, .connections > *, .footer-invitation",
  )
  .forEach((element) => {
    // Never hide content the person can already see when enhancement starts.
    const bounds = element.getBoundingClientRect();
    if (bounds.top < innerHeight && bounds.bottom > 0) return;
    observer.observe(element);
  });
preference.addEventListener("change", () => {
  if (preference.matches) for (const animation of active) animation.cancel();
});

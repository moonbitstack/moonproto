// Page chrome: the scrollbar leaves the top edge, the theme toggle, copy buttons.
const root = document.documentElement;

const markAtTop = () => root.classList.toggle("at-top", window.scrollY === 0);
window.addEventListener("scroll", markAtTop, { passive: true });
markAtTop();

const stored = localStorage.getItem("moonproto-theme");
if (stored === "light" || stored === "dark") root.dataset.theme = stored;

const toggle = document.querySelector("[data-theme-toggle]");
if (toggle) {
  toggle.addEventListener("click", () => {
    const dark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = dark ? "light" : "dark";
    localStorage.setItem("moonproto-theme", root.dataset.theme);
  });
}

for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.classList.add("done");
      setTimeout(() => button.classList.remove("done"), 1200);
    } catch {
      /* clipboard unavailable: the command stays selectable */
    }
  });
}

// Page chrome: the scrollbar leaves the top edge, the theme toggle, copy buttons.
const root = document.documentElement;

const markAtTop = () => root.classList.toggle("at-top", window.scrollY === 0);
window.addEventListener("scroll", markAtTop, { passive: true });
markAtTop();

// With nothing stored the page follows the system: no data-theme attribute is
// written, so the prefers-color-scheme rules in the stylesheet stay in charge,
// including when the system switches while the page is open.
const media = matchMedia("(prefers-color-scheme: dark)");
let chosen = localStorage.getItem("moonproto-theme");
if (chosen !== "light" && chosen !== "dark") chosen = null;
if (chosen) root.dataset.theme = chosen;

const effective = () => chosen ?? (media.matches ? "dark" : "light");

const toggle = document.querySelector("[data-theme-toggle]");
const describe = () => {
  if (!toggle) return;
  const next = effective() === "dark" ? "light" : "dark";
  toggle.setAttribute("aria-label", `Switch to the ${next} theme`);
  toggle.setAttribute("title", `Switch to the ${next} theme`);
};

if (toggle) {
  toggle.addEventListener("click", () => {
    chosen = effective() === "dark" ? "light" : "dark";
    root.dataset.theme = chosen;
    localStorage.setItem("moonproto-theme", chosen);
    describe();
  });
}

media.addEventListener("change", describe);
describe();

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

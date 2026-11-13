(function () {
  "use strict";

  var STORAGE_KEY = "rhcsa-theme";
  var root = document.documentElement;

  function getSavedTheme() {
    try {
      var saved = localStorage.getItem(STORAGE_KEY);
      return saved === "light" || saved === "dark" ? saved : null;
    } catch (error) {
      return null;
    }
  }

  function getTheme() {
    return getSavedTheme() || "dark";
  }

  function updateButton(theme) {
    var button = document.getElementById("theme-toggle");
    if (!button) return;

    var isDark = theme === "dark";
    button.textContent = isDark ? "☀️ Modo claro" : "🌙 Modo oscuro";
    button.setAttribute(
      "aria-label",
      isDark ? "Cambiar a modo claro" : "Cambiar a modo oscuro"
    );
    button.setAttribute("aria-pressed", String(isDark));
  }

  function applyTheme(theme) {
    root.setAttribute("data-theme", theme);
    updateButton(theme);
  }

  // Se aplica antes de pintar la pagina para evitar un destello del tema claro.
  applyTheme(getTheme());

  document.addEventListener("DOMContentLoaded", function () {
    var sidebar = document.querySelector(".sidebar");
    if (!sidebar) return;

    var button = document.createElement("button");
    button.type = "button";
    button.id = "theme-toggle";
    button.className = "theme-toggle";
    button.addEventListener("click", function () {
      var next =
        root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      applyTheme(next);
      try {
        localStorage.setItem(STORAGE_KEY, next);
      } catch (error) {
        /* localStorage puede no estar disponible */
      }
    });

    sidebar.appendChild(button);
    applyTheme(root.getAttribute("data-theme") || getTheme());
  });

  // Mantiene el tema sincronizado entre pestanas.
  window.addEventListener("storage", function (event) {
    if (event.key === STORAGE_KEY) {
      applyTheme(event.newValue === "light" ? "light" : "dark");
    }
  });
})();

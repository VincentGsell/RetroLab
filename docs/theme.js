// RetroLab : dark / light theme switch. The system choice applies until the visitor picks one.
(function () {
  var root = document.documentElement;
  var button = document.querySelector('.theme');
  if (!button) return;
  var light = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;

  function current() {
    return root.getAttribute('data-theme') || (light && light.matches ? 'light' : 'dark');
  }

  function paint() {
    var dark = current() === 'dark';
    button.textContent = dark ? '☀' : '☾';
    var label = button.getAttribute(dark ? 'data-to-light' : 'data-to-dark');
    button.setAttribute('aria-label', label);
    button.title = label;
  }

  button.addEventListener('click', function () {
    var next = current() === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('retrolab-theme', next); } catch (e) {}
    paint();
  });
  if (light && light.addEventListener) light.addEventListener('change', paint);
  paint();
})();

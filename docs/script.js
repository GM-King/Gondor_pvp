// Use the release publication time, with a bundled timestamp for offline visits.
(() => {
  const time = document.getElementById('last-updated');
  let updated = Date.parse(time.dateTime);
  function refresh() {
    const minutes = Math.max(0, Math.floor((Date.now() - updated) / 60000));
    const [count, unit] = minutes >= 1440 ? [Math.floor(minutes / 1440), 'day']
      : minutes >= 60 ? [Math.floor(minutes / 60), 'hour'] : [minutes, 'minute'];
    time.textContent = `${count} ${unit}${count === 1 ? '' : 's'} ago`;
    time.title = new Date(updated).toLocaleString();
  }
  refresh();
  setInterval(refresh, 60000);
  fetch('https://api.github.com/repos/GM-King/Gondor_pvp/releases/tags/v0.9.13-beta')
    .then(response => { if (!response.ok) throw new Error('Release unavailable'); return response.json(); })
    .then(release => {
      const published = Date.parse(release.published_at);
      if (!Number.isFinite(published)) return;
      updated = published;
      time.dateTime = new Date(updated).toISOString();
      refresh();
    })
    .catch(() => {}); // Keep the bundled date if GitHub is unavailable or rate limited.
})();

(() => {
  const roasts = [
    'I’ve seen target dummies with better fucking footwork!',
    'Even the spirit healer has died of boredom.',
    'You’ve been outflanked by a fucking menu.',
    'That’s your war face? You look like you just vendored your fucking weapon!',
    'I’ve seen a corpse run with more fucking purpose!',
    'You found the download button. A fucking tactical breakthrough!'
  ];
  const text = document.getElementById('roast-text');
  const speech = text.parentElement;
  function fitSpeech(line) {
    const visibleText = text.textContent;
    text.textContent = line;
    const style = getComputedStyle(speech);
    const availableHeight = speech.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
    let size = 48;
    speech.style.fontSize = `${size}px`;
    while (size > 20 && text.scrollHeight > availableHeight) {
      speech.style.fontSize = `${--size}px`;
    }
    text.textContent = visibleText;
  }
  const announcement = document.getElementById('announcement');
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let bag = [];
  let last;
  let timer;
  let current = '';
  function finishLine() {
    clearTimeout(timer);
    text.textContent = current;
  }
  document.getElementById('sergeant').addEventListener('click', () => {
    clearTimeout(timer);
    if (!bag.length) {
      bag = [...roasts];
      for (let i = bag.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [bag[i], bag[j]] = [bag[j], bag[i]];
      }
      if (bag[bag.length - 1] === last) {
        [bag[0], bag[bag.length - 1]] = [bag[bag.length - 1], bag[0]];
      }
    }
    current = bag.pop();
    last = current;
    fitSpeech(current);
    announcement.textContent = current;
    text.textContent = '';
    if (motion.matches) {
      finishLine();
      return;
    }
    let position = 0;
    function writeNext() {
      text.textContent = current.slice(0, ++position);
      if (position < current.length) timer = setTimeout(writeNext, 22);
    }
    writeNext();
  });
  motion.addEventListener('change', () => {
    if (motion.matches && current) finishLine();
  });
  function refitSpeech() {
    fitSpeech(current || text.textContent);
  }
  refitSpeech();
  window.addEventListener('resize', refitSpeech);
  document.fonts.ready.then(refitSpeech);
  const dialog = document.getElementById('image-dialog');
  const large = document.getElementById('large-preview');
  if (typeof dialog.showModal === 'function') {
    document.querySelectorAll('[data-preview]').forEach(link => {
      link.addEventListener('click', event => {
        if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        large.src = link.href;
        large.alt = link.querySelector('img').alt;
        dialog.showModal();
      });
    });
    document.getElementById('close-preview').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', event => {
      const bounds = dialog.getBoundingClientRect();
      if (event.target === dialog && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) dialog.close();
    });
  }
})();

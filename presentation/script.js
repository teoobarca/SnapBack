// ============================================
// SnapBack Hackathon Presentation
// ============================================

const slides = document.querySelectorAll('.slide');
const progressBar = document.getElementById('progressBar');
const slideCounter = document.getElementById('slideCounter');
const navHint = document.getElementById('navHint');
let current = 0;
let isTransitioning = false;

// ---- Slide Navigation ----

function goToSlide(index, force) {
  if (index < 0 || index >= slides.length) return;
  if (index === current) return;
  if (isTransitioning && !force) return;
  isTransitioning = true;

  const prev = slides[current];
  const next = slides[index];

  // Direction
  if (index > current) {
    prev.classList.remove('active');
    prev.classList.add('exit-up');
  } else {
    prev.classList.remove('active');
  }

  current = index;
  next.classList.remove('exit-up');

  // Small delay so exit animation plays
  requestAnimationFrame(() => {
    next.classList.add('active');
  });

  // Update progress
  const progress = ((current) / (slides.length - 1)) * 100;
  progressBar.style.width = progress + '%';
  slideCounter.textContent = (current + 1) + ' / ' + slides.length;

  // Hide nav hint after first navigation
  if (current > 0) {
    navHint.style.opacity = '0';
  }

  // Trigger slide-specific animations
  setTimeout(() => {
    triggerSlideAnimations(current);
    isTransitioning = false;
  }, 400);
}

function nextSlide() {
  goToSlide(current + 1);
}

function prevSlide() {
  goToSlide(current - 1);
}

// ---- Keyboard Controls ----

document.addEventListener('keydown', (e) => {
  switch(e.key) {
    case 'ArrowRight':
    case ' ':
    case 'Enter':
      e.preventDefault();
      nextSlide();
      break;
    case 'ArrowLeft':
    case 'Backspace':
      e.preventDefault();
      prevSlide();
      break;
    case 'f':
      toggleFullscreen();
      break;
    case '0':
      e.preventDefault();
      goToSlide(0, true);
      break;
  }
});

// ---- Touch Controls ----

let touchStartX = 0;
document.addEventListener('touchstart', (e) => {
  touchStartX = e.touches[0].clientX;
});

document.addEventListener('touchend', (e) => {
  const diff = touchStartX - e.changedTouches[0].clientX;
  if (Math.abs(diff) > 50) {
    if (diff > 0) nextSlide();
    else prevSlide();
  }
});

// ---- Click to advance ----
document.addEventListener('click', (e) => {
  // Don't advance if clicking interactive elements
  if (e.target.closest('code, a, button, kbd')) return;

  const x = e.clientX / window.innerWidth;
  if (x > 0.3) nextSlide();
  else prevSlide();
});

// ---- Fullscreen ----

function toggleFullscreen() {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen().catch(() => {});
  } else {
    document.exitFullscreen();
  }
}

// ---- Slide-Specific Animations ----

function triggerSlideAnimations(index) {
  // Slide 1: Type "claude" in terminal
  if (index === 1) {
    typeText('typedClaude', 'claude', 80);
  }

  // Slide 2: Type the prompt with rainbow "ultrathink"
  if (index === 2) {
    typeTextRainbow('typedPrompt',
      'go and see what the client wants and build it, no mistakes, ultrathink',
      'ultrathink',
      40
    );
  }

  // Slide 4: Counter animation
  if (index === 4) {
    animateCounter();
  }
}

// ---- Title Typewriter (JS-based, no ghost chars) ----

(function() {
  const text = 'Vibecoding just got solved.';
  const el = document.getElementById('titleTypewriter');
  if (!el) return;
  let i = 0;
  function type() {
    if (i <= text.length) {
      el.textContent = text.substring(0, i);
      i++;
      setTimeout(type, 60);
    }
  }
  setTimeout(type, 800);
})();

// ---- Typing Animation ----

// Rainbow colors matching Claude Code's ultrathink style
const RAINBOW_COLORS = [
  '#E8488A', // u - pink
  '#AB51E3', // l - purple
  '#5B8DEF', // t - blue
  '#58D68D', // r - green
  '#F4D03F', // a - yellow
  '#EB984E', // t - orange
  '#E8488A', // h - pink
  '#AB51E3', // i - purple
  '#5B8DEF', // n - blue
  '#58D68D', // k - green
];

let typeTimeout = null;
function typeText(elementId, text, speed) {
  const el = document.getElementById(elementId);
  if (!el) return;
  el.textContent = '';
  let i = 0;

  clearTimeout(typeTimeout);

  function type() {
    if (i < text.length) {
      el.textContent += text.charAt(i);
      i++;
      typeTimeout = setTimeout(type, speed);
    }
  }
  type();
}

function typeTextRainbow(elementId, text, rainbowWord, speed) {
  const el = document.getElementById(elementId);
  if (!el) return;
  el.innerHTML = '';
  let i = 0;
  const rainbowStart = text.lastIndexOf(rainbowWord);

  clearTimeout(typeTimeout);

  function type() {
    if (i < text.length) {
      if (i >= rainbowStart && i < rainbowStart + rainbowWord.length) {
        const span = document.createElement('span');
        span.textContent = text.charAt(i);
        span.style.color = RAINBOW_COLORS[i - rainbowStart];
        span.style.fontWeight = '600';
        el.appendChild(span);
      } else {
        el.appendChild(document.createTextNode(text.charAt(i)));
      }
      i++;
      typeTimeout = setTimeout(type, speed);
    }
  }
  type();
}

// ---- Counter Animation ----

function animateCounter() {
  const counters = document.querySelectorAll('.counter');
  counters.forEach(counter => {
    const target = parseInt(counter.dataset.target);
    const duration = 2000;
    const start = performance.now();

    function update(now) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      // Ease out
      const eased = 1 - Math.pow(1 - progress, 3);
      counter.textContent = Math.round(eased * target);

      if (progress < 1) {
        requestAnimationFrame(update);
      }
    }
    requestAnimationFrame(update);
  });
}

// ---- Init ----

// Set initial state
slideCounter.textContent = '1 / ' + slides.length;

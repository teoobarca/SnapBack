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

function goToSlide(index) {
  if (index < 0 || index >= slides.length || isTransitioning) return;
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
  // Slide 2: Type the prompt
  if (index === 2) {
    typeText('typedPrompt',
      'go and see what the client wants and build it, no mistakes, ultrathink',
      40
    );
  }

  // Slide 4: Counter animation
  if (index === 4) {
    animateCounter();
  }
}

// ---- Typing Animation ----

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

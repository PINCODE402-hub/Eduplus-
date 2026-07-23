// =========================================================
// DANIEL MEMORIAL ACADEMY — SHARED SITE SCRIPT
// =========================================================

document.addEventListener('DOMContentLoaded', () => {
  const yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // ---------- Mobile nav ----------
  const menuToggle = document.getElementById('menu-toggle');
  const navLinks = document.getElementById('nav-links');
  if (menuToggle && navLinks) {
    menuToggle.addEventListener('click', () => {
      navLinks.classList.toggle('open');
      const icon = menuToggle.querySelector('i');
      icon.classList.toggle('fa-bars');
      icon.classList.toggle('fa-xmark');
    });
    navLinks.querySelectorAll('a').forEach(a => a.addEventListener('click', () => {
      navLinks.classList.remove('open');
      const icon = menuToggle.querySelector('i');
      icon.classList.add('fa-bars');
      icon.classList.remove('fa-xmark');
    }));
  }

  // ---------- Nav shadow on scroll ----------
  const nav = document.getElementById('site-nav');
  if (nav) {
    window.addEventListener('scroll', () => {
      nav.classList.toggle('scrolled', window.scrollY > 12);
    }, { passive: true });
  }

  // ---------- Scroll reveal ----------
  const revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && revealEls.length) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });
    revealEls.forEach(el => io.observe(el));
  } else {
    revealEls.forEach(el => el.classList.add('in-view'));
  }

  // ---------- Animated counters ----------
  const counters = document.querySelectorAll('.counter[data-target]');
  if ('IntersectionObserver' in window && counters.length) {
    const countIo = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        const el = entry.target;
        const target = parseFloat(el.dataset.target);
        const suffix = el.dataset.suffix || '';
        const decimals = el.dataset.decimals ? parseInt(el.dataset.decimals) : 0;
        const duration = 1400;
        const start = performance.now();
        function tick(now) {
          const progress = Math.min((now - start) / duration, 1);
          const eased = 1 - Math.pow(1 - progress, 3);
          const value = target * eased;
          el.textContent = decimals ? value.toFixed(decimals) : Math.round(value);
          el.textContent += suffix;
          if (progress < 1) requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
        countIo.unobserve(el);
      });
    }, { threshold: 0.5 });
    counters.forEach(el => countIo.observe(el));
  }

  // ---------- FAQ accordion ----------
  document.querySelectorAll('.faq-item').forEach(item => {
    const q = item.querySelector('.faq-q');
    if (!q) return;
    q.addEventListener('click', () => {
      const wasOpen = item.classList.contains('open');
      item.parentElement.querySelectorAll('.faq-item').forEach(i => i.classList.remove('open'));
      if (!wasOpen) item.classList.add('open');
    });
  });

  // ---------- Gallery filters ----------
  const filters = document.querySelectorAll('.gfilter');
  const gitems = document.querySelectorAll('.gitem');
  filters.forEach(btn => {
    btn.addEventListener('click', () => {
      filters.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const cat = btn.dataset.filter;
      gitems.forEach(item => {
        item.style.display = (cat === 'all' || item.dataset.cat === cat) ? '' : 'none';
      });
    });
  });

  // ---------- Gallery lightbox ----------
  const lightbox = document.getElementById('lightbox');
  if (lightbox) {
    const lbIcon = lightbox.querySelector('.lightbox-media i');
    const lbTitle = lightbox.querySelector('.lightbox-body h4');
    const lbDesc = lightbox.querySelector('.lightbox-body p');
    const lbMedia = lightbox.querySelector('.lightbox-media');
    gitems.forEach(item => {
      item.addEventListener('click', () => {
        lbTitle.textContent = item.dataset.title || '';
        lbDesc.textContent = item.dataset.desc || '';
        lbMedia.className = 'lightbox-media ' + item.className.replace('gitem', '').trim();
        lbMedia.style.background = getComputedStyle(item).background;
        lbIcon.className = item.querySelector('i').className;
        lightbox.classList.add('open');
      });
    });
    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox || e.target.closest('.lightbox-close')) {
        lightbox.classList.remove('open');
      }
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') lightbox.classList.remove('open');
    });
  }

  // ---------- Contact / enquiry forms (mailto handoff) ----------
  document.querySelectorAll('form[data-mailto]').forEach(form => {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      const to = form.dataset.mailto;
      const fields = form.querySelectorAll('input, select, textarea');
      let bodyLines = [];
      let subjectName = '';
      fields.forEach(f => {
        const label = form.querySelector(`label[for="${f.id}"]`);
        const labelText = label ? label.textContent : f.id;
        bodyLines.push(`${labelText}: ${f.value}`);
        if (f.id.includes('name') && !subjectName) subjectName = f.value;
      });
      const subject = form.dataset.subject || 'Website Enquiry';
      const body = bodyLines.join('\n');
      window.location.href = `mailto:${to}?subject=${encodeURIComponent(subject + (subjectName ? ' - ' + subjectName : ''))}&body=${encodeURIComponent(body)}`;
    });
  });
});

// =========================================================
// DANIEL MEMORIAL ACADEMY — UNIFORM 3D VIEWER
// A stylized, non-photorealistic 3D preview built from primitive
// geometry, colored to match the school's uniform scheme.
// =========================================================

(function () {
  const stage = document.getElementById('viewer-stage');
  const loadingEl = document.getElementById('viewer-loading');
  const hintEl = document.getElementById('viewer-hint');

  function showFallback(message) {
    if (loadingEl) {
      loadingEl.innerHTML = `<i class="fas fa-shirt" style="font-size:2rem;color:var(--sea-blue);"></i><span style="max-width:280px;text-align:center;">${message}</span>`;
    }
  }

  if (typeof THREE === 'undefined') {
    showFallback('The 3D preview could not load (your connection may be blocking the 3D library). The uniform details below still apply.');
    return;
  }

  try {
    // ---------- Scene setup ----------
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0xeef6f3);

    const camera = new THREE.PerspectiveCamera(38, stage.clientWidth / stage.clientHeight, 0.1, 100);
    const defaultCamPos = new THREE.Vector3(0, 1.1, 4.6);
    camera.position.copy(defaultCamPos);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(stage.clientWidth, stage.clientHeight);
    stage.appendChild(renderer.domElement);

    // ---------- Lighting ----------
    scene.add(new THREE.AmbientLight(0xffffff, 0.65));
    const keyLight = new THREE.DirectionalLight(0xffffff, 0.85);
    keyLight.position.set(3, 5, 4);
    scene.add(keyLight);
    const fillLight = new THREE.DirectionalLight(0xbfe3e8, 0.35);
    fillLight.position.set(-4, 2, -3);
    scene.add(fillLight);

    // ---------- Ground shadow disc ----------
    const groundGeo = new THREE.CircleGeometry(1.6, 48);
    const groundMat = new THREE.MeshBasicMaterial({ color: 0x0b3f4d, transparent: true, opacity: 0.08 });
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -1.62;
    scene.add(ground);

    // ---------- Texture helpers ----------
    function makeCheckTexture(baseColor, lineColor) {
      const size = 128;
      const canvas = document.createElement('canvas');
      canvas.width = size; canvas.height = size;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = baseColor; ctx.fillRect(0, 0, size, size);
      ctx.strokeStyle = lineColor; ctx.lineWidth = 4;
      const step = size / 4;
      for (let i = 0; i <= 4; i++) {
        ctx.beginPath(); ctx.moveTo(i * step, 0); ctx.lineTo(i * step, size); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(0, i * step); ctx.lineTo(size, i * step); ctx.stroke();
      }
      const tex = new THREE.CanvasTexture(canvas);
      tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
      tex.repeat.set(6, 3);
      return tex;
    }
    function makePleatTexture(baseColor, lineColor) {
      const w = 64, h = 128;
      const canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = baseColor; ctx.fillRect(0, 0, w, h);
      ctx.strokeStyle = lineColor; ctx.lineWidth = 2;
      for (let i = 0; i <= 8; i++) {
        ctx.beginPath(); ctx.moveTo(i * (w / 8), 0); ctx.lineTo(i * (w / 8), h); ctx.stroke();
      }
      const tex = new THREE.CanvasTexture(canvas);
      tex.wrapS = THREE.RepeatWrapping; tex.wrapT = THREE.ClampToEdgeWrapping;
      tex.repeat.set(8, 1);
      return tex;
    }

    const checkTexPrimary = makeCheckTexture('#bfe3e8', '#1e7b8c');
    const solidNavyColor = 0x0b3f4d;
    const skirtTex = makePleatTexture('#c9932c', '#a97a1e');
    const shortsColor = 0xc9932c;

    // ---------- Mannequin group ----------
    const mannequin = new THREE.Group();
    scene.add(mannequin);

    // Display stand (base + pole)
    const standMat = new THREE.MeshStandardMaterial({ color: 0x8a6a45, roughness: 0.7 });
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.46, 0.06, 32), standMat);
    base.position.y = -1.6;
    mannequin.add(base);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.9, 16), standMat);
    pole.position.y = -1.15;
    mannequin.add(pole);

    // Torso (skin-toned dress form)
    const torsoMat = new THREE.MeshStandardMaterial({ color: 0xe3b78f, roughness: 0.85 });
    const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.5, 1.15, 32, 1, true), torsoMat);
    torso.position.y = 0.05;
    mannequin.add(torso);
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.24, 0.22, 20), torsoMat);
    neck.position.y = 0.72;
    mannequin.add(neck);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.22, 24, 24), torsoMat);
    head.position.y = 1.0;
    mannequin.add(head);

    // Shirt (swaps texture/color with level)
    const shirtMat = new THREE.MeshStandardMaterial({ map: checkTexPrimary, roughness: 0.75 });
    const shirt = new THREE.Mesh(new THREE.CylinderGeometry(0.66, 0.55, 0.98, 32, 1, true), shirtMat);
    shirt.position.y = 0.08;
    mannequin.add(shirt);

    // Short sleeve stubs
    const sleeveGeo = new THREE.CylinderGeometry(0.15, 0.14, 0.26, 16, 1, true);
    const sleeveL = new THREE.Mesh(sleeveGeo, shirtMat);
    sleeveL.position.set(-0.72, 0.42, 0); sleeveL.rotation.z = Math.PI / 2.4;
    mannequin.add(sleeveL);
    const sleeveR = new THREE.Mesh(sleeveGeo, shirtMat);
    sleeveR.position.set(0.72, 0.42, 0); sleeveR.rotation.z = -Math.PI / 2.4;
    mannequin.add(sleeveR);

    // Collar
    const collarMat = new THREE.MeshStandardMaterial({ color: 0xfbf3e1, roughness: 0.7 });
    const collar = new THREE.Mesh(new THREE.TorusGeometry(0.24, 0.035, 12, 32), collarMat);
    collar.position.y = 0.58; collar.rotation.x = Math.PI / 2;
    mannequin.add(collar);

    // Tie (JHS only)
    const tieMat = new THREE.MeshStandardMaterial({ color: 0xc9932c, roughness: 0.6 });
    const tie = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.55, 0.02), tieMat);
    tie.position.set(0, 0.28, 0.62);
    tie.visible = false;
    mannequin.add(tie);

    // Bottom wear: shorts (boys) & skirt (girls)
    const shortsMat = new THREE.MeshStandardMaterial({ color: shortsColor, roughness: 0.8 });
    const shorts = new THREE.Mesh(new THREE.CylinderGeometry(0.56, 0.5, 0.5, 32, 1, true), shortsMat);
    shorts.position.y = -0.68;
    mannequin.add(shorts);

    const skirtMat = new THREE.MeshStandardMaterial({ map: skirtTex, roughness: 0.8, side: THREE.DoubleSide });
    const skirt = new THREE.Mesh(new THREE.ConeGeometry(0.78, 0.62, 32, 1, true), skirtMat);
    skirt.position.y = -0.72;
    skirt.visible = false;
    mannequin.add(skirt);

    mannequin.position.y = 0.3;

    // ---------- Controls ----------
    const controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.enablePan = false;
    controls.minDistance = 2.8;
    controls.maxDistance = 6.5;
    controls.minPolarAngle = Math.PI / 4;
    controls.maxPolarAngle = Math.PI / 1.7;
    controls.target.set(0, 0.3, 0);
    controls.autoRotate = false;
    controls.autoRotateSpeed = 2.2;

    // ---------- Resize ----------
    function onResize() {
      const w = stage.clientWidth, h = stage.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    }
    window.addEventListener('resize', onResize);

    // ---------- Render loop ----------
    function animate() {
      requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    }

    // Hide the loading overlay once the first frame is ready
    requestAnimationFrame(() => {
      if (loadingEl) loadingEl.style.display = 'none';
      animate();
      setTimeout(() => { if (hintEl) hintEl.style.opacity = '0'; }, 4000);
    });

    // ---------- UI wiring ----------
    let currentGender = 'boys';
    let currentLevel = 'primary';

    function updateOutfit() {
      shorts.visible = currentGender === 'boys';
      skirt.visible = currentGender === 'girls';
      tie.visible = currentLevel === 'jhs';
      if (currentLevel === 'jhs') {
        shirtMat.map = null;
        shirtMat.color.set(solidNavyColor);
      } else {
        shirtMat.color.set(0xffffff);
        shirtMat.map = checkTexPrimary;
      }
      shirtMat.needsUpdate = true;
    }

    const btnBoys = document.getElementById('btn-boys');
    const btnGirls = document.getElementById('btn-girls');
    const btnPrimary = document.getElementById('btn-primary');
    const btnJhs = document.getElementById('btn-jhs');
    const btnAutorotate = document.getElementById('btn-autorotate');
    const btnReset = document.getElementById('btn-reset');

    btnBoys.addEventListener('click', () => {
      currentGender = 'boys'; btnBoys.classList.add('active'); btnGirls.classList.remove('active'); updateOutfit();
    });
    btnGirls.addEventListener('click', () => {
      currentGender = 'girls'; btnGirls.classList.add('active'); btnBoys.classList.remove('active'); updateOutfit();
    });
    btnPrimary.addEventListener('click', () => {
      currentLevel = 'primary'; btnPrimary.classList.add('active'); btnJhs.classList.remove('active'); updateOutfit();
    });
    btnJhs.addEventListener('click', () => {
      currentLevel = 'jhs'; btnJhs.classList.add('active'); btnPrimary.classList.remove('active'); updateOutfit();
    });
    btnAutorotate.addEventListener('click', () => {
      controls.autoRotate = !controls.autoRotate;
      btnAutorotate.classList.toggle('active', controls.autoRotate);
    });
    btnReset.addEventListener('click', () => {
      camera.position.copy(defaultCamPos);
      controls.target.set(0, 0.3, 0);
      controls.update();
    });

    updateOutfit();
  } catch (err) {
    console.error('Uniform 3D viewer failed to initialize:', err);
    showFallback('The 3D preview hit a snag loading in your browser. The uniform details below still apply.');
  }
})();

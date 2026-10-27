document.addEventListener("DOMContentLoaded", async () => {
  /* =========================================================
     PATIENT FRAMES CATALOG
     ========================================================= */

  const API_BASE = (
    document.body.dataset.api || "https://api.gonzalesvisionclinic.com"
  ).replace(/\/+$/, "");

  const FACE_MODEL_PATH = "./models";

  /* =========================================================
     DOM
     ========================================================= */

  const frameGrid = document.getElementById("frame-grid");
  const frameCount = document.getElementById("frame-count");

  const searchInput = document.getElementById("searchInput");
  const sortSelect = document.getElementById("sortSelect");
  const availabilitySelect = document.getElementById("availabilitySelect");
  const categoryPills = document.getElementById("categoryPills");

  const previewModal = document.getElementById("previewModal");
  const previewModalImg = document.getElementById("previewModalImg");
  const previewModalTitle = document.getElementById("previewModalTitle");
  const previewModalPrice = document.getElementById("previewModalPrice");
  const previewModalDesc = document.getElementById("previewModalDesc");
  const previewTryOnBtn = document.getElementById("previewTryOnBtn");
  const closePreviewBtn = document.getElementById("closePreviewBtn");

  const faceFilterModal = document.getElementById("faceFilterModal");
  const modalContainer = document.getElementById("modal-container");
  const closeVTOBtn = document.getElementById("closeVTOBtn");
  const vtoStatus = document.getElementById("vto-status");

  /* =========================================================
     STATE
     ========================================================= */

  let allFrames = [];
  let filteredFrames = [];

  let selectedCategory = "All";
  let selectedFrame = null;

  let faceModelsReady = false;

  let vtoOpen = false;

  let cameraStream = null;
  let cameraVideo = null;

  let detectionTimer = null;
  let detectionRunning = false;
  let faceDetectionStarted = false;

  let threeScene = null;
  let threeCamera = null;
  let threeRenderer = null;
  let threeLoader = null;

  let frameModel = null;

  /*
   * Base normalized scale of the current GLTF.
   */
  let frameModelNormalizedScale = 1;

  /*
   * Normalized dimensions of the current model.
   */
  let frameModelBaseSize = {
    x: 1,
    y: 1,
    z: 1,
  };

  let animationStarted = false;

  /* =========================================================
     UTILITY
     ========================================================= */

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function cleanApiBase() {
    return API_BASE.replace(/\/+$/, "");
  }

  /* =========================================================
     URL HELPERS
     ========================================================= */

  function isAbsoluteUrl(value) {
    return /^https?:\/\//i.test(String(value || ""));
  }

  function resolveImageUrl(value) {
    if (!value) {
      return "";
    }

    const raw = String(value).trim();

    if (!raw) {
      return "";
    }

    if (isAbsoluteUrl(raw)) {
      return raw;
    }

    return `${cleanApiBase()}/${raw.replace(/^\/+/, "")}`;
  }

  function resolveModelUrl(value) {
    if (!value) {
      return "";
    }

    const raw = String(value).trim();

    if (!raw) {
      return "";
    }

    if (isAbsoluteUrl(raw)) {
      return raw;
    }

    if (
      raw.startsWith("./models/") ||
      raw.startsWith("../patient/models/") ||
      raw.startsWith("/patient/models/")
    ) {
      return raw;
    }

    if (raw.startsWith("models/") || raw.startsWith("/models/")) {
      const filename = raw.replace(/^\/?models\//, "");

      return `./models/${filename}`;
    }

    return `${cleanApiBase()}/${raw.replace(/^\/+/, "")}`;
  }

  /* =========================================================
     STOCK
     ========================================================= */

  function getStockState(frame) {
    const stock = Number(frame?.stock_quantity ?? 0);

    if (stock <= 0) {
      return "out";
    }

    if (stock <= 2) {
      return "low";
    }

    return "available";
  }

  function getAvailabilityLabel(state) {
    if (state === "out") {
      return "Out of Stock";
    }

    if (state === "low") {
      return "Low Stock";
    }

    return "Available";
  }

  /* =========================================================
     TRY-ON AVAILABILITY
     ========================================================= */

  function isTryOnReady(frame) {
    return Boolean(
      frame &&
      frame.model_3d_url &&
      String(frame.conversion_status || "").toLowerCase() === "converted",
    );
  }

  /* =========================================================
     STATUS
     ========================================================= */

  function setVTOStatus(message) {
    if (vtoStatus) {
      vtoStatus.textContent = message;
    }
  }

  /* =========================================================
     CATEGORY PILLS
     ========================================================= */

  function buildCategoryPills() {
    if (!categoryPills) {
      return;
    }

    const categories = [
      ...new Set(
        allFrames
          .map((frame) => String(frame.category || "").trim())
          .filter(Boolean),
      ),
    ].sort((a, b) => a.localeCompare(b));

    categoryPills.innerHTML = `
      <button
        class="pill-btn active"
        type="button"
        data-category="All"
      >
        All Frames
      </button>

      ${categories
        .map(
          (category) => `
            <button
              class="pill-btn"
              type="button"
              data-category="${escapeHtml(category)}"
            >
              ${escapeHtml(category)}
            </button>
          `,
        )
        .join("")}
    `;
  }

  /* =========================================================
     FILTERING
     ========================================================= */

  function applyFilters() {
    const query = String(searchInput?.value || "")
      .trim()
      .toLowerCase();

    const availability = availabilitySelect?.value || "all";

    const sort = sortSelect?.value || "newest";

    const category = String(selectedCategory || "All")
      .trim()
      .toLowerCase();

    filteredFrames = allFrames.filter((frame) => {
      const name = String(frame.name || "").toLowerCase();
      const brand = String(frame.brand || "").toLowerCase();
      const frameCategory = String(frame.category || "").toLowerCase();

      const matchesSearch =
        !query || name.includes(query) || brand.includes(query);

      const matchesCategory =
        category === "all" || frameCategory.includes(category);

      const matchesAvailability =
        availability === "all" || getStockState(frame) === availability;

      return matchesSearch && matchesCategory && matchesAvailability;
    });

    filteredFrames.sort((a, b) => {
      switch (sort) {
        case "name-asc":
          return String(a.name || "").localeCompare(String(b.name || ""));

        case "name-desc":
          return String(b.name || "").localeCompare(String(a.name || ""));

        case "price-low":
          return Number(a.price || 0) - Number(b.price || 0);

        case "price-high":
          return Number(b.price || 0) - Number(a.price || 0);

        case "newest":
        default:
          return Number(b.frame_id || 0) - Number(a.frame_id || 0);
      }
    });

    renderFrameCards(filteredFrames);
  }

  /* =========================================================
     FRAME CARD RENDERING
     ========================================================= */

  function renderFrameCards(frames) {
    if (!frameGrid) {
      return;
    }

    if (frameCount) {
      frameCount.textContent =
        frames.length === 1 ? "1 frame" : `${frames.length} frames`;
    }

    if (!frames.length) {
      frameGrid.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
            >
              <circle cx="11" cy="11" r="7"></circle>
              <path d="m20 20-4-4"></path>
            </svg>
          </div>

          <h3>No frames found</h3>

          <p>
            Try changing your search or filter options.
          </p>
        </div>
      `;

      return;
    }

    frameGrid.innerHTML = "";

    frames.forEach((frame) => {
      const card = document.createElement("article");

      card.className = "frame-card";

      const imageUrl = resolveImageUrl(
        frame.image_2d_url || frame.image_url || "",
      );

      const modelUrl = isTryOnReady(frame)
        ? resolveModelUrl(frame.model_3d_url)
        : "";

      const stockState = getStockState(frame);
      const stockLabel = getAvailabilityLabel(stockState);

      const converted = isTryOnReady(frame);

      card.innerHTML = `
        <div class="frame-img-box">
          <img
            src="${escapeHtml(imageUrl)}"
            alt="${escapeHtml(frame.name || "Eyeglass Frame")}"
          />
        </div>

        <div class="frame-content">

          <div class="frame-topline">

            <h3>
              ${escapeHtml(frame.name || "Unnamed Frame")}
            </h3>

            ${
              converted
                ? `
                  <span class="three-badge">
                    <svg
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.8"
                    >
                      <path
                        d="M12 3 4 7v10l8 4 8-4V7l-8-4Z"
                      ></path>

                      <path d="m4 7 8 4 8-4"></path>

                      <path d="M12 11v10"></path>
                    </svg>

                    3D
                  </span>
                `
                : ""
            }

          </div>

          <p class="frame-meta">
            ${escapeHtml(frame.brand || "Gonzales Vision Clinic")}
            ${frame.category ? ` • ${escapeHtml(frame.category)}` : ""}
          </p>

          <span class="availability ${stockState}">
            ${stockLabel}
          </span>

          <div class="frame-price">
            ₱${Number(frame.price || 0).toLocaleString("en-PH", {
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            })}
          </div>

          <div class="frame-actions">

            <button
              type="button"
              class="view-btn"
              data-action="details"
            >
              View Details
            </button>

            ${
              converted
                ? `
                  <button
                    type="button"
                    class="try-btn try-on-btn"
                    data-action="try-on"
                  >
                    Try On 3D
                  </button>
                `
                : `
                  <button
                    type="button"
                    class="try-btn try-on-btn"
                    disabled
                  >
                    ${
                      String(frame.conversion_status || "").toLowerCase() ===
                      "processing"
                        ? "Converting..."
                        : "2D Only"
                    }
                  </button>
                `
            }

          </div>
        </div>
      `;

      const detailsButton = card.querySelector('[data-action="details"]');

      if (detailsButton) {
        detailsButton.addEventListener("click", () => {
          openPreviewModal(frame);
        });
      }

      const tryButton = card.querySelector('[data-action="try-on"]');

      if (tryButton && converted) {
        tryButton.addEventListener("click", () => {
          startVirtualTryOn(frame, modelUrl);
        });
      }

      frameGrid.appendChild(card);
    });
  }

  /* =========================================================
     PREVIEW MODAL
     ========================================================= */

  function openPreviewModal(frame) {
    if (!previewModal) {
      return;
    }

    selectedFrame = frame;

    const imageUrl = resolveImageUrl(
      frame.image_2d_url || frame.image_url || "",
    );

    const modelUrl = isTryOnReady(frame)
      ? resolveModelUrl(frame.model_3d_url)
      : "";

    if (previewModalImg) {
      previewModalImg.src = imageUrl;
      previewModalImg.alt = frame.name || "Frame preview";
    }

    if (previewModalTitle) {
      previewModalTitle.textContent = frame.name || "Eyeglass Frame";
    }

    if (previewModalPrice) {
      previewModalPrice.textContent = `₱${Number(
        frame.price || 0,
      ).toLocaleString("en-PH", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;
    }

    if (previewModalDesc) {
      previewModalDesc.textContent =
        frame.description ||
        `${frame.brand || "Gonzales Vision Clinic"} ${
          frame.category || "eyewear"
        } frame designed for comfort and everyday use.`;
    }

    if (previewTryOnBtn) {
      if (isTryOnReady(frame) && modelUrl) {
        previewTryOnBtn.disabled = false;

        previewTryOnBtn.textContent = "Try On 3D";

        previewTryOnBtn.onclick = () => {
          closePreviewModal();

          startVirtualTryOn(frame, modelUrl);
        };
      } else {
        previewTryOnBtn.disabled = true;

        previewTryOnBtn.textContent =
          String(frame.conversion_status || "").toLowerCase() === "processing"
            ? "Converting..."
            : "Try-On Unavailable";

        previewTryOnBtn.onclick = null;
      }
    }

    previewModal.style.display = "flex";
  }

  /* =========================================================
     CLOSE PREVIEW
     ========================================================= */

  function closePreviewModal() {
    if (previewModal) {
      previewModal.style.display = "none";
    }
  }

  /* =========================================================
     THREE.JS SETUP
     ========================================================= */

  function initializeThreeJS() {
    if (threeScene && threeCamera && threeRenderer) {
      resizeThreeRenderer();

      return true;
    }

    if (typeof THREE === "undefined") {
      console.error("Three.js is not loaded.");

      setVTOStatus("3D engine failed to load.");

      return false;
    }

    if (typeof THREE.GLTFLoader === "undefined") {
      console.error("GLTFLoader is not loaded.");

      setVTOStatus("3D model loader failed to load.");

      return false;
    }

    if (!modalContainer) {
      console.error("#modal-container was not found.");

      setVTOStatus("Try-On container was not found.");

      return false;
    }

    modalContainer.style.position = "relative";

    modalContainer.style.overflow = "hidden";

    modalContainer.style.width = "100%";

    modalContainer.style.height = "100%";

    modalContainer.style.background = "#07101d";

    threeScene = new THREE.Scene();

    threeCamera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);

    threeCamera.position.set(0, 0, 10);

    threeCamera.lookAt(0, 0, 0);

    const ambientLight = new THREE.AmbientLight(0xffffff, 1.0);

    threeScene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 1.2);

    directionalLight.position.set(1, 1, 2);

    threeScene.add(directionalLight);

    threeRenderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      preserveDrawingBuffer: false,
    });

    threeRenderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    const canvas = threeRenderer.domElement;

    canvas.style.position = "absolute";

    canvas.style.top = "0";
    canvas.style.left = "0";
    canvas.style.right = "0";
    canvas.style.bottom = "0";

    canvas.style.width = "100%";
    canvas.style.height = "100%";

    canvas.style.zIndex = "2";

    canvas.style.pointerEvents = "none";

    canvas.style.display = "block";

    canvas.style.background = "transparent";

    modalContainer.appendChild(canvas);

    threeLoader = new THREE.GLTFLoader();

    resizeThreeRenderer();

    return true;
  }

  /* =========================================================
     RESIZE THREE.JS
     ========================================================= */

  function resizeThreeRenderer() {
    if (!threeRenderer || !threeCamera || !modalContainer) {
      return;
    }

    const width = modalContainer.clientWidth || 640;

    const height = modalContainer.clientHeight || 480;

    threeCamera.aspect = width / height;

    threeCamera.updateProjectionMatrix();

    threeRenderer.setSize(width, height, false);

    threeRenderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    if (cameraVideo) {
      cameraVideo.style.width = "100%";

      cameraVideo.style.height = "100%";
    }
  }

  window.addEventListener("resize", resizeThreeRenderer);

  /* =========================================================
     THREE.JS ANIMATION
     ========================================================= */

  function startThreeAnimation() {
    if (animationStarted) {
      return;
    }

    animationStarted = true;

    function renderLoop() {
      requestAnimationFrame(renderLoop);

      if (threeRenderer && threeScene && threeCamera) {
        threeRenderer.render(threeScene, threeCamera);
      }
    }

    renderLoop();
  }

  /* =========================================================
     REMOVE CURRENT MODEL
     ========================================================= */

  function removeCurrentModel() {
    if (!frameModel || !threeScene) {
      frameModel = null;

      frameModelNormalizedScale = 1;

      frameModelBaseSize = {
        x: 1,
        y: 1,
        z: 1,
      };

      return;
    }

    threeScene.remove(frameModel);

    frameModel.traverse((object) => {
      if (object.geometry) {
        object.geometry.dispose();
      }

      if (object.material) {
        if (Array.isArray(object.material)) {
          object.material.forEach((material) => {
            if (material.map) {
              material.map.dispose();
            }

            material.dispose();
          });
        } else {
          if (object.material.map) {
            object.material.map.dispose();
          }

          object.material.dispose();
        }
      }
    });

    frameModel = null;

    frameModelNormalizedScale = 1;

    frameModelBaseSize = {
      x: 1,
      y: 1,
      z: 1,
    };
  }

  /* =========================================================
     CAMERA VIDEO
     ========================================================= */

  function createCameraVideo() {
    if (!modalContainer) {
      console.error("#modal-container does not exist.");

      return null;
    }

    modalContainer.querySelectorAll(".patient-vto-camera").forEach((video) => {
      try {
        video.pause();
      } catch (_) {}

      try {
        video.srcObject = null;
      } catch (_) {}

      video.remove();
    });

    modalContainer.style.position = "relative";

    modalContainer.style.overflow = "hidden";

    const video = document.createElement("video");

    video.className = "patient-vto-camera";

    video.autoplay = true;
    video.muted = true;
    video.playsInline = true;

    video.setAttribute("autoplay", "");

    video.setAttribute("muted", "");

    video.setAttribute("playsinline", "");

    video.setAttribute("webkit-playsinline", "");

    video.style.position = "absolute";

    video.style.top = "0";
    video.style.left = "0";
    video.style.right = "0";
    video.style.bottom = "0";

    video.style.width = "100%";
    video.style.height = "100%";

    video.style.objectFit = "cover";

    video.style.zIndex = "1";

    video.style.display = "block";

    video.style.visibility = "visible";

    video.style.opacity = "1";

    video.style.backgroundColor = "#07101d";

    /*
     * Mirror the front camera.
     */
    video.style.transform = "scaleX(-1)";

    video.style.pointerEvents = "none";

    modalContainer.prepend(video);

    return video;
  }

  /* =========================================================
     START CAMERA
     ========================================================= */

  async function startCamera() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error("Camera access is not supported by this browser.");
    }

    stopCamera();

    cameraVideo = createCameraVideo();

    if (!cameraVideo) {
      throw new Error("Unable to create camera video element.");
    }

    const constraints = {
      audio: false,

      video: {
        facingMode: {
          ideal: "user",
        },

        width: {
          ideal: 1280,
          min: 640,
        },

        height: {
          ideal: 720,
          min: 480,
        },
      },
    };

    setVTOStatus("Requesting camera access...");

    try {
      cameraStream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (error) {
      console.error("getUserMedia failed:", error);

      throw error;
    }

    cameraVideo.srcObject = cameraStream;

    cameraVideo.style.display = "block";

    cameraVideo.style.visibility = "visible";

    cameraVideo.style.opacity = "1";

    try {
      await cameraVideo.play();
    } catch (error) {
      console.warn("Initial camera play warning:", error);

      await new Promise((resolve) => {
        const retryPlay = async () => {
          try {
            await cameraVideo.play();
          } catch (playError) {
            console.warn("Retry camera play warning:", playError);
          }

          resolve();
        };

        if (cameraVideo.readyState >= 2) {
          retryPlay();
        } else {
          cameraVideo.addEventListener("loadedmetadata", retryPlay, {
            once: true,
          });
        }
      });
    }

    await waitForVideoReady(cameraVideo);

    resizeThreeRenderer();

    setVTOStatus("Camera ready — looking for your face...");

    return cameraVideo;
  }

  /* =========================================================
     WAIT FOR VIDEO
     ========================================================= */

  function waitForVideoReady(video) {
    return new Promise((resolve, reject) => {
      let attempts = 0;

      const check = () => {
        if (
          video.readyState >= 2 &&
          video.videoWidth > 0 &&
          video.videoHeight > 0
        ) {
          resolve();
          return;
        }

        attempts++;

        if (attempts >= 80) {
          reject(new Error("Camera video did not become ready."));

          return;
        }

        setTimeout(check, 100);
      };

      check();
    });
  }

  /* =========================================================
     STOP CAMERA
     ========================================================= */

  function stopCamera() {
    if (detectionTimer) {
      clearTimeout(detectionTimer);

      detectionTimer = null;
    }

    faceDetectionStarted = false;

    detectionRunning = false;

    if (cameraStream) {
      cameraStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (_) {}
      });

      cameraStream = null;
    }

    if (cameraVideo) {
      try {
        cameraVideo.pause();
      } catch (_) {}

      try {
        cameraVideo.srcObject = null;
      } catch (_) {}

      try {
        cameraVideo.remove();
      } catch (_) {}

      cameraVideo = null;
    }

    if (modalContainer) {
      modalContainer
        .querySelectorAll(".patient-vto-camera")
        .forEach((video) => video.remove());
    }
  }

  /* =========================================================
     LOAD GLTF MODEL
     ========================================================= */

  function loadFrameModel(modelUrl) {
    return new Promise((resolve, reject) => {
      if (!threeLoader || !threeScene) {
        reject(new Error("3D engine is not ready."));

        return;
      }

      if (!modelUrl) {
        reject(new Error("3D model URL is empty."));

        return;
      }

      setVTOStatus("Loading 3D frame...");

      threeLoader.load(
        modelUrl,

        (gltf) => {
          removeCurrentModel();

          frameModel = gltf.scene;

          frameModel.scale.set(1, 1, 1);

          /*
           * Keep the model orientation used
           * by the existing catalog.
           */
          frameModel.rotation.set(0, Math.PI, 0);

          frameModel.visible = false;

          /* =================================================
               NORMALIZE MODEL
               ================================================= */

          const boundingBox = new THREE.Box3().setFromObject(frameModel);

          const modelSize = new THREE.Vector3();

          boundingBox.getSize(modelSize);

          const maxDimension = Math.max(modelSize.x, modelSize.y, modelSize.z);

          console.log("Original GLTF dimensions:", {
            x: modelSize.x,
            y: modelSize.y,
            z: modelSize.z,
            maxDimension,
          });

          if (Number.isFinite(maxDimension) && maxDimension > 0) {
            frameModelNormalizedScale = 1 / maxDimension;

            frameModel.scale.set(
              frameModelNormalizedScale,
              frameModelNormalizedScale,
              frameModelNormalizedScale,
            );
          } else {
            frameModelNormalizedScale = 1;
          }

          frameModelBaseSize = {
            x: modelSize.x * frameModelNormalizedScale,

            y: modelSize.y * frameModelNormalizedScale,

            z: modelSize.z * frameModelNormalizedScale,
          };

          console.log("Normalized GLTF dimensions:", frameModelBaseSize);

          threeScene.add(frameModel);

          frameModel.visible = false;

          resolve(frameModel);
        },

        undefined,

        (error) => {
          console.error("3D model loading failed:", error);

          reject(error);
        },
      );
    });
  }

  /* =========================================================
     LANDMARK CENTER
     ========================================================= */

  function getLandmarkCenter(landmarks) {
    if (!landmarks || !landmarks.length) {
      return null;
    }

    let totalX = 0;
    let totalY = 0;

    landmarks.forEach((point) => {
      totalX += point.x;
      totalY += point.y;
    });

    return {
      x: totalX / landmarks.length,

      y: totalY / landmarks.length,
    };
  }

  /* =========================================================
     FACE DETECTION
     ========================================================= */

  async function detectFace() {
    if (!faceModelsReady || !cameraVideo || !frameModel) {
      return;
    }

    if (
      cameraVideo.readyState < 2 ||
      cameraVideo.videoWidth <= 0 ||
      cameraVideo.videoHeight <= 0
    ) {
      return;
    }

    if (detectionRunning) {
      return;
    }

    if (typeof faceapi === "undefined") {
      return;
    }

    detectionRunning = true;

    try {
      const detection = await faceapi
        .detectSingleFace(
          cameraVideo,
          new faceapi.SsdMobilenetv1Options({
            minConfidence: 0.3,
            inputSize: 320,
          }),
        )
        .withFaceLandmarks();

      if (!detection) {
        frameModel.visible = false;

        setVTOStatus("🔴 No face detected");

        return;
      }

      /* =====================================================
         ACTUAL EYE LANDMARKS
         ===================================================== */

      const leftEye = detection.landmarks.getLeftEye();

      const rightEye = detection.landmarks.getRightEye();

      if (!leftEye || !rightEye || !leftEye.length || !rightEye.length) {
        frameModel.visible = false;

        setVTOStatus("🔴 Eyes not detected");

        return;
      }

      /* =====================================================
         EYE CENTERS
         ===================================================== */

      const leftCenter = getLandmarkCenter(leftEye);

      const rightCenter = getLandmarkCenter(rightEye);

      if (!leftCenter || !rightCenter) {
        frameModel.visible = false;

        return;
      }

      const videoWidth = cameraVideo.videoWidth;

      const videoHeight = cameraVideo.videoHeight;

      /* =====================================================
         EXACT MIDPOINT BETWEEN THE EYES
         ===================================================== */

      const eyeCenterX = (leftCenter.x + rightCenter.x) / 2;

      const eyeCenterY = (leftCenter.y + rightCenter.y) / 2;

      /* =====================================================
         NORMALIZE POSITION
         ===================================================== */

      const normalizedX = eyeCenterX / videoWidth;

      const normalizedY = eyeCenterY / videoHeight;

      /*
       * Because the camera image is mirrored,
       * mirror the horizontal coordinate too.
       */

      const mirroredX = 1 - normalizedX;

      /* =====================================================
         THREE.JS POSITION
         ===================================================== */

      const worldX = (mirroredX - 0.5) * 4.5;

      const worldY = -(normalizedY - 0.5) * 3.4;

      /*
       * IMPORTANT:
       *
       * No artificial -0.45 offset.
       *
       * The glasses are placed directly on the
       * midpoint between the detected eyes.
       */

      const worldZ = 1;

      frameModel.position.set(worldX, worldY, worldZ);

      /* =====================================================
         HEAD TILT
         ===================================================== */

      const deltaX = rightCenter.x - leftCenter.x;

      const deltaY = rightCenter.y - leftCenter.y;

      const angle = Math.atan2(deltaY, deltaX);

      frameModel.rotation.z = angle;

      /* =====================================================
         EYE DISTANCE
         ===================================================== */

      const eyeDistance = Math.sqrt(
        Math.pow(rightCenter.x - leftCenter.x, 2) +
          Math.pow(rightCenter.y - leftCenter.y, 2),
      );

      if (!Number.isFinite(eyeDistance) || eyeDistance <= 0) {
        frameModel.visible = false;

        return;
      }

      /* =====================================================
         FRAME SIZE
         ===================================================== */

      const faceWidthRatio = eyeDistance / videoWidth;

      /*
       * Main frame-size control.
       *
       * 2.8 gives a natural glasses width.
       *
       * If you later want:
       *
       * slightly smaller = 2.5
       * current            = 2.8
       * slightly larger = 3.0
       * large = 3.2
       */

      const desiredWorldWidth = faceWidthRatio * 4.5 * 2.8;

      /* =====================================================
         MODEL WIDTH
         ===================================================== */

      /*
       * Some GLTF models may have their horizontal
       * dimension represented by X while others can
       * have a larger Z dimension.
       *
       * Use the larger horizontal dimension.
       */

      const normalizedModelWidth =
        Math.max(frameModelBaseSize.x || 0, frameModelBaseSize.z || 0) || 1;

      let finalScale = desiredWorldWidth / normalizedModelWidth;

      /* =====================================================
         SCALE LIMIT
         ===================================================== */

      /*
       * Old code capped this at 1.5.
       *
       * That could make some frame models
       * unnecessarily small.
       *
       * 3.5 gives enough room for different
       * GLTF models.
       */

      finalScale = Math.max(0.1, Math.min(finalScale, 3.5));

      /* =====================================================
         FINAL SCALE
         ===================================================== */

      const finalModelScale = frameModelNormalizedScale * finalScale;

      if (Number.isFinite(finalModelScale) && finalModelScale > 0) {
        frameModel.scale.set(finalModelScale, finalModelScale, finalModelScale);
      }

      /* =====================================================
         SHOW FRAME
         ===================================================== */

      frameModel.visible = true;

      const score = detection.detection.score;

      setVTOStatus(`🟢 Face detected (${Math.round(score * 100)}%)`);
    } catch (error) {
      console.error("Face detection error:", error);

      if (frameModel) {
        frameModel.visible = false;
      }

      setVTOStatus("Face detection error");
    } finally {
      detectionRunning = false;
    }
  }

  /* =========================================================
     DETECTION LOOP
     ========================================================= */

  async function detectionLoop() {
    if (!faceDetectionStarted) {
      return;
    }

    await detectFace();

    if (!faceDetectionStarted) {
      return;
    }

    detectionTimer = setTimeout(detectionLoop, 100);
  }

  /* =========================================================
     START FACE DETECTION
     ========================================================= */

  function startFaceDetection() {
    if (faceDetectionStarted) {
      return;
    }

    if (!faceModelsReady) {
      console.warn("Face models are not ready.");

      return;
    }

    if (!cameraVideo) {
      console.warn("Camera video is not ready.");

      return;
    }

    faceDetectionStarted = true;

    detectionLoop();
  }

  /* =========================================================
     OPEN VIRTUAL TRY-ON
     ========================================================= */

  async function startVirtualTryOn(frame, modelUrl) {
    if (!frame) {
      return;
    }

    if (!modelUrl) {
      setVTOStatus("This frame does not have a 3D model.");

      return;
    }

    closePreviewModal();

    if (faceFilterModal) {
      faceFilterModal.style.display = "flex";
    }

    vtoOpen = true;

    setVTOStatus("Preparing virtual try-on...");

    stopCamera();

    removeCurrentModel();

    const threeReady = initializeThreeJS();

    if (!threeReady) {
      setVTOStatus("Unable to initialize the 3D Try-On.");

      return;
    }

    resizeThreeRenderer();

    startThreeAnimation();

    /* =======================================================
       START CAMERA
       ======================================================= */

    try {
      await startCamera();
    } catch (error) {
      console.error("Camera error:", error);

      if (frameModel) {
        frameModel.visible = false;
      }

      setVTOStatus(
        `❌ Camera error: ${error.message || "Unable to access camera."}`,
      );

      return;
    }

    /* =======================================================
       LOAD MODEL
       ======================================================= */

    try {
      await loadFrameModel(modelUrl);
    } catch (error) {
      console.error("Model load error:", error);

      stopCamera();

      setVTOStatus("❌ Failed to load the 3D frame model.");

      return;
    }

    /* =======================================================
       START TRACKING
       ======================================================= */

    if (!faceModelsReady) {
      setVTOStatus("Face detection models are still loading...");

      return;
    }

    startFaceDetection();

    setVTOStatus("Camera ready — looking for your face...");
  }

  /* =========================================================
     EXTERNAL GLTF API
     ========================================================= */

  window.loadGLTFModel = function (modelUrl) {
    const frame = selectedFrame || {
      name: "Frame",
    };

    startVirtualTryOn(frame, resolveModelUrl(modelUrl));
  };

  /* =========================================================
     CLOSE VIRTUAL TRY-ON
     ========================================================= */

  function closeVirtualTryOn() {
    vtoOpen = false;

    faceDetectionStarted = false;

    if (detectionTimer) {
      clearTimeout(detectionTimer);

      detectionTimer = null;
    }

    detectionRunning = false;

    stopCamera();

    removeCurrentModel();

    if (faceFilterModal) {
      faceFilterModal.style.display = "none";
    }

    setVTOStatus("Preparing virtual try-on...");
  }

  window.closeVirtualTryOn = closeVirtualTryOn;

  /* =========================================================
     CLOSE BUTTON
     ========================================================= */

  if (closeVTOBtn) {
    closeVTOBtn.addEventListener("click", closeVirtualTryOn);
  }

  /* =========================================================
     CLICK OUTSIDE TRY-ON
     ========================================================= */

  if (faceFilterModal) {
    faceFilterModal.addEventListener("click", (event) => {
      if (event.target === faceFilterModal) {
        closeVirtualTryOn();
      }
    });
  }

  /* =========================================================
     CLOSE PREVIEW
     ========================================================= */

  if (closePreviewBtn) {
    closePreviewBtn.addEventListener("click", closePreviewModal);
  }

  if (previewModal) {
    previewModal.addEventListener("click", (event) => {
      if (event.target === previewModal) {
        closePreviewModal();
      }
    });
  }

  /* =========================================================
     ESCAPE
     ========================================================= */

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }

    closePreviewModal();

    if (vtoOpen) {
      closeVirtualTryOn();
    }
  });

  /* =========================================================
     SEARCH
     ========================================================= */

  if (searchInput) {
    searchInput.addEventListener("input", applyFilters);
  }

  /* =========================================================
     SORT
     ========================================================= */

  if (sortSelect) {
    sortSelect.addEventListener("change", applyFilters);
  }

  /* =========================================================
     AVAILABILITY
     ========================================================= */

  if (availabilitySelect) {
    availabilitySelect.addEventListener("change", applyFilters);
  }

  /* =========================================================
     CATEGORY
     ========================================================= */

  if (categoryPills) {
    categoryPills.addEventListener("click", (event) => {
      const button = event.target.closest(".pill-btn");

      if (!button) {
        return;
      }

      categoryPills.querySelectorAll(".pill-btn").forEach((item) => {
        item.classList.remove("active");
      });

      button.classList.add("active");

      selectedCategory = button.dataset.category || "All";

      applyFilters();
    });
  }

  /* =========================================================
     LOAD FRAMES
     ========================================================= */

  async function loadFrames() {
    try {
      if (frameCount) {
        frameCount.textContent = "Loading frames...";
      }

      const response = await fetch(`${cleanApiBase()}/api/frames`, {
        cache: "no-store",
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const data = await response.json();

      allFrames = Array.isArray(data) ? data : [];

      buildCategoryPills();

      applyFilters();
    } catch (error) {
      console.error("Frames catalog error:", error);

      if (frameCount) {
        frameCount.textContent = "Catalog unavailable";
      }

      if (frameGrid) {
        frameGrid.innerHTML = `
        <div class="empty-state">

          <div class="empty-icon">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
            >
              <path d="M12 9v4"></path>

              <path d="M12 17h.01"></path>

              <path
                d="M10.3 3.6 2.9 17a2 2 0 0 0 1.75 3h14.7a2 2 0 0 0 1.75-3L13.7 3.6a2 2 0 0 0-3.4 0Z"
              ></path>
            </svg>
          </div>

          <h3>
            Unable to load frames
          </h3>

          <p>
            We couldn't connect to the clinic frame catalog.
            Please refresh the page and try again.
          </p>

        </div>
        `;
      }
    }
  }

  /* =========================================================
     FACE-API INITIALIZATION
     ========================================================= */

  async function initFaceDetection() {
    if (typeof faceapi === "undefined") {
      console.error("face-api.js is not loaded.");

      setVTOStatus("Face detection library failed to load.");

      return false;
    }

    try {
      setVTOStatus("Loading face detection models...");

      await Promise.all([
        faceapi.nets.ssdMobilenetv1.loadFromUri(FACE_MODEL_PATH),

        faceapi.nets.faceLandmark68Net.loadFromUri(FACE_MODEL_PATH),
      ]);

      faceModelsReady = true;

      console.log("Patient face-api models loaded.");

      setVTOStatus("Ready — select a frame to try it on.");

      return true;
    } catch (error) {
      faceModelsReady = false;

      console.error("Face-api model loading failed:", error);

      setVTOStatus("Failed to load face detection models.");

      return false;
    }
  }

  /* =========================================================
     THEME BRIDGE
     ========================================================= */

  function applyTheme(theme) {
    document.body.classList.toggle("dark", theme === "dark");
  }

  window.addEventListener("message", (event) => {
    const data = event.data || {};

    if (data.type === "patientPortalTheme" || data.type === "theme-change") {
      applyTheme(data.theme);
    }
  });

  /* =========================================================
     LOCAL THEME
     ========================================================= */

  try {
    const savedTheme = localStorage.getItem("patientPortalTheme");

    if (savedTheme) {
      applyTheme(savedTheme);
    }
  } catch (_) {}

  /* =========================================================
     PARENT DASHBOARD THEME
     ========================================================= */

  try {
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(
        {
          type: "requestPatientPortalTheme",
        },
        "*",
      );

      try {
        const parentDark =
          window.parent.document.body.classList.contains("dark");

        applyTheme(parentDark ? "dark" : "light");
      } catch (_) {}
    }
  } catch (_) {}

  /* =========================================================
     MOBILE TRY-ON SUPPORT
     ========================================================= */

  const urlParams = new URLSearchParams(window.location.search);

  const targetFrameId = urlParams.get("frameId");

  const mobileTryOn = urlParams.get("mobileTryOn") === "true";

  if (mobileTryOn) {
    document.body.dataset.mobileTryOn = "true";

    window.addEventListener("message", (event) => {
      if (event.source === window.parent && event.data === "close-try-on") {
        closeVirtualTryOn();
      }
    });
  }

  async function openMobileTryOn() {
    if (!mobileTryOn || !targetFrameId) {
      return;
    }

    const numericId = Number(targetFrameId);

    if (!Number.isFinite(numericId)) {
      return;
    }

    if (!allFrames.length) {
      await loadFrames();
    }

    const frame = allFrames.find((item) => Number(item.frame_id) === numericId);

    if (!frame) {
      if (faceFilterModal) {
        faceFilterModal.style.display = "flex";
      }

      setVTOStatus("Frame could not be found.");

      return;
    }

    if (!isTryOnReady(frame)) {
      if (faceFilterModal) {
        faceFilterModal.style.display = "flex";
      }

      setVTOStatus("This frame is not ready for 3D Try-On.");

      return;
    }

    const modelUrl = resolveModelUrl(frame.model_3d_url);

    selectedFrame = frame;

    await startVirtualTryOn(frame, modelUrl);
  }

  /* =========================================================
     INITIAL LOAD
     ========================================================= */

  await loadFrames();

  await initFaceDetection();

  if (mobileTryOn && targetFrameId) {
    await openMobileTryOn();
  }
});

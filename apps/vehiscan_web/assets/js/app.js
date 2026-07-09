// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/vehiscan_web"
import topbar from "../vendor/topbar"

const Hooks = {
  LeafletMap: {
    mounted() {
      const el = this.el;
      const lat = parseFloat(el.dataset.lat || "-12.046374");
      const lng = parseFloat(el.dataset.lng || "-77.042793");
      const zoom = parseInt(el.dataset.zoom || "13");
      
      this.map = L.map(el).setView([lat, lng], zoom);
      
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
      }).addTo(this.map);
      
      this.markers = {};
      
      if (el.dataset.cameras) {
        try {
          const cameras = JSON.parse(el.dataset.cameras);
          cameras.forEach(cam => {
            this.addCameraMarker(cam);
          });
        } catch (e) {
          console.error("Error parsing cameras dataset:", e);
        }
      }
      
      this.handleEvent("new-capture", ({latitude, longitude, plate, camera_code, location_name}) => {
        if (latitude && longitude) {
          const marker = L.marker([latitude, longitude], {
            icon: L.icon({
              iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png',
              shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
              iconSize: [25, 41],
              iconAnchor: [12, 41],
              popupAnchor: [1, -34],
              shadowSize: [41, 41]
            })
          }).addTo(this.map);
          
          marker.bindPopup(`<b>${plate}</b><br/>Cámara: ${camera_code}<br/>${location_name}`).openPopup();
          this.map.panTo([latitude, longitude]);
          
          setTimeout(() => {
            this.map.removeLayer(marker);
          }, 15000);
        }
      });

      this.handleEvent("load-markers", ({markers}) => {
        if (this.tempMarkers) {
          this.tempMarkers.forEach(m => this.map.removeLayer(m));
        }
        this.tempMarkers = [];
        
        if (markers && markers.length > 0) {
          markers.forEach(markerData => {
            const marker = L.marker([markerData.latitude, markerData.longitude], {
              icon: L.icon({
                iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-blue.png',
                shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
                iconSize: [25, 41],
                iconAnchor: [12, 41],
                popupAnchor: [1, -34],
                shadowSize: [41, 41]
              })
            }).addTo(this.map);
            
            marker.bindPopup(`<b>${markerData.plate}</b><br/>Cámara: ${markerData.camera_code}<br/>${markerData.location_name}`);
            this.tempMarkers.push(marker);
          });
          
          try {
            const group = new L.featureGroup(this.tempMarkers);
            this.map.fitBounds(group.getBounds().pad(0.1));
          } catch (e) {
            console.error(e);
          }
        }
      });
    },

    addCameraMarker(cam) {
      if (cam.latitude && cam.longitude) {
        const color = cam.status === 'active' ? 'green' : 'orange';
        const marker = L.marker([cam.latitude, cam.longitude], {
          icon: L.icon({
            iconUrl: `https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-${color}.png`,
            shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
          })
        }).addTo(this.map);
        
        marker.bindPopup(`<b>Cámara: ${cam.code}</b><br/>Ubicación: ${cam.location_name}<br/>Estado: ${cam.status}`);
        this.markers[cam.code] = marker;
      }
    }
  },
  WebcamDetector: {
    mounted() {
      this.detectWebcams();
    },
    updated() {
      this.detectWebcams();
    },
    detectWebcams() {
      if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
      
      const triggerDetection = () => {
        navigator.mediaDevices.enumerateDevices()
          .then(devices => {
            const videoDevices = devices.filter(d => d.kind === "videoinput");
            const formatted = videoDevices.map((device, index) => ({
              index: index.toString(),
              label: device.label || `Cámara de Equipo ${index + 1}`
            }));
            this.pushEvent("webcams-detected", {devices: formatted});
          })
          .catch(err => console.error("Error enumerando cámaras:", err));
      };

      // Request permission if labels are empty
      navigator.mediaDevices.enumerateDevices().then(devices => {
        const hasLabels = devices.some(d => d.kind === "videoinput" && d.label);
        if (!hasLabels && navigator.mediaDevices.getUserMedia) {
          navigator.mediaDevices.getUserMedia({video: true})
            .then(stream => {
              stream.getTracks().forEach(track => track.stop());
              triggerDetection();
            })
            .catch(() => triggerDetection());
        } else {
          triggerDetection();
        }
      });
    }
  },
  CameraConfigMap: {
    mounted() {
      this.loadLeaflet().then(() => {
        this.initMap();
      });
    },
    updated() {
      if (this.map && this.marker) {
        const lat = parseFloat(document.getElementById("camera-lat-input")?.value);
        const lng = parseFloat(document.getElementById("camera-lng-input")?.value);
        if (!isNaN(lat) && !isNaN(lng)) {
          this.marker.setLatLng([lat, lng]);
          this.map.panTo([lat, lng]);
        }
      }
    },
    loadLeaflet() {
      if (window.L) {
        return Promise.resolve();
      }
      
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      link.crossOrigin = "";
      document.head.appendChild(link);

      return new Promise((resolve) => {
        const script = document.createElement("script");
        script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
        script.crossOrigin = "";
        script.onload = () => resolve();
        document.head.appendChild(script);
      });
    },
    initMap() {
      const latEl = document.getElementById("camera-lat-input");
      const lngEl = document.getElementById("camera-lng-input");
      
      let initialLat = parseFloat(latEl?.value) || -12.046374; 
      let initialLng = parseFloat(lngEl?.value) || -77.042793;
      
      this.map = L.map(this.el).setView([initialLat, initialLng], 13);
      
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
      }).addTo(this.map);
      
      this.marker = L.marker([initialLat, initialLng], {draggable: true}).addTo(this.map);
      
      const updateInputs = (lat, lng) => {
        if (latEl && lngEl) {
          latEl.value = lat.toFixed(6);
          lngEl.value = lng.toFixed(6);
          latEl.dispatchEvent(new Event("input", {bubbles: true}));
          lngEl.dispatchEvent(new Event("input", {bubbles: true}));
        }
      };

      const reverseGeocode = (lat, lng) => {
        const locEl = document.getElementById("camera-location-input");
        if (locEl) {
          // Add a temporary loading text or search indicator
          locEl.placeholder = "Obteniendo dirección física...";
        }
        fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18`, {
          headers: {
            "Accept-Language": "es"
          }
        })
          .then(resp => resp.json())
          .then(data => {
            if (data && data.display_name && locEl) {
              locEl.value = data.display_name;
              locEl.dispatchEvent(new Event("input", {bubbles: true}));
            }
          })
          .catch(err => {
            console.error("Error al obtener dirección física:", err);
            if (locEl) {
              locEl.placeholder = "Ej. Av. Arequipa cdra. 12 con Cl. Risso";
            }
          });
      };

      this.marker.on("dragend", () => {
        const position = this.marker.getLatLng();
        updateInputs(position.lat, position.lng);
        reverseGeocode(position.lat, position.lng);
      });

      this.map.on("click", (e) => {
        const {lat, lng} = e.latlng;
        this.marker.setLatLng([lat, lng]);
        updateInputs(lat, lng);
        reverseGeocode(lat, lng);
      });

      const locBtn = document.getElementById("use-my-location-btn");
      if (locBtn) {
        locBtn.addEventListener("click", () => {
          if (navigator.geolocation) {
            locBtn.disabled = true;
            locBtn.textContent = "Obteniendo ubicación...";
            navigator.geolocation.getCurrentPosition(
              (position) => {
                const {latitude, longitude} = position.coords;
                this.map.setView([latitude, longitude], 15);
                this.marker.setLatLng([latitude, longitude]);
                updateInputs(latitude, longitude);
                reverseGeocode(latitude, longitude);
                locBtn.disabled = false;
                locBtn.innerHTML = '<svg class="w-3.5 h-3.5 mr-1 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"></path></svg> Usar mi ubicación actual';
              },
              (error) => {
                console.error(error);
                alert("No se pudo obtener la ubicación: " + error.message);
                locBtn.disabled = false;
                locBtn.innerHTML = '<svg class="w-3.5 h-3.5 mr-1 inline-block" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"></path></svg> Usar mi ubicación actual';
              }
            );
          } else {
            alert("Su navegador no soporta geolocalización.");
          }
        });
      }
    }
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

// Play synthetic high-tech threat alarm sound using Web Audio API
window.addEventListener("phx:play-threat-alarm", (e) => {
  try {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const playBeep = (time, freq, type = "sawtooth") => {
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      
      osc.type = type;
      osc.frequency.setValueAtTime(freq, time);
      
      gain.gain.setValueAtTime(0, time);
      gain.gain.linearRampToValueAtTime(0.2, time + 0.05);
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.25);
      
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      
      osc.start(time);
      osc.stop(time + 0.3);
    };
    
    const now = audioCtx.currentTime;
    playBeep(now, 880);
    playBeep(now + 0.15, 880);
    playBeep(now + 0.3, 1000);
    playBeep(now + 0.45, 1000);
  } catch (err) {
    console.warn("Failed to play Web Audio threat alarm:", err);
  }
});


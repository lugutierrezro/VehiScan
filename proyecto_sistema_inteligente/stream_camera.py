#!/usr/bin/env python3
"""
VehiScan MJPEG Streamer con detección de placas en tiempo real.

Flujo de datos:
  stdout → frames MJPEG (el navegador los muestra como video en vivo)
  stderr → líneas JSON de placas detectadas (el StreamController las parsea y guarda en BD)
"""
import sys
import os
import cv2
import time
import json
import re
import threading
import numpy as np

# Configure binary mode for stdout on Windows to prevent OSError: [Errno 22] Invalid argument
if os.name == 'nt':
    import msvcrt
    try:
        msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)
    except Exception as e:
        sys.stderr.write(f"WARNING: Failed to set stdout to binary mode: {e}\n")

# ─── Configuración ────────────────────────────────────────────────────────────

# Mínima confianza OCR para considerar una placa válida
OCR_CONFIDENCE_THRESHOLD = 0.45

# Intervalo mínimo (segundos) entre reportes de la misma placa, para evitar spam
PLATE_COOLDOWN_SECONDS = 5.0

# Número de frames entre cada intento de OCR por track_id
OCR_EVERY_N_FRAMES = 8

# Tiempo que dura la animación de captura en el frame (segundos)
CAPTURE_OVERLAY_DURATION = 3.0


# ─── Hilo de Captura de Video ─────────────────────────────────────────────────

class VideoStream:
    """
    Lee frames de cv2.VideoCapture en un hilo daemon para siempre tener el frame más fresco.
    """
    def __init__(self, src):
        self.cap = cv2.VideoCapture(src)
        self.ret = False
        self.frame = None
        self.stopped = False
        self.lock = threading.Lock()

    def start(self):
        t = threading.Thread(target=self.update, daemon=True)
        t.start()
        return self

    def update(self):
        while not self.stopped:
            if not self.cap.isOpened():
                break
            ret, frame = self.cap.read()
            if not ret:
                self.stopped = True
                break
            with self.lock:
                self.ret = ret
                self.frame = frame
            time.sleep(0.005)

    def read(self):
        with self.lock:
            if self.frame is None:
                return False, None
            return self.ret, self.frame.copy()

    def isOpened(self):
        return self.cap.isOpened()

    def get(self, propId):
        return self.cap.get(propId)

    def release(self):
        self.stopped = True
        self.cap.release()


# ─── Hilo YOLO Tracker ────────────────────────────────────────────────────────

class YOLOTrackerThread(threading.Thread):
    """
    Ejecuta YOLOv8 tracking en un hilo separado para no bloquear el streaming.
    Cada detección incluye el recorte del vehículo para que el OCR lo procese.
    """
    def __init__(self, model, device):
        super().__init__(daemon=True)
        self.model = model
        self.device = device
        self.frame = None
        self.boxes = []          # lista de (cls_name, track_id, xyxy, conf)
        self.crops = {}          # track_id → (crop_img, cls_name, conf)
        self.stopped = False
        self.lock = threading.Lock()
        self.event = threading.Event()
        self.frame_count = 0

    def update_frame(self, frame):
        with self.lock:
            self.frame = frame.copy()
        self.event.set()

    def get_boxes(self):
        with self.lock:
            return list(self.boxes)

    def get_and_clear_crops(self):
        with self.lock:
            crops = dict(self.crops)
            self.crops = {}
            return crops

    def stop(self):
        self.stopped = True
        self.event.set()

    def run(self):
        while not self.stopped:
            self.event.wait(timeout=0.1)
            if self.stopped:
                break

            frame_to_process = None
            with self.lock:
                if self.frame is not None:
                    frame_to_process = self.frame.copy()
            self.event.clear()

            if frame_to_process is None:
                continue

            self.frame_count += 1
            try:
                results = self.model.track(
                    frame_to_process,
                    persist=True,
                    classes=[2, 3, 5, 7],   # car, motorcycle, bus, truck
                    verbose=False,
                    imgsz=320,
                    device=self.device
                )

                new_boxes = []
                h, w = frame_to_process.shape[:2]

                if results and results[0].boxes is not None:
                    boxes = results[0].boxes
                    for box in boxes:
                        cls_idx = int(box.cls[0].item())
                        cls_name = self.model.names[cls_idx]
                        track_id = int(box.id[0].item()) if box.id is not None else None
                        xyxy = box.xyxy[0].cpu().numpy()
                        conf = float(box.conf[0].item())
                        new_boxes.append((cls_name, track_id, xyxy, conf))

                        # Guardar recorte del vehículo cada N frames para OCR
                        if track_id is not None and (self.frame_count % OCR_EVERY_N_FRAMES == 0):
                            x1, y1, x2, y2 = map(int, xyxy)
                            # Añadir un pequeño padding
                            pad = 10
                            x1 = max(0, x1 - pad)
                            y1 = max(0, y1 - pad)
                            x2 = min(w, x2 + pad)
                            y2 = min(h, y2 + pad)
                            crop = frame_to_process[y1:y2, x1:x2]
                            if crop.size > 0:
                                with self.lock:
                                    self.crops[track_id] = (crop.copy(), cls_name, conf)

                with self.lock:
                    self.boxes = new_boxes
            except Exception:
                pass


# ─── Hilo OCR de Placas ───────────────────────────────────────────────────────

class LicensePlateOCRThread(threading.Thread):
    """
    Recibe recortes de vehículos y les aplica EasyOCR para leer la placa.
    Cuando detecta una placa válida, la emite como JSON por stderr.
    """
    def __init__(self, camera_id: str):
        super().__init__(daemon=True)
        self.camera_id = camera_id
        self.queue = []          # lista de (track_id, crop, cls_name, conf)
        self.lock = threading.Lock()
        self.event = threading.Event()
        self.stopped = False
        self.crop_counter = 0

        # Cooldown: placa → timestamp del último reporte
        self.reported_plates = {}

        # Última placa detectada para mostrar overlay en el video
        self.last_capture = None   # (plate_text, conf, timestamp)
        self.last_capture_lock = threading.Lock()

        # Inicializar EasyOCR en segundo plano
        self.reader = None
        self._init_thread = threading.Thread(target=self._init_ocr, daemon=True)
        self._init_thread.start()

    def _init_ocr(self):
        try:
            import easyocr
            self.reader = easyocr.Reader(['es', 'en'], gpu=False, verbose=False)
            print("OCR: EasyOCR inicializado correctamente", file=sys.stderr, flush=True)
        except Exception as e:
            print(f"OCR: No se pudo inicializar EasyOCR: {e}", file=sys.stderr, flush=True)

    def enqueue(self, track_id: int, crop, cls_name: str, conf: float):
        with self.lock:
            # Reemplazar si ya existe el mismo track_id para procesar siempre el más reciente
            self.queue = [(t, c, n, f) for t, c, n, f in self.queue if t != track_id]
            self.queue.append((track_id, crop, cls_name, conf))
        self.event.set()

    def get_last_capture(self):
        with self.last_capture_lock:
            return self.last_capture

    def stop(self):
        self.stopped = True
        self.event.set()

    def run(self):
        while not self.stopped:
            self.event.wait(timeout=0.2)
            if self.stopped:
                break

            if self.reader is None:
                self.event.clear()
                continue

            item = None
            with self.lock:
                if self.queue:
                    item = self.queue.pop(0)
            self.event.clear()

            if item is None:
                continue

            track_id, crop, cls_name, vehicle_conf = item
            self._process_crop(track_id, crop, cls_name, vehicle_conf)

    def _estimate_color(self, crop):
        if crop is None or crop.size == 0:
            return "unknown"
        try:
            img = cv2.resize(crop, (100, 100))
            hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            colors = {
                "red": (np.array([0, 50, 50]), np.array([10, 255, 255])),
                "red2": (np.array([170, 50, 50]), np.array([180, 255, 255])),
                "green": (np.array([35, 50, 50]), np.array([85, 255, 255])),
                "blue": (np.array([90, 50, 50]), np.array([130, 255, 255])),
                "yellow": (np.array([15, 50, 50]), np.array([35, 255, 255])),
                "white": (np.array([0, 0, 200]), np.array([180, 40, 255])),
                "black": (np.array([0, 0, 0]), np.array([180, 255, 50])),
                "gray": (np.array([0, 0, 50]), np.array([180, 50, 199]))
            }
            color_counts = {}
            for color_name, (lower, upper) in colors.items():
                mask = cv2.inRange(hsv, lower, upper)
                count = np.sum(mask > 0)
                if color_name == "red2":
                    color_counts["red"] = color_counts.get("red", 0) + count
                else:
                    color_counts[color_name] = count
            dominant = max(color_counts, key=color_counts.get)
            if color_counts[dominant] < 100:
                return "silver"
            return dominant
        except Exception as e:
            print(f"Error estimating color: {e}", file=sys.stderr, flush=True)
            return "unknown"

    def _process_crop(self, track_id, crop, cls_name, vehicle_conf):
        try:
            # Pre-procesamiento para mejorar OCR en placas pequeñas
            # Escalar si el recorte es muy pequeño
            h, w = crop.shape[:2]
            if w < 200:
                scale = 200.0 / w
                crop = cv2.resize(crop, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

            # Convertir a escala de grises y mejorar contraste
            gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            gray = cv2.equalizeHist(gray)

            # Ejecutar OCR
            results = self.reader.readtext(gray, detail=1)

            best_plate = ""
            best_conf = 0.0

            for (bbox, text, prob) in results:
                # Limpiar texto: solo alfanumérico, mayúsculas
                cleaned = re.sub(r'[^a-zA-Z0-9]', '', text).upper()

                # Heurística: placa tiene entre 4 y 8 caracteres
                if 4 <= len(cleaned) <= 8 and prob > best_conf:
                    best_plate = cleaned
                    best_conf = float(prob)

            # Si no hay candidato principal, tomar cualquier texto de >= 3 chars
            if not best_plate and results:
                for (bbox, text, prob) in sorted(results, key=lambda x: -x[2]):
                    cleaned = re.sub(r'[^a-zA-Z0-9]', '', text).upper()
                    if len(cleaned) >= 3:
                        best_plate = cleaned
                        best_conf = float(prob)
                        break

            if best_plate:
                if best_conf >= OCR_CONFIDENCE_THRESHOLD:
                    self._report_plate(best_plate, best_conf, cls_name, vehicle_conf, crop, track_id)
                else:
                    print(f"OCR: Candidata '{best_plate}' descartada por baja confianza ({best_conf*100:.1f}% < {OCR_CONFIDENCE_THRESHOLD*100:.1f}%)",
                          file=sys.stderr, flush=True)

        except Exception as e:
            print(f"OCR error: {e}", file=sys.stderr, flush=True)

    def _report_plate(self, plate: str, ocr_conf: float, cls_name: str, vehicle_conf: float, crop=None, track_id=0):
        now = time.time()
        last = self.reported_plates.get(plate, 0)

        if now - last < PLATE_COOLDOWN_SECONDS:
            return

        self.reported_plates[plate] = now

        # Actualizar el último capturado para el overlay visual
        with self.last_capture_lock:
            self.last_capture = (plate, ocr_conf, now)

        # Determinar color
        vehicle_color = "unknown"
        if crop is not None:
            vehicle_color = self._estimate_color(crop)

        # Guardar recorte si existe
        crop_filename = ""
        if crop is not None:
            try:
                self.crop_counter = (self.crop_counter + 1) % 1000000
                crop_filename = f"vehicle_{track_id}_frame_{self.crop_counter}.jpg"
                script_dir = os.path.dirname(os.path.abspath(__file__))
                crops_dir = os.path.join(script_dir, "data", "02_intermediate", "crops")
                os.makedirs(crops_dir, exist_ok=True)
                full_path = os.path.join(crops_dir, crop_filename)
                cv2.imwrite(full_path, crop)
            except Exception as e:
                print(f"Error al guardar recorte de vehículo: {e}", file=sys.stderr, flush=True)

        # Notificar al servidor Phoenix via HTTP POST
        event = {
            "plate": plate,
            "confidence": round(ocr_conf * 100, 1),
            "vehicle_class": cls_name,
            "camera_id": self.camera_id,
            "vehicle_color": vehicle_color,
            "crop_filename": crop_filename
        }

        threading.Thread(
            target=self._post_to_phoenix,
            args=(event,),
            daemon=True
        ).start()

    def _post_to_phoenix(self, event: dict):
        """Envía la detección al servidor Phoenix en un hilo separado para no bloquear el OCR."""
        try:
            import urllib.request, urllib.error
            api_url = os.environ.get("VEHISCAN_API_URL", "http://127.0.0.1:4000")
            data = json.dumps(event).encode('utf-8')
            req = urllib.request.Request(
                f"{api_url}/api/plate_event",
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "X-Internal-Token": "vehiscan_stream_internal_2024"
                },
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                body = resp.read().decode()
                print(f"OCR POST OK: {event['plate']} ({event['confidence']}%) → {body}",
                      file=sys.stderr, flush=True)
        except Exception as e:
            print(f"OCR POST ERROR ({event['plate']}): {e}", file=sys.stderr, flush=True)


# ─── Funciones de Dibujo ──────────────────────────────────────────────────────

def draw_vehicle_boxes(frame, boxes, plate_tracks: set):
    """Dibuja bounding boxes de vehículos. Verde normal, naranja si tiene placa detectada."""
    for cls_name, track_id, xyxy, conf in boxes:
        x1, y1, x2, y2 = map(int, xyxy)
        has_plate = track_id in plate_tracks

        color = (0, 165, 255) if has_plate else (0, 220, 0)  # Naranja o Verde
        thickness = 3 if has_plate else 2

        cv2.rectangle(frame, (x1, y1), (x2, y2), color, thickness)

        if track_id is not None:
            label = f"{cls_name.upper()} #{track_id}"
        else:
            label = cls_name.upper()

        # Fondo del label
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2)
        cv2.rectangle(frame, (x1, y1 - th - 10), (x1 + tw + 6, y1), color, -1)
        cv2.putText(frame, label, (x1 + 3, y1 - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 2, cv2.LINE_AA)


def draw_capture_overlay(frame, last_capture):
    """
    Muestra una animación de captura de placa sobre el frame cuando se detecta una.
    Efecto: caja parpadeante en esquina superior derecha con la placa.
    """
    if last_capture is None:
        return frame

    plate, conf, ts = last_capture
    elapsed = time.time() - ts

    if elapsed > CAPTURE_OVERLAY_DURATION:
        return frame

    h, w = frame.shape[:2]

    # Efecto de opacidad: empieza opaco, va desvaneciendo
    alpha = max(0.0, 1.0 - (elapsed / CAPTURE_OVERLAY_DURATION))

    # Parpadeo en el primer segundo
    if elapsed < 1.0:
        blink_rate = 6  # veces por segundo
        if int(elapsed * blink_rate) % 2 == 1:
            alpha *= 0.3

    # Panel de captura
    panel_w, panel_h = 320, 90
    px = w - panel_w - 20
    py = 70

    overlay = frame.copy()
    cv2.rectangle(overlay, (px - 5, py - 5), (px + panel_w + 5, py + panel_h + 5),
                  (0, 0, 0), -1)
    cv2.rectangle(overlay, (px, py), (px + panel_w, py + panel_h),
                  (0, 80, 180), -1)

    # Borde animado (naranja parpadeante en el primer segundo)
    border_color = (0, 165, 255) if elapsed < 1.0 else (0, 100, 220)
    cv2.rectangle(overlay, (px, py), (px + panel_w, py + panel_h), border_color, 3)

    # Ícono de cámara (texto)
    cv2.putText(overlay, "[ PLACA CAPTURADA ]", (px + 10, py + 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 220, 255), 2, cv2.LINE_AA)

    # Placa grande
    cv2.putText(overlay, plate, (px + 10, py + 62),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3, cv2.LINE_AA)

    # Confianza
    conf_str = f"Confianza: {conf:.0f}%"
    cv2.putText(overlay, conf_str, (px + 10, py + 82),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (180, 220, 255), 1, cv2.LINE_AA)

    # Mezclar con alpha
    cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0, frame)

    # Borde exterior parpadeante del frame completo (flash breve)
    if elapsed < 0.3:
        flash_alpha = 1.0 - (elapsed / 0.3)
        flash_overlay = frame.copy()
        cv2.rectangle(flash_overlay, (0, 0), (w - 1, h - 1), (0, 165, 255), 8)
        cv2.addWeighted(flash_overlay, flash_alpha * 0.8, frame, 1 - flash_alpha * 0.8, 0, frame)

    return frame


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: stream_camera.py <video_source> [fps] [camera_id]", file=sys.stderr)
        sys.exit(1)

    source = sys.argv[1]
    target_fps = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
    camera_id = sys.argv[3] if len(sys.argv) > 3 else "unknown"
    frame_delay = 1.0 / target_fps

    # Resolver URL de YouTube si aplica
    if isinstance(source, str) and ("youtube.com" in source or "youtu.be" in source):
        try:
            import yt_dlp
            with yt_dlp.YoutubeDL({'format': 'best[ext=mp4]/best', 'quiet': True}) as ydl:
                info = ydl.extract_info(source, download=False)
                source = info.get('url', source)
        except Exception:
            pass

    # Convertir a índice numérico si es webcam
    try:
        source = int(source)
    except (ValueError, TypeError):
        pass

    # Abrir fuente de video
    is_fallback = False
    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        print(f"WARNING: No se puede abrir {source}. Buscando video de fallback...", file=sys.stderr)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        fallback_paths = [
            os.path.join(script_dir, "data", "01_raw", "downloaded_stream.mp4"),
            os.path.join(script_dir, "data", "01_raw", "input_video.mp4"),
            "data/01_raw/downloaded_stream.mp4",
        ]
        for p in fallback_paths:
            if os.path.exists(p):
                cap = cv2.VideoCapture(p)
                if cap.isOpened():
                    is_fallback = True
                    print(f"Usando fallback: {p}", file=sys.stderr)
                    break

        if not cap.isOpened():
            print(f"ERROR: No se pudo abrir ninguna fuente de video.", file=sys.stderr)
            sys.exit(1)

    # Determinar si es fuente en vivo (no loopear) o archivo (sí loopear)
    is_url = isinstance(source, str) and source.startswith(("rtsp://", "rtmp://", "http://", "https://"))
    is_webcam = isinstance(source, int)
    is_live = (is_webcam or (is_url and ("rtsp://" in str(source) or "rtmp://" in str(source)))) and not is_fallback
    loop_video = not is_live and not is_url

    if is_live:
        cap.release()
        cap = VideoStream(source).start()

    # ── Cargar YOLO ──
    yolo_thread = None
    yolo_available = False
    try:
        from ultralytics import YOLO
        import torch

        num_cores = os.cpu_count() or 4
        torch.set_num_threads(num_cores)
        cv2.setNumThreads(num_cores)

        device = 0 if torch.cuda.is_available() else 'cpu'
        script_dir = os.path.dirname(os.path.abspath(__file__))
        model_path = os.path.join(script_dir, "yolov8n.pt")
        if not os.path.exists(model_path):
            model_path = "yolov8n.pt"

        model = YOLO(model_path)
        yolo_thread = YOLOTrackerThread(model, device)
        yolo_thread.start()
        yolo_available = True
        print("YOLO: Modelo cargado correctamente", file=sys.stderr, flush=True)
    except Exception as e:
        print(f"WARNING: YOLO no disponible: {e}", file=sys.stderr, flush=True)

    # ── Iniciar OCR en hilo ──
    ocr_thread = LicensePlateOCRThread(camera_id)
    ocr_thread.start()

    # Track IDs con placa detectada (para colorear naranja)
    plate_track_ids: set = set()

    # ── Header MJPEG ──
    boundary = b"--vehiscan_frame"
    sys.stdout.buffer.write(b"Content-Type: multipart/x-mixed-replace; boundary=vehiscan_frame\r\n\r\n")
    sys.stdout.buffer.flush()

    frame_count = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            if loop_video:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            else:
                break

        # Redimensionar para eficiencia de ancho de banda (máx 960px)
        h, w = frame.shape[:2]
        if w > 960:
            scale = 960.0 / w
            frame = cv2.resize(frame, (960, int(h * scale)))

        # Enviar frame al hilo YOLO
        if yolo_available and yolo_thread:
            yolo_thread.update_frame(frame)

        # Enviar recortes nuevos al OCR
        if yolo_available and yolo_thread:
            crops = yolo_thread.get_and_clear_crops()
            for tid, (crop, cls_name, vconf) in crops.items():
                ocr_thread.enqueue(tid, crop, cls_name, vconf)

        # Actualizar set de track IDs con placa
        last_cap = ocr_thread.get_last_capture()
        if last_cap:
            plate, conf, ts = last_cap
            if time.time() - ts < CAPTURE_OVERLAY_DURATION + 2:
                # Marcar todos los tracks actuales como "con placa" brevemente
                if yolo_available and yolo_thread:
                    for cls_name, tid, xyxy, conf in yolo_thread.get_boxes():
                        if tid is not None:
                            plate_track_ids.add(tid)

        # Dibujar bounding boxes de vehículos
        if yolo_available and yolo_thread:
            boxes = yolo_thread.get_boxes()
            draw_vehicle_boxes(frame, boxes, plate_track_ids)

        # Dibujar overlay de captura de placa
        frame = draw_capture_overlay(frame, last_cap)

        # Timestamp
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        cv2.putText(frame, timestamp, (10, frame.shape[0] - 15),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)

        # Indicador de estado
        status_text = "MODO DEMO - SIN SENAL" if is_fallback else "VehiScan LIVE | ALPR Activo"
        status_color = (0, 140, 255) if is_fallback else (0, 220, 0)
        cv2.putText(frame, status_text, (10, 25),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, status_color, 2, cv2.LINE_AA)

        # Indicador de OCR
        ocr_ready = ocr_thread.reader is not None
        ocr_txt = "OCR: LISTO" if ocr_ready else "OCR: Cargando..."
        ocr_col = (0, 200, 100) if ocr_ready else (0, 140, 255)
        cv2.putText(frame, ocr_txt, (10, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, ocr_col, 1, cv2.LINE_AA)

        # Codificar JPEG
        _, jpeg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 72])
        jpeg_bytes = jpeg.tobytes()

        # Escribir frame MJPEG en stdout
        try:
            sys.stdout.buffer.write(boundary + b"\r\n")
            sys.stdout.buffer.write(b"Content-Type: image/jpeg\r\n")
            sys.stdout.buffer.write(f"Content-Length: {len(jpeg_bytes)}\r\n\r\n".encode())
            sys.stdout.buffer.write(jpeg_bytes)
            sys.stdout.buffer.write(b"\r\n")
            sys.stdout.buffer.flush()
        except (BrokenPipeError, IOError):
            break

        frame_count += 1
        time.sleep(frame_delay)

    if yolo_thread:
        yolo_thread.stop()
    ocr_thread.stop()
    if hasattr(cap, 'release'):
        cap.release()


if __name__ == "__main__":
    main()

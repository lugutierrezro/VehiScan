import os
import cv2
import pandas as pd
from ultralytics import YOLO
import urllib.request

def _create_synthetic_traffic_video(output_path: str, num_frames: int = 300) -> None:
    """Creates a synthetic traffic video with moving vehicle-like shapes on a road background."""
    import numpy as np
    import random

    width, height = 1280, 720
    fps = 30.0
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

    # Define synthetic vehicles: [x, y, w, h, speed_x, speed_y, color]
    vehicles = []
    vehicle_colors = [
        (200, 200, 200),  # white/silver
        (40, 40, 40),     # black
        (30, 30, 180),    # red
        (180, 140, 30),   # blue
        (30, 140, 30),    # green
    ]
    for _ in range(8):
        lane_y = random.choice([280, 340, 420, 480])
        vehicles.append({
            "x": random.randint(-200, width),
            "y": lane_y + random.randint(-10, 10),
            "w": random.randint(80, 140),
            "h": random.randint(50, 70),
            "speed": random.uniform(3, 8) * random.choice([-1, 1]),
            "color": random.choice(vehicle_colors),
        })

    for frame_idx in range(num_frames):
        # Road background: gray asphalt
        frame = np.full((height, width, 3), (80, 80, 80), dtype=np.uint8)

        # Sky
        frame[0:250, :] = (200, 180, 140)

        # Road surface
        cv2.rectangle(frame, (0, 250), (width, 550), (60, 60, 60), -1)

        # Lane markings
        for ly in [320, 400]:
            for lx in range(0, width, 60):
                offset = (frame_idx * 4) % 60
                cv2.rectangle(frame, (lx + offset, ly - 2), (lx + offset + 30, ly + 2), (220, 220, 220), -1)

        # Draw and move vehicles
        for v in vehicles:
            x, y, w, h = int(v["x"]), int(v["y"]), v["w"], v["h"]
            color = v["color"]

            # Vehicle body
            cv2.rectangle(frame, (x, y), (x + w, y + h), color, -1)
            # Windshield
            cv2.rectangle(frame, (x + 5, y + 5), (x + w - 5, y + int(h * 0.4)), (160, 180, 200), -1)
            # Wheels
            cv2.circle(frame, (x + 15, y + h), 8, (30, 30, 30), -1)
            cv2.circle(frame, (x + w - 15, y + h), 8, (30, 30, 30), -1)

            # Move vehicle
            v["x"] += v["speed"]

            # Wrap around
            if v["speed"] > 0 and v["x"] > width + 200:
                v["x"] = -200
            elif v["speed"] < 0 and v["x"] < -200:
                v["x"] = width + 200

        # Timestamp overlay
        cv2.putText(frame, f"VehiScan Traffic Cam - Frame {frame_idx:04d}",
                    (20, 700), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

        out.write(frame)

    out.release()
    print(f"Synthetic traffic video created: {output_path} ({num_frames} frames at {fps} fps)")


def download_sample_video(url: str, output_path: str) -> str:
    """Downloads a sample traffic video if it doesn't exist."""
    # If the output_path is a numeric camera index (like 0), bypass download
    try:
        val = int(output_path)
        return val
    except (ValueError, TypeError):
        pass

    # Check if the output_path is actually a remote URL
    if isinstance(output_path, str) and (output_path.startswith(("http://", "https://", "rtsp://", "rtmp://")) or "m3u8" in output_path):
        # If it is a live streaming source (RTSP, RTMP, or M3U8), bypass download and return it
        if output_path.startswith(("rtsp://", "rtmp://")) or "m3u8" in output_path:
            print(f"Input is a live stream source: {output_path}. Bypassing download.")
            return output_path

        # If it is a remote video file (HTTP/HTTPS), download it locally to data/01_raw
        local_path = os.path.join("data", "01_raw", "downloaded_stream.mp4")
        print(f"Input is a remote URL. Downloading {output_path} to local cache: {local_path}...")
        url = output_path
        output_path = local_path

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    if not os.path.exists(output_path):
        print(f"Downloading video from {url} to {output_path}...")
        try:
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
            )
            with urllib.request.urlopen(req, timeout=30) as response, open(output_path, 'wb') as out_file:
                data = response.read()
                out_file.write(data)

            # Validate download: must be at least 10KB to be a real video
            file_size = os.path.getsize(output_path)
            if file_size < 10240:
                print(f"Downloaded file too small ({file_size} bytes), likely an error page. Removing.")
                os.remove(output_path)
                raise ValueError(f"Downloaded file is only {file_size} bytes")

            print(f"Download complete ({file_size / 1024:.1f} KB).")
        except Exception as e:
            print(f"Failed to download video: {e}. Creating synthetic traffic video instead.")
            _create_synthetic_traffic_video(output_path)
    return output_path

def resolve_youtube_url(url: str) -> str:
    """Resolves a YouTube URL to a direct streaming URL using yt-dlp."""
    try:
        import yt_dlp
        print(f"Resolving YouTube URL using yt-dlp: {url}")
        ydl_opts = {
            'format': 'best[ext=mp4]/best',
            'quiet': True,
            'no_warnings': True,
            'logger': None,
            'skip_download': True
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            resolved_url = info.get('url')
            if resolved_url:
                print(f"Successfully resolved YouTube URL to stream: {resolved_url[:80]}...")
                return resolved_url
    except Exception as e:
        print(f"Failed to resolve YouTube URL: {e}. Attempting direct open.")
    return url

def track_vehicles(
    video_path: str,
    model_name: str,
    tracker_type: str,
    output_video_path: str,
    crops_dir: str
) -> pd.DataFrame:
    """
    Tracks vehicles in a video or image directory using YOLO and a tracking algorithm.
    Saves vehicle crop images and returns tracking metadata.
    """
    # Convert video_path to string (Kedro might parse numeric index like 0 as int)
    video_path = str(video_path)

    os.makedirs(crops_dir, exist_ok=True)
    os.makedirs(os.path.dirname(output_video_path), exist_ok=True)
    
    # Load YOLO model
    model = YOLO(model_name)
    
    is_youtube = "youtube.com" in video_path or "youtu.be" in video_path
    actual_source = resolve_youtube_url(video_path) if is_youtube else video_path

    # Convert numeric camera index if applicable
    try:
        actual_source = int(actual_source)
    except ValueError:
        pass

    # Check if the source is live (webcam index or live network stream)
    is_live = False
    if isinstance(actual_source, int):
        is_live = True
    elif isinstance(actual_source, str) and (
        actual_source.startswith(("rtsp://", "rtmp://")) or "m3u8" in actual_source
    ):
        is_live = True

    is_dir = isinstance(actual_source, str) and os.path.isdir(actual_source)
    
    if is_dir:
        valid_exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
        image_files = sorted([
            os.path.join(actual_source, f) for f in os.listdir(actual_source)
            if os.path.splitext(f)[1].lower() in valid_exts
        ])
        if not image_files:
            raise ValueError(f"No valid image files found in directory: {actual_source}")
            
        print(f"Processing {len(image_files)} images from directory: {actual_source}")
        first_img = cv2.imread(image_files[0])
        if first_img is None:
            raise ValueError(f"Could not read first image in directory: {image_files[0]}")
        height, width, _ = first_img.shape
        fps = 1.0
        cap = None
    else:
        cap = cv2.VideoCapture(actual_source)
        if not cap.isOpened():
            print(f"WARNING: Could not open video source at {actual_source}. Trying fallback demo video.", file=sys.stderr)
            script_dir = os.path.dirname(os.path.abspath(__file__))
            paths = [
                "data/01_raw/downloaded_stream.mp4",
                "../data/01_raw/downloaded_stream.mp4",
                "proyecto_sistema_inteligente/data/01_raw/downloaded_stream.mp4",
                os.path.join(script_dir, "../../../../data/01_raw/downloaded_stream.mp4"),
                os.path.join(script_dir, "../../../../../data/01_raw/downloaded_stream.mp4")
            ]
            fallback_path = None
            for p in paths:
                if os.path.exists(p):
                    fallback_path = p
                    break
            
            if fallback_path:
                print(f"Using fallback demo video at: {fallback_path}", file=sys.stderr)
                cap = cv2.VideoCapture(fallback_path)
                
            if not cap or not cap.isOpened():
                raise ValueError(f"Could not open video source at {actual_source} and no fallback found.")
            
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps == 0 or fps is None:
            fps = 30.0
        
    # Setup video writer
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_video_path, fourcc, fps, (width, height))
    
    tracking_data = []
    frame_idx = 0
    
    # COCO vehicle classes: car (2), motorcycle (3), bus (5), truck (7)
    vehicle_classes = [2, 3, 5, 7]
    
    # Frame generator to unify source consumption
    def frame_generator():
        if is_dir:
            for img_path in image_files:
                frame = cv2.imread(img_path)
                if frame is not None:
                    yield frame
        else:
            max_frames = 150 if is_live else float("inf")
            count = 0
            while cap.isOpened() and count < max_frames:
                ret, frame = cap.read()
                if not ret:
                    break
                yield frame
                count += 1
            cap.release()

    for frame in frame_generator():
        # Run tracking (bytetrack.yaml or botsort.yaml)
        results = model.track(frame, persist=True, tracker=tracker_type, verbose=False)
        
        if results and results[0].boxes is not None:
            boxes = results[0].boxes
            for box in boxes:
                # Class check
                cls = int(box.cls[0].item())
                if cls not in vehicle_classes:
                    continue
                    
                # Track ID
                if box.id is not None:
                    track_id = int(box.id[0].item())
                else:
                    track_id = -1
                    
                # Coordinates
                xyxy = box.xyxy[0].cpu().numpy()
                x1, y1, x2, y2 = map(int, xyxy)
                
                # Confidence
                conf = float(box.conf[0].item())
                
                # Check if crops_dir is empty/created
                crop_filename = f"vehicle_{track_id}_frame_{frame_idx}.jpg"
                crop_path = os.path.join(crops_dir, crop_filename)
                
                # Only save crops for valid tracks, and once every N frames to save space
                saved_crop = False
                should_save = (track_id != -1) and (frame_idx % 15 == 0 if not is_dir else True)
                if should_save:
                    crop = frame[y1:y2, x1:x2]
                    if crop.size > 0:
                        cv2.imwrite(crop_path, crop)
                        saved_crop = True
                        
                tracking_data.append({
                    "frame": frame_idx,
                    "track_id": track_id,
                    "class": model.names[cls],
                    "confidence": conf,
                    "x1": x1,
                    "y1": y1,
                    "x2": x2,
                    "y2": y2,
                    "crop_path": crop_path if saved_crop else None
                })
                
                # Draw bounding box and label
                label = f"{model.names[cls]} #{track_id} {conf:.2f}"
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
                
        out.write(frame)
        frame_idx += 1
        
    out.release()
    df = pd.DataFrame(tracking_data)
    return df

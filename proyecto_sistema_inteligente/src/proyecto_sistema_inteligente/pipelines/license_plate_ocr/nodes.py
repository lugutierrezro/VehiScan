import os
import cv2
import re
import pandas as pd
import easyocr

def detect_and_ocr_plates(
    tracked_vehicles: pd.DataFrame,
    languages: list,
    output_ocr_path: str
) -> pd.DataFrame:
    """
    Processes cropped vehicle images, detects text regions, 
    and reads license plates using EasyOCR.
    """
    os.makedirs(os.path.dirname(output_ocr_path), exist_ok=True)
    
    # Guard: if the tracking DataFrame is empty or missing crop_path, short-circuit
    if tracked_vehicles.empty or "crop_path" not in tracked_vehicles.columns:
        print("No vehicle tracking data found. Skipping OCR.")
        empty_df = pd.DataFrame(columns=["track_id", "frame", "crop_path", "plate_text", "ocr_confidence"])
        empty_df.to_csv(output_ocr_path, index=False)
        return empty_df
    
    # Filter rows that have crops saved
    valid_crops = tracked_vehicles[tracked_vehicles["crop_path"].notna() & (tracked_vehicles["crop_path"] != "")]
    
    if valid_crops.empty:
        print("No vehicle crops found to run OCR on.")
        empty_df = pd.DataFrame(columns=["track_id", "frame", "crop_path", "plate_text", "ocr_confidence"])
        empty_df.to_csv(output_ocr_path, index=False)
        return empty_df
        
    # Initialize EasyOCR Reader
    print(f"Initializing EasyOCR with languages: {languages}...")
    reader = easyocr.Reader(languages, gpu=True) # Will fallback to CPU if GPU not available
    
    ocr_results = []
    processed_crops = set()
    
    for idx, row in valid_crops.iterrows():
        crop_path = row["crop_path"]
        track_id = row["track_id"]
        frame = row["frame"]
        
        if crop_path in processed_crops:
            continue
        processed_crops.add(crop_path)
        
        if not os.path.exists(crop_path):
            continue
            
        img = cv2.imread(crop_path)
        if img is None or img.size == 0:
            continue
            
        # Run EasyOCR
        # detail=1 returns bounding box, text, and confidence
        results = reader.readtext(img, detail=1)
        
        best_plate = ""
        best_conf = 0.0
        
        for (bbox, text, prob) in results:
            # Clean the text (uppercase, alphanumeric only, remove spaces)
            cleaned_text = re.sub(r'[^a-zA-Z0-9]', '', text).upper()
            
            # Simple heuristic for license plates: length between 4 and 9 characters
            if 4 <= len(cleaned_text) <= 9:
                # If we find a candidate, prioritize it over shorter or lower-confidence texts
                if prob > best_conf:
                    best_plate = cleaned_text
                    best_conf = float(prob)
                    
        # If no good candidate was found, we can take the one with the highest confidence
        # that is at least 3 characters
        if not best_plate and results:
            results_sorted = sorted(results, key=lambda x: x[2], reverse=True)
            for (bbox, text, prob) in results_sorted:
                cleaned_text = re.sub(r'[^a-zA-Z0-9]', '', text).upper()
                if len(cleaned_text) >= 3:
                    best_plate = cleaned_text
                    best_conf = float(prob)
                    break
                    
        if best_plate:
            ocr_results.append({
                "track_id": int(track_id),
                "frame": int(frame),
                "crop_path": crop_path,
                "plate_text": best_plate,
                "ocr_confidence": best_conf
            })
            
    df_ocr = pd.DataFrame(ocr_results)
    
    # If we have multiple crops for the same track_id, let's group by track_id
    # and find the most frequent plate text or the one with the highest confidence.
    if not df_ocr.empty:
        # Group and save
        df_ocr.to_csv(output_ocr_path, index=False)
        print(f"OCR results saved to {output_ocr_path}")
    else:
        print("No plates were read by OCR.")
        df_ocr = pd.DataFrame(columns=["track_id", "frame", "crop_path", "plate_text", "ocr_confidence"])
        df_ocr.to_csv(output_ocr_path, index=False)
        
    return df_ocr

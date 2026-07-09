import os
import cv2
import numpy as np
import pandas as pd
import torch
import torchvision.models as models
import torchvision.transforms as transforms
from PIL import Image

def get_dominant_color(image_path: str) -> str:
    """Estimates the dominant color of the vehicle crop in HSV color space."""
    if not os.path.exists(image_path):
        return "Unknown"
        
    img = cv2.imread(image_path)
    if img is None or img.size == 0:
        return "Unknown"
        
    # Resize to speed up and reduce noise
    img = cv2.resize(img, (100, 100))
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    
    # Define color thresholds in HSV
    # H: 0-180, S: 0-255, V: 0-255
    colors = {
        "Red": (np.array([0, 50, 50]), np.array([10, 255, 255])),
        "Red2": (np.array([170, 50, 50]), np.array([180, 255, 255])),
        "Green": (np.array([35, 50, 50]), np.array([85, 255, 255])),
        "Blue": (np.array([90, 50, 50]), np.array([130, 255, 255])),
        "Yellow": (np.array([15, 50, 50]), np.array([35, 255, 255])),
        "White": (np.array([0, 0, 200]), np.array([180, 40, 255])),
        "Black": (np.array([0, 0, 0]), np.array([180, 255, 50])),
        "Gray": (np.array([0, 0, 50]), np.array([180, 50, 199]))
    }
    
    color_counts = {}
    for color_name, (lower, upper) in colors.items():
        mask = cv2.inRange(hsv, lower, upper)
        count = np.sum(mask > 0)
        
        # Merge red bounds
        if color_name == "Red2":
            color_counts["Red"] = color_counts.get("Red", 0) + count
        else:
            color_counts[color_name] = count
            
    # Find the color with the highest count
    dominant = max(color_counts, key=color_counts.get)
    # If the dominant color has very few pixels, class as Gray/Unknown
    if color_counts[dominant] < 100:
        return "Silver/Gray"
        
    return dominant

def extract_vehicle_embeddings(
    tracked_vehicles: pd.DataFrame,
    output_reid_path: str
) -> pd.DataFrame:
    """
    Extracts visual embeddings using ResNet50 and classifies vehicle color
    to generate a Re-ID profile for each vehicle.
    """
    os.makedirs(os.path.dirname(output_reid_path), exist_ok=True)
    
    # Guard: if tracking DataFrame has no data or missing crop_path column, short-circuit
    if tracked_vehicles.empty or "crop_path" not in tracked_vehicles.columns:
        print("No vehicle tracking data found. Skipping Re-ID.")
        empty_df = pd.DataFrame(columns=["track_id", "vehicle_class", "dominant_color", "embedding_snippet"])
        empty_df.to_csv(output_reid_path, index=False)
        return empty_df

    valid_crops = tracked_vehicles[tracked_vehicles["crop_path"].notna() & (tracked_vehicles["crop_path"] != "")]
    
    if valid_crops.empty:
        print("No vehicle crops found for Re-ID.")
        empty_df = pd.DataFrame(columns=["track_id", "vehicle_class", "dominant_color", "embedding_snippet"])
        empty_df.to_csv(output_reid_path, index=False)
        return empty_df
        
    # Load ResNet50 pre-trained model for embedding extraction
    print("Loading pre-trained ResNet50 model for embedding extraction...")
    weights = models.ResNet50_Weights.DEFAULT
    resnet = models.resnet50(weights=weights)
    # Remove the final classification layer, keep average pooling
    feature_extractor = torch.nn.Sequential(*(list(resnet.children())[:-1]))
    feature_extractor.eval()
    
    # Image preprocessing pipeline
    preprocess = transforms.Compose([
        transforms.Resize(224),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    
    reid_profiles = []
    
    # Process each unique track_id
    unique_tracks = valid_crops["track_id"].unique()
    
    for track_id in unique_tracks:
        track_rows = valid_crops[valid_crops["track_id"] == track_id]
        vehicle_class = track_rows.iloc[0]["class"]
        
        # Collect crops for this vehicle
        embeddings = []
        colors = []
        
        for _, row in track_rows.iterrows():
            crop_path = row["crop_path"]
            if not os.path.exists(crop_path):
                continue
                
            # 1. Estimate color
            color = get_dominant_color(crop_path)
            colors.append(color)
            
            # 2. Extract visual embedding
            try:
                img = Image.open(crop_path).convert("RGB")
                img_tensor = preprocess(img).unsqueeze(0)
                
                with torch.no_grad():
                    # Output shape: [1, 2048, 1, 1] -> squeeze to [2048]
                    feat = feature_extractor(img_tensor).squeeze().numpy()
                    embeddings.append(feat)
            except Exception as e:
                print(f"Error processing image {crop_path} for embedding: {e}")
                
        if not embeddings:
            continue
            
        # Average embedding across all frames to get a robust profile
        mean_embedding = np.mean(embeddings, axis=0)
        # Normalize the embedding to unit length (L2 norm) for cosine similarity
        norm = np.linalg.norm(mean_embedding)
        if norm > 0:
            mean_embedding = mean_embedding / norm
            
        # Major color (mode)
        major_color = max(set(colors), key=colors.count) if colors else "Unknown"
        
        reid_profiles.append({
            "track_id": int(track_id),
            "vehicle_class": vehicle_class,
            "dominant_color": major_color,
            "embedding": mean_embedding.tolist()
        })
        
    df_reid = pd.DataFrame(reid_profiles)
    
    # Save a representation with a snippet of the embedding for easy readability in CSV
    if not df_reid.empty:
        df_reid_readable = df_reid.copy()
        df_reid_readable["embedding_snippet"] = df_reid_readable["embedding"].apply(lambda x: str(x[:5]) + "...")
        df_reid_readable = df_reid_readable.drop(columns=["embedding"])
        
        # Save complete profiles in a separate JSON/npy file for calculations
        json_path = output_reid_path.replace(".csv", ".json")
        df_reid.to_json(json_path, orient="records", indent=2)
        df_reid_readable.to_csv(output_reid_path, index=False)
        print(f"Re-ID profiles saved to {output_reid_path} and {json_path}")
        return df_reid_readable
    else:
        print("No Re-ID profiles created.")
        df_reid_empty = pd.DataFrame(columns=["track_id", "vehicle_class", "dominant_color", "embedding_snippet"])
        df_reid_empty.to_csv(output_reid_path, index=False)
        return df_reid_empty

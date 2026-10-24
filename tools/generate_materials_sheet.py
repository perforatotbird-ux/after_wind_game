import os
import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import binary_fill_holes

src = r"C:\Users\inval\.gemini\antigravity-cli\brain\f29f5821-9e75-4697-b156-d35a301ff9b9\materials_sheet_5x4_isometric_1792829556613.jpg"
bgr = cv2.imread(src)
h, w = bgr.shape[:2]

cols = 5
rows = 4
cw = w // cols  # 240
ch = h // rows  # 224

item_ids = [
    # Row 0
    "stone_dust", "sawdust", "coal_powder", "mortar", "poor_brick",
    # Row 1
    "fuel_briquette", "fired_brick", "glass", "glass_bottle", "clay_pot",
    # Row 2
    "glassware_set", "steel_plate", "precision_gear", "steel_ingot", "iron_ingot",
    # Row 3
    "fertilizer", "wooden_handle", "bolt", "fabric", "leather_strap"
]

def process_cell(cell_bgr, target_size=256):
    cell_h, cell_w = cell_bgr.shape[:2]
    gray = cv2.cvtColor(cell_bgr, cv2.COLOR_BGR2GRAY)
    
    # Mask of candidate background (very dark pixels)
    # Background in the image is typically < 15
    mask_ff = np.zeros((cell_h + 2, cell_w + 2), np.uint8)
    
    # Border points to seed flood fill
    border_pts = []
    for x in range(cell_w):
        border_pts.append((x, 0))
        border_pts.append((x, cell_h - 1))
    for y in range(cell_h):
        border_pts.append((0, y))
        border_pts.append((cell_w - 1, y))
        
    for x, y in border_pts:
        if gray[y, x] <= 24 and mask_ff[y + 1, x + 1] == 0:
            cv2.floodFill(gray.copy(), mask_ff, (x, y), 255, loDiff=6, upDiff=18, flags=4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY)
            
    # Connected background is where mask_ff == 255
    bg_mask = (mask_ff[1:-1, 1:-1] == 255)
    
    # Refine foreground mask: any pixel not connected to border background
    fg_mask = ~bg_mask
    
    # Fill internal holes (e.g. inside dark objects)
    fg_mask = binary_fill_holes(fg_mask)
    
    # Also check if any small stray speckles near border need cleanup
    # Only keep the largest connected component(s)
    num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(fg_mask.astype(np.uint8))
    if num_labels > 1:
        # Sort components by area (excluding background 0)
        areas = stats[1:, cv2.CC_STAT_AREA]
        max_area = np.max(areas)
        # Keep components with at least 5% of max_area (to keep multi-piece items like glassware set or bolt+nut)
        clean_fg = np.zeros_like(fg_mask, dtype=bool)
        for idx, area in enumerate(areas, start=1):
            if area >= max_area * 0.05:
                clean_fg |= (labels == idx)
        fg_mask = clean_fg

    # Find tight bounding box of the foreground
    ys, xs = np.where(fg_mask)
    if len(xs) == 0:
        return np.zeros((target_size, target_size, 4), dtype=np.uint8)
        
    min_x, max_x = xs.min(), xs.max()
    min_y, max_y = ys.min(), ys.max()
    
    # Add a small padding around the cropped bounding box (e.g. 2px)
    pad = 2
    crop_x1 = max(0, min_x - pad)
    crop_x2 = min(cell_w, max_x + pad + 1)
    crop_y1 = max(0, min_y - pad)
    crop_y2 = min(cell_h, max_y + pad + 1)
    
    crop_bgr = cell_bgr[crop_y1:crop_y2, crop_x1:crop_x2]
    crop_fg = fg_mask[crop_y1:crop_y2, crop_x1:crop_x2]
    crop_gray = gray[crop_y1:crop_y2, crop_x1:crop_x2]
    
    # Build soft anti-aliased alpha
    # For pixels outside crop_fg: alpha = 0
    # For pixels inside crop_fg near edge: smooth ramp based on brightness
    alpha = np.zeros_like(crop_gray, dtype=np.float32)
    # Smooth mask
    u8_mask = (crop_fg * 255).astype(np.uint8)
    blurred = cv2.GaussianBlur(u8_mask, (3, 3), 0.8).astype(np.float32) / 255.0
    
    # Intensity-aware alpha: ramp down if pixel is near border and dark
    # Dark background was < 15
    lum_ramp = np.clip((crop_gray.astype(np.float32) - 8.0) / 20.0, 0.0, 1.0)
    
    # Final alpha
    final_alpha = np.where(crop_fg, np.maximum(blurred, lum_ramp * blurred), 0.0)
    final_alpha = np.clip(final_alpha, 0.0, 1.0)
    
    # Unmultiply black background for clean edges
    rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB).astype(np.float32)
    safe_alpha = np.clip(final_alpha, 0.15, 1.0)[:, :, np.newaxis]
    rgb_clean = np.clip(rgb / safe_alpha, 0, 255).astype(np.uint8)
    alpha_u8 = (final_alpha * 255).astype(np.uint8)
    
    crop_rgba = np.dstack([rgb_clean, alpha_u8])
    
    # Center into target_size x target_size (256x256)
    # Keep aspect ratio, scale to fit nicely (e.g. max dimension ~ 210px for ~18% margin)
    crop_pil = Image.fromarray(crop_rgba, mode="RGBA")
    item_w, item_h = crop_pil.size
    
    max_target_dim = int(target_size * 0.82) # ~210 px
    scale = min(max_target_dim / item_w, max_target_dim / item_h)
    new_w = max(1, int(round(item_w * scale)))
    new_h = max(1, int(round(item_h * scale)))
    
    scaled_item = crop_pil.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    out_cell = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    paste_x = (target_size - new_w) // 2
    paste_y = (target_size - new_h) // 2
    out_cell.paste(scaled_item, (paste_x, paste_y), scaled_item)
    
    return np.array(out_cell)

print("Processing all 20 cells...")
out_sheet = np.zeros((rows * 256, cols * 256, 4), dtype=np.uint8)
individual_icons = {}

for r in range(rows):
    for c in range(cols):
        idx = r * cols + c
        item_id = item_ids[idx]
        cell_bgr = bgr[r*ch : (r+1)*ch, c*cw : (c+1)*cw]
        rgba_256 = process_cell(cell_bgr, 256)
        
        # Place into out_sheet
        out_sheet[r*256 : (r+1)*256, c*256 : (c+1)*256] = rgba_256
        individual_icons[item_id] = rgba_256

# Output directories
out_dir = r"K:\After Wind\assets\materials_nano_banana"
os.makedirs(out_dir, exist_ok=True)

# Save master sprite sheet
sheet_im = Image.fromarray(out_sheet, mode="RGBA")
sheet_path = os.path.join(out_dir, "materials_sheet_256.png")
sheet_im.save(sheet_path, "PNG")
print(f"Saved master sheet: {sheet_path} ({sheet_im.size})")

# Also save copy in assets/icons/ for general access
icons_dir = r"K:\After Wind\assets\icons"
os.makedirs(icons_dir, exist_ok=True)
sheet_im.save(os.path.join(icons_dir, "materials_sheet_256.png"), "PNG")

# Save individual 256x256 icons
for item_id, rgba_arr in individual_icons.items():
    icon_im = Image.fromarray(rgba_arr, mode="RGBA")
    icon_path = os.path.join(out_dir, f"{item_id}_icon.png")
    icon_im.save(icon_path, "PNG")

print(f"Saved all 20 individual icons into {out_dir}")

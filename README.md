# PicoCAD-Shader
A shader with faithful recreation for 1 & 2, and more.

<img width="443" height="333" alt="picocadshader" src="https://github.com/user-attachments/assets/a6d72587-af6b-4135-b900-38bb2838d762" />


# 🎨 PicoCAD-Style URP Shader for Unity 6.x

A beginner-friendly Unity URP shader designed to emulate the crisp, low-poly aesthetic of **PicoCAD**. Import your models and get started!
Built for simplicity and creativity, this shader includes a demo scene, and intuitive inspector controls. It's robust, gets the job done, and is meant to encourage experimentation.

> 💡 *"It's probably not the best shader in the world. But, it gets the job done and I hope it encourages creativity."*

---

## 📦 Requirements
- **Unity 6.x** (URP pipeline required)
- Basic knowledge of Unity materials & inspector assignment
- No external packages needed

---

## 🛠️ Setup & Import Settings

### 1. Camera & Viewport
For accurate color reproduction, **disable Post-Processing** on your main camera and in the Scene Viewport:
- `Camera > Post Processing` → `Off`
- `Scene View > Camera > Post Processing` → `Off`

### 2. PNG Texture Import Settings
To preserve the crisp, pixel-perfect look:
- `Mip Maps` → **Off**
- `Filter Mode` → **Point (no filter)**
- `Compression` → **None**
- `Alpha Source` → **From Input**


### 3. Palette Setup
Copy your palette directly from PicoCAD:
1. Open your PicoCAD scene
2. Screenshot the palette grid
3. Edit into 16x3 image
4. Import into Unity with settings above
5. Assign to the shader's `Palette` property

(Or just make edits to the provided bit-palette.png)

📸 *[TODO: Add screenshot/gif showing palette copy process]*

---

## 🎛️ Shader Inspector Guide

### 🖼️ Textures
| Property | Description |
|----------|-------------|
| **PicoCAD Texture** | Index map + alpha. RGB drives color lookup, Alpha controls visibility/cutoff. |
| **Palette (16 x 3)** | 16-color gradient × 3 shading rows. |

### 📐 Dither / Plaid Grid
| Property | Description |
|----------|-------------|
| **Use Dynamic Camera Scaling** | Toggles distance-based grid scaling. |
| **Static Grid Scale** | Base dither size when dynamic scaling is off. |
| **Near / Far Grid Scale** | Min/max dither sizes when dynamic scaling is on. |
| **Distance Near / Far** | Camera distance thresholds for dynamic scaling fade. |
| **Switch away from Unmoving** | Toggles to **Uniform Object-Space Dither** (scales with object, not camera). |
| **Grid Scale** | Size multiplier for uniform dither mode. |

### 💡 Shading & Lighting
| Property | Description |
|----------|-------------|
| **Low Poly Shading** | Enables flat shading via geometry shader. Disables per-vertex normal interpolation. |
| **Light Scale** | Multiplies overall lighting intensity. |
| **Ambient** | Base shadow floor (0 = pitch black, 1 = fully lit). |
| **Threshold Black/Dark/Mid/Dither** | Quantized lighting band cutoffs. Adjust to control how many shading steps appear. |
| **Light Steps** | Number of discrete lighting bands (2–16). |
| **Amplify Bands** | Adds spacing between threshold bands for sharper banding. |
| **Invert Lighting / Back Face** | Flips light direction for front/back faces (useful for inside-out meshes or stylized lighting). |

### 🎨 Rendering Options
| Property | Description |
|----------|-------------|
| **Show Faces** | `Front` / `Back` / `Both` face culling. |
| **Back Face Shading** | `Flat Light` (row 1), `Flat Dark` (row 3), or `Dynamic` (calculates lighting per back-face pixel). |
| **Alpha Mode** | `Flat Cut` (hard alpha), `Stipple` (dithered transparency), `Transparent` (blend mode). |
| **Alpha Cutoff** | Minimum alpha value to render. Pixels below this are discarded. |

---

## ⚠️ Critical Notes

### 🔹 Transparency & Render Queue
> **TRANSPARENCY CAN'T BE STRESSED ENOUGH**

Alpha Mode Transparent: shader uses rendering queue. To avoid clipping, z-fighting, or render distance jumps:
- Always set the **Render Queue** manually in the material inspector (`Transparent` = 3001 or more)
- `Flat Cut` & `Stipple` modes disable depth write to prevent sorting artifacts (so no worries)
- `Transparent` mode enables texture image  but requires correct render queue ordering <---
- Test with overlapping objects to verify sorting behavior after adjusting queue

### 🔹 Depth & Pixel Camera
For accurate pixel-aligned rendering, I used a pixel-snapping camera setup found on youtube:
📺 [Render Pixel Camera Tutorial](https://www.youtube.com/watch?v=R7922Pchiq4)


---

## 🐛 Known Issues & Roadmap

| Status | Issue |
|--------|-------|
| 🚧 Todo | Global transparency slider (object-wide opacity without alpha texture) |
| 🚧 Todo | Support for palettes larger than 16x3 |
| 🚧 Todo | Adding more palette presets to the repo |
| 🚧 Todo | Smooth dynamic distance scaling (currently janky, works best clamped) |

---

## 🙏 Credits

- **Johan Peitz** – [PicoCAD](https://www.picocad.com/) & PicoCAD Bunny
- **hfcred** – [PicoCAD2 Web Viewer](https://github.com/hfcRed/PicoCAD2-Web-Viewer)
- **aladarknis** - [Godot PicoCAD Importer](https://github.com/aladarknis/godot-picocad2-importer)
- **GlasCade** – Demo scene music - [Check out his YT](https://www.youtube.com/@glascade/shorts)
- **Para** – [Jet, books, stop sign area assets](https://paramonium.itch.io/)
- **Holland** (`holland1793` on Discord) – Soft serve cone model
- **You** – For trying it out!

---

## 📜 License
This project is free to use, modify, and share under the **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)** license.  
🔗 [View License](https://creativecommons.org/licenses/by-nc/4.0/)

You must give appropriate credit, indicate changes, and link to the license. **Commercial use is not permitted.** No warranty is provided.
Further use requires prior written permission from the copyright holder.

---

## 💬 Community & Support
- 🌐 Join the Discord: [Insert Discord Invite Link]
- 🍴 Fork freely, tweak as needed, and share your builds!
- 📝 I don't plan to offer extensive tech support beyond this guide, but I welcome PRs, feedback, and community contributions.

---

## 📝 Final Thoughts
This shader was built to be approachable for beginners while still offering enough control for stylized workflows. It's not perfect, but it's reliable, documented, and meant to spark creativity. If it helps you make something cool, that's all that matters.

Happy rendering! 🎮✨

# PicoCAD-Shader
A shader with faithful recreation for 1 & 2, and more.




# 🎨 Picocad-Style URP Shader for Unity 6.x

A beginner-friendly Unity URP shader designed to emulate the crisp, stylized aesthetic of **Picocad**. Built for simplicity and creativity, this shader includes a demo scene, intuitive controls, and tools for palette/texture management. It's robust, gets the job done, and is meant to encourage experimentation.

> 💡 *"It's probably fine. It gets the job done and I hope to encourage creativity."*

---

## ✨ Features
- 🌞 Dynamic lighting support
- 🟦 Unmoving plaid/texture alignment
- 🎨 Custom palette & texture injection
- 🔍 Alpha/transparent material control
- 📐 Dither pattern support
- 🔲 Round & flat/low-poly shading modes
- 📦 Demo scene included for easy testing

---

## 📦 Requirements
- **Unity 6.x** (URP pipeline required)
- Basic knowledge of Unity material/shader assignment
- No external packages needed

---

## 🛠️ Setup & Configuration

### 1. Camera Settings
For accurate color reproduction, **disable Post-Processing** on your main camera and in the Scene Viewport:
- `Camera > Post Processing` → `Off`
- `Scene View > Camera > Post Processing` → `Off`

### 2. Texture Import Settings
To preserve the crisp, pixel-perfect look:
- `Mip Maps` → **Off**
- `Filter Mode` → **Point (no filter)**
- `Compression` → **None**
- `Alpha Source` → **From Input or Grayscale** (enable as needed)

### 3. Palette Setup
Copy your palette directly from Picocad:
1. Open your Picocad scene
2. Export/screenshot the palette grid
3. Import into Unity with settings above
4. Assign to the shader's `Palette` property

📸 *[TODO: Add screenshot/gif showing palette copy process]*

---

## ⚠️ Important Notes

### 🔹 Transparency & Render Queue
> **TRANSPARENCY CAN'T BE STRESSED ENOUGH**

This shader uses blend transparency. To avoid clipping, z-fighting, or render distance jumps:
- Always set the **Render Queue** manually in the material inspector
- Use `Depth Write = Off` for transparent passes
- Test with multiple overlapping objects to verify sorting

### 🔹 Depth & Pixel Camera
For accurate pixel-aligned rendering, consider using a pixel-snapping camera setup:
📺 [Render Pixel Camera Tutorial](https://www.youtube.com/watch?v=R7922Pchiq4)

---

## 🐛 Known Issues & Roadmap

| Status | Issue |
|--------|-------|
| ✅ Fixed | Transparency clipping & render distance jumps (render queue resolved) |
| ✅ Fixed | Triangles appearing oddly with flat shading |
| ✅ Fixed | Floor transparency issues (resolved in v53) |
| 🚧 Todo | Transparency slider for full-object opacity (no alpha texture needed) |
| 🚧 Todo | Support for palettes larger than 16x3 |
| 🚧 Todo | More built-in palette presets |
| 🚧 Todo | Smooth dynamic distance scaling (currently janky) |

---

## 🙏 Credits

- **Johan Peitz** – [Picocad](https://www.picocad.com/) & [The Bunny](https://www.picocad.com/bunny)
- **hfcred** – [WedViewer](https://github.com/hfcred/wedviewer) (base shader code)
- **GlasCade** – Demo scene music
- **Para** – Jet, books, stop sign area assets
- **Holland** (`holland1793` on Discord) – Soft serve cone model
- **You** – For trying it out!

---

## 📜 License
This project is free to use, modify, and share under the **Creative Commons Attribution 4.0 International (CC BY 4.0)** license.  
🔗 [View License](https://creativecommons.org/licenses/by/4.0/)

You must give appropriate credit, indicate changes, and link to the license. No warranty is provided.

---

## 💬 Community & Support
- 🌐 Join the Discord: [Insert Discord Invite Link]
- 🍴 Fork freely, tweak as needed, and share your builds!
- 📝 I don't plan to offer extensive tech support beyond this guide, but I welcome PRs, feedback, and community contributions.

---

## 📝 Final Thoughts
This shader was built to be approachable for beginners while still offering enough control for stylized workflows. It's not perfect, but it's reliable, documented, and meant to spark creativity. If it helps you make something cool, that's all that matters.

Happy rendering! 🎮✨
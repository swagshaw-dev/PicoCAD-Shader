Shader "Custom/Ditherv8_Plaid_Surface"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _Ambient("Ambient", Range(0,1)) = 0.15
        _RenderMode("Render Mode", Int) = 0

        // Plaid controls
        _DitherMode("Dither Mode 0=px 1=relative", Int) = 1
        _DitherScaleA("Plaid Scale A", Float) = 0.02
        _DitherScaleB("Plaid Scale B", Float) = 0.04
        _PlaidAngle("Plaid Angle (deg)", Float) = 45.0
        _PlaidBlend("Plaid Blend", Range(0,1)) = 1.0

        // Optional tint to let lighting color influence palette subtly
        _LightTint("Light Tint", Range(0,1)) = 0.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200

        CGPROGRAM
        // Surface shader using a custom lighting function named DitherLighting
        #pragma surface surf DitherLighting fullforwardshadows addshadow
        #pragma target 3.0

        #include "UnityCG.cginc"

        sampler2D _IndexTex;
        sampler2D _PaletteTex;
        float _Ambient;
        int _RenderMode;

        int _DitherMode;
        float _DitherScaleA;
        float _DitherScaleB;
        float _PlaidAngle;
        float _PlaidBlend;
        float _LightTint;

        struct Input
        {
            float2 uv_IndexTex;
            float3 normal : NORMAL;    // vertex normal (object space) -> convert to world in surf
            float4 screenPos;          // required for screen-anchored plaid
        };

        // rotate a 2D point by angle (radians)
        float2 rotate2(float2 p, float a)
        {
            float ca = cos(a);
            float sa = sin(a);
            return float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
        }

        // Sample palette helper (idx 0..15, row 0..2)
       float3 SamplePalette(float idx, float paletteRow) 
       { float u = (idx + 0.5) / 16.0; float v = (paletteRow + 0.5) / 3.0; 
       return tex2D(_PaletteTex, float2(u, v)).rgb; }


        // Surface function: compute index and plaid, encode into o.Albedo for the lighting function
        void surf(Input IN, inout SurfaceOutput o)
        {
            // --- index selection (0..15)
            float texSample = tex2D(_IndexTex, IN.uv_IndexTex).r;
            float colorIdx = floor(texSample * 255.0 + 0.5);
            colorIdx = clamp(colorIdx, 0.0, 15.0);

            // --- compute screen pixel coords (screenPos is clip-space; convert to pixels)
            float2 ndc = IN.screenPos.xy / IN.screenPos.w; // 0..1
            float2 screenSize = float2(_ScreenParams.x, _ScreenParams.y);
            float2 fragCoord = ndc * screenSize;

            // --- compute effective scales (screen-relative or pixel)
            float shortSide = min(screenSize.x, screenSize.y);
            float scaleA = _DitherScaleA;
            float scaleB = _DitherScaleB;
            if (_DitherMode == 1)
            {
                scaleA = max(0.0001, _DitherScaleA * shortSide);
                scaleB = max(0.0001, _DitherScaleB * shortSide);
            }
            else
            {
                scaleA = max(0.0001, scaleA);
                scaleB = max(0.0001, scaleB);
            }

            // --- Plaid computation (screen-anchored)
            float2 cellA = floor(fragCoord / scaleA);
            float checkerA = fmod(cellA.x + cellA.y, 2.0);

            float angleRad = radians(_PlaidAngle);
            float2 center = screenSize * 0.5;
            float2 rel = fragCoord - center;
            float2 rotated = rotate2(rel, angleRad) + center;
            float2 cellB = floor(rotated / scaleB);
            float checkerB = fmod(cellB.x + cellB.y, 2.0);

            float plaidRaw = checkerA * checkerB;
            float plaid = lerp(checkerA, plaidRaw, saturate(_PlaidBlend));

            // Encode values into Albedo channels for the lighting function:
            // Albedo.r = normalized colorIdx (0..1)
            // Albedo.g = plaid (0..1)
            o.Albedo = float3(colorIdx / 15.0, plaid, 0.0);

            // Neutral physical values (we only use palette colors)
            o.Specular = 0.0;
            o.Gloss = 0.0;

            // Provide a proper normal for lighting: convert object normal to world normal
            o.Normal = normalize(UnityObjectToWorldNormal(IN.normal));
        }

        // Custom lighting model: DitherLighting
        // Called per-light by Unity's forward renderer. Use SurfaceOutput here.
        half4 LightingDitherLighting(SurfaceOutput s, half3 lightDir, half atten)
        {
            // Recover encoded values from s.Albedo
            float colorIdxNorm = saturate(s.Albedo.r);
            float plaid = saturate(s.Albedo.g);
            float colorIdx = floor(colorIdxNorm * 15.0 + 0.5);

            // Normal and light direction are in world space; ensure normalized
            half3 N = normalize(s.Normal);
            half3 L = normalize(lightDir);

            // Compute raw dot using the same sign convention (negated)
            float rawDot = -dot(N, L);
            rawDot = saturate(rawDot);

            // Per-light shaping
            float lambert = rawDot; // 0..1
            float lightFactorPerLight = 1.0 - (1.0 - lambert) * (1.0 - lambert);
            lightFactorPerLight = clamp(lightFactorPerLight, _Ambient, 1.0);

            // Determine palette row for this per-light factor.
            int paletteRow = 0;
            if (lightFactorPerLight < 0.4)
            {
                paletteRow = 2;
            }
            else if (lightFactorPerLight < 0.56)
            {
                paletteRow = 1;
            }
            else if (lightFactorPerLight < 0.75)
            {
                paletteRow = (plaid < 0.5) ? 1 : 0;
            }
            else
            {
                paletteRow = 0;
            }

            // Sample palette color
            float3 pal = SamplePalette(colorIdx, paletteRow);

            // Compute diffuse contribution (Lambert * atten)
            float diff = lambert * atten;

            // Return the diffuse contribution scaled by palette color.
            half3 c = pal * diff;

            return half4(c, 1.0);
        }

        ENDCG
    }

    FallBack "Diffuse"
}

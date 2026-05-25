Shader "Custom/SteppedSkybox" {
    Properties {
        _BaseCol ("Base Color", Color) = (1, 1, 1, 1)
        _TopCol ("Top Color", Color) = (1, 1, 1, 1)
        _Steps ("Gradient Steps", Range(2, 32)) = 8
        _Coverage ("Gradient Coverage", Range(0.1, 2.0)) = 1.0
    }
    SubShader {
        Tags { "RenderType"="Opaque" "Queue"="Background" }
        LOD 100
        Pass {
            Cull Off      // Double-sided rendering
            ZWrite Off    // Skybox depth safety
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata { float4 vertex : POSITION; };
            struct v2f {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
            };

            fixed4 _BaseCol, _TopCol;
            float _Steps, _Coverage;

            v2f vert(appdata v) {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target {
                // World-space direction for stable, camera-independent mapping
                float3 dir = normalize(i.worldPos);
                float y = dir.y; // -1 (bottom) to 1 (top)

                // Map to 0-1, clamping below horizon to base color
                float t = saturate(y);

                // Control vertical spread of the gradient
                float gradient = saturate(t * _Coverage);

                // Quantize to create clean stepped bands
                float stepped = floor(gradient * _Steps) / _Steps;

                return lerp(_BaseCol, _TopCol, stepped);
            }
            ENDCG
        }
    }
}

shader_type spatial;
render_mode cull_disabled;

uniform vec3 Main_Color : source_color = vec3(1.0);
uniform vec3 Effect_Color : source_color = vec3(0.3, 0.3, 1.0);

uniform int Octave_Count : hint_range(1, 20) = 10;
uniform float Amp_Start = 0.5;
uniform float Amp_Coeff = 0.5;
uniform float Freq_Coeff = 2.0;
uniform float Speed = 3.0;

uniform float Y_Size = 4.0;
uniform float X_Size = 1.0;

uniform float Emission_Power = 2.0;
uniform sampler2D Power_Texture : source_color;

float Hash12(vec2 UV_)
{
    return fract(cos(mod(dot(UV_, vec2(13.9898, 8.141)), 3.14)) * 43758.5453);
}

vec2 Hash22(vec2 UV_)
{
    UV_ = vec2(dot(UV_, vec2(127.1,311.7)),
    dot(UV_, vec2(269.5,183.3)));
    return 2.0 * fract(sin(UV_) * 43758.5453123);
}

float Noise(vec2 UV_)
{
    vec2 IUV = floor(UV_);
    vec2 FUV = fract(UV_);
    vec2 Blur = smoothstep(0.0, 1.0, FUV);

    float A = dot(Hash22(IUV + vec2(0.0,0.0)), FUV - vec2(0.0,0.0));
    float B = dot(Hash22(IUV + vec2(1.0,0.0)), FUV - vec2(1.0,0.0));
    float C = dot(Hash22(IUV + vec2(0.0,1.0)), FUV - vec2(0.0,1.0));
    float D = dot(Hash22(IUV + vec2(1.0,1.0)), FUV - vec2(1.0,1.0));

    float Mix_X1 = mix(A, B, Blur.x);
    float Mix_X2 = mix(C, D, Blur.x);

    return mix(Mix_X1, Mix_X2, Blur.y) + 0.5;
}

float FBM(vec2 UV_)
{
    float Value = 0.0;
    float Amplitude = Amp_Start;

    for (int Index = 0; Index < Octave_Count; Index++)
    {
        Value += Amplitude * Noise(UV_);
        UV_ *= Freq_Coeff;
        Amplitude *= Amp_Coeff;
    }

    return Value;
}

void fragment()
{
    float Power_Value = texture(Power_Texture, UV).r;

    vec2 Modified_UV = 2.0 * UV - 1.0;
    Modified_UV.y *= Y_Size;
    Modified_UV.x *= X_Size;

    Modified_UV.x -= Amp_Start;
    Modified_UV += FBM(Modified_UV + TIME * Speed);
    Modified_UV.x += 0.5 - Amp_Coeff;

    float Dist = abs(Modified_UV.x);

    vec3 Final_Color = Effect_Color * mix(0.0, 0.05, Hash12(vec2(TIME))) / Dist;

    ALBEDO = Final_Color * Main_Color;
    EMISSION = ALBEDO * Emission_Power;
    ALPHA = Final_Color.r;
}

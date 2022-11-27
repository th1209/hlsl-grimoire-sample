cbuffer cb : register(b0)
{
    float4x4 mvp;       // MVP行列
    float4 mulColor;    // 乗算カラー
};

struct VSInput
{
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct PSInput
{
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

Texture2D<float4> sceneTexture : register(t0); // シーンテクスチャ
sampler Sampler : register(s0);

PSInput VSMain(VSInput In)
{
    PSInput psIn;
    psIn.pos = mul(mvp, In.pos);
    psIn.uv = In.uv;
    return psIn;
}

float4 PSMain(PSInput In) : SV_Target0
{
    float4 color = sceneTexture.Sample(Sampler, In.uv);

    // step-1 基準テクセル+近傍8テクセルの平均を計算する
    float offsetU = 1.5f / 1280.0f;
    float offsetV = 1.5f / 720.0f;
    color += screenTexture.Sample(Sampler, In.uv + float2(offsetU,      0.0f));
    color += screenTexture.Sample(Sampler, In.uv + float2(-offsetU,     0.0f));
    color += screenTexture.Sample(Sampler, In.uv + float2(0.0f,      offsetV));
    color += screenTexture.Sample(Sampler, In.uv + float2(0.0f,     -offsetV));
    color += screenTexture.Sample(Sampler, In.uv + float2(offsetU,   offsetV));
    color += screenTexture.Sample(Sampler, In.uv + float2(offsetU,  -offsetV));
    color += screenTexture.Sample(Sampler, In.uv + float2(-offsetU,  offsetV));
    color += screenTexture.Sample(Sampler, In.uv + float2(-offsetU, -offsetV));

    // 基準テクセルと近傍8つなので､9で割る
    color /= 9.0f;

    return color;
}

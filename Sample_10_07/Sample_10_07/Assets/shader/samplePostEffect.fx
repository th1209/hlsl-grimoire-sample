/*!
 * @brief 被写界深度
 */

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

/*!
 * @brief 頂点シェーダー
 */
PSInput VSMain(VSInput In)
{
    PSInput psIn;
    psIn.pos = mul(mvp, In.pos);
    psIn.uv = In.uv;
    return psIn;
}

//step-11 ボケ画像と深度テクスチャにアクセスするための変数を追加
Texture2D<float4> bokeTexture: register(t0);
Texture2D<float4> depthTexture: register(t1);

sampler Sampler : register(s0);

// cbuffer cb : register(b0)
// {
//     float4x4 mpv; //MVP行列
//     float4 mulColor; // 乗算カラー
// };

/////////////////////////////////////////////////////////
// ボケ画像書き込み用
/////////////////////////////////////////////////////////

float4 PSMain(PSInput In) : SV_Target0
{
    // step-12 ボケ画像書き込み用のピクセルシェーダーを実装
    float depth = depthTexture.Sample(Sampler, In.uv);

    // カメラ空間の深度値が800以下ならピクセルキル
    clip(depth -800);

    float4 boke = bokeTexture.Sample(Sampler, In.uv);

    // 深度値から不透明度を計算(深度値800からボケはじまり､2000で最大のボケ具合になる)
    boke.a = min(1.0f, (depth - 800.0f) / 2000.0f);

    return boke;
}

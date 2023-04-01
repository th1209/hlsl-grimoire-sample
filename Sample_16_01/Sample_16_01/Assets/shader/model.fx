/*!
 * @brief シンプルなモデル表示用のシェーダー
 */

// step-7 ポイントライト構造体を定義する
struct SPointLight
{
    float3 position;
    float3 color;
    float range;
};

// step-8 ポイントライトの数を表す定数を定義する
static const int NUM_POINT_LIGHT = 1000;

// モデル用の定数バッファー
cbuffer ModelCb : register(b0)
{
    float4x4 mWorld;
    float4x4 mView;
    float4x4 mProj;
};

// step-9 ポイントライトの定数バッファーにアクセスするための変数を定義する
cbuffer PointLightCb : register(b1)
{
    SPointLight pointLights[NUM_POINT_LIGHT];
}

// 頂点シェーダーへの入力
struct SVSIn
{
    float4 pos      : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
};

// ピクセルシェーダーへの入力
struct SPSIn
{
    float4 pos      : SV_POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
    float3 worldPos : TEXCOORD1;    // ワールド座標
};

// モデルテクスチャ
Texture2D<float4> g_texture : register(t0);

// サンプラーステート
sampler g_sampler : register(s0);

/// <summary>
/// モデル用の頂点シェーダーのエントリーポイント
/// </summary>
SPSIn VSMain(SVSIn vsIn, uniform bool hasSkin)
{
    SPSIn psIn;

    psIn.pos = mul(mWorld, vsIn.pos);   // モデルの頂点をワールド座標系に変換

    psIn.worldPos = psIn.pos;

    psIn.pos = mul(mView, psIn.pos);    // ワールド座標系からカメラ座標系に変換
    psIn.pos = mul(mProj, psIn.pos);    // カメラ座標系からスクリーン座標系に変換
    psIn.normal = normalize(mul(mWorld, vsIn.normal));
    psIn.uv = vsIn.uv;

    return psIn;
}

/// <summary>
/// モデル用のピクセルシェーダーのエントリーポイント
/// </summary>
float4 PSMain(SPSIn psIn) : SV_Target0
{
    // アルベドカラーを出力
    float4 albedo = g_texture.Sample(g_sampler, psIn.uv);

    float3 lig = 0.0f;

    // step-10 ポイントライトから光によるLambert拡散反射を計算する
    for(int i = 0; i < NUM_POINT_LIGHT; i++)
    {
        // 光源からサーフェスに入射するベクトル
        float3 ligDir = normalize(psIn.worldPos - pointLights[i].position);

        // 光源からサーフェスまでの距離
        float distance = length(psIn.worldPos - pointLights[i].position);
        
        // 反射の強さ
        float t = max(0.0f, dot(-ligDir, psIn.normal));

        // 距離に応じた影響率
        float affect = 1.0f - min(1.0f, distance / pointLights[i].range);
        lig += pointLights[i].color * t * affect;
    }

    // 環境光を加算
    lig += 0.3f;
    albedo.xyz *= lig;
    return albedo;
}

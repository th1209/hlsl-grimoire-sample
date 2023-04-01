/*!
 * @brief ディズニーベースの物理ベースシェーダ
 */

///////////////////////////////////////////////////
// 定数
///////////////////////////////////////////////////
static const int NUM_DIRECTIONAL_LIGHT = 4; // ディレクションライトの本数
static const float PI = 3.1415926f;         // π

///////////////////////////////////////////////////
// 構造体
///////////////////////////////////////////////////
// モデル用の定数バッファー
cbuffer ModelCb : register(b0)
{
    float4x4 mWorld;
    float4x4 mView;
    float4x4 mProj;
};

// ディレクションライト
struct DirectionalLight
{
    float3 direction;   // ライトの方向
    float4 color;       // ライトの色
};
// ライト用の定数バッファー
cbuffer LightCb : register(b1)
{
    DirectionalLight directionalLight[NUM_DIRECTIONAL_LIGHT];
    float3 eyePos;          // カメラの視点
    float specPow;          // スペキュラの絞り
    float3 ambientLight;    // 環境光
};

// 頂点シェーダーへの入力
struct SVSIn
{
    float4 pos : POSITION;  // モデルの頂点座標
    float3 normal : NORMAL; // 法線
    float3 tangent  : TANGENT;
    float3 biNormal : BINORMAL;
    float2 uv : TEXCOORD0;  // UV座標
};

// ピクセルシェーダーへの入力
struct SPSIn
{
    float4 pos : SV_POSITION;       // スクリーン空間でのピクセルの座標
    float3 normal : NORMAL;         // 法線
    float3 tangent : TANGENT;
    float3 biNormal : BINORMAL;
    float2 uv : TEXCOORD0;          // uv座標
    float3 worldPos : TEXCOORD1;    // ワールド空間でのピクセルの座標
};

///////////////////////////////////////////////////
// グローバル変数
///////////////////////////////////////////////////

// step-1 各種マップにアクセスするための変数を追加
Texture2D<float4> g_albedo : register(t0);
Texture2D<float4> g_normalMap : register(t1);
Texture2D<float4> g_metallicSmoothMap : register(t2); //r:メタリック､α:滑らかさ

// サンプラーステート
sampler g_sampler : register(s0);

///////////////////////////////////////////////////
// 関数
///////////////////////////////////////////////////

float3 GetNormal(float3 normal, float3 tangent, float3 biNormal, float2 uv)
{
    float3 binSpaceNormal = g_normalMap.SampleLevel (g_sampler, uv, 0.0f).xyz;
    binSpaceNormal = (binSpaceNormal * 2.0f) - 1.0f;

    float3 newNormal = tangent * binSpaceNormal.x + biNormal * binSpaceNormal.y + normal * binSpaceNormal.z;

    return newNormal;
}

// ベックマン分布を計算する
float Beckmann(float m, float t)
{
    float t2 = t * t;
    float t4 = t * t * t * t;
    float m2 = m * m;
    float D = 1.0f / (4.0f * m2 * t4);
    D *= exp((-1.0f / m2) * (1.0f-t2)/ t2);
    return D;
}

// フレネルを計算。Schlick近似を使用
float SpcFresnel(float f0, float u)
{
    // from Schlick
    return f0 + (1-f0) * pow(1-u, 5);
}

/// <summary>
/// Cook-Torranceモデルの鏡面反射を計算
/// </summary>
/// <param name="L">光源に向かうベクトル</param>
/// <param name="V">視点に向かうベクトル</param>
/// <param name="N">法線ベクトル</param>
/// <param name="metallic">金属度</param>
float CookTorranceSpecular(float3 L, float3 V, float3 N, float metallic)
{
    float microfacet = 0.76f;

    // 金属度を垂直入射の時のフレネル反射率として扱う
    // 金属度が高いほどフレネル反射は大きくなる
    float f0 = metallic;

    // ライトに向かうベクトルと視線に向かうベクトルのハーフベクトルを求める
    float3 H = normalize(L + V);

    // 各種ベクトルがどれくらい似ているかを内積を利用して求める
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));
    float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));

    // D項をベックマン分布を用いて計算する
    float D = Beckmann(microfacet, NdotH);

    // F項をSchlick近似を用いて計算する
    float F = SpcFresnel(f0, VdotH);

    // G項を求める
    float G = min(1.0f, min(2*NdotH*NdotV/VdotH, 2*NdotH*NdotL/VdotH));

    // m項を求める
    float m = PI * NdotV * NdotH;

    // ここまで求めた、値を利用して、Cook-Torranceモデルの鏡面反射を求める
    return max(F * D * G / m, 0.0);
}

/// <summary>
/// フレネル反射を考慮した拡散反射を計算
/// </summary>
/// <remark>
/// この関数はフレネル反射を考慮した拡散反射率を計算します
/// フレネル反射は、光が物体の表面で反射する現象のとこで、鏡面反射の強さになります
/// 一方拡散反射は、光が物体の内部に入って、内部錯乱を起こして、拡散して反射してきた光のことです
/// つまりフレネル反射が弱いときには、拡散反射が大きくなり、フレネル反射が強いときは、拡散反射が小さくなります
///
/// </remark>
/// <param name="N">法線</param>
/// <param name="L">光源に向かうベクトル。光の方向と逆向きのベクトル。</param>
/// <param name="V">視線に向かうベクトル。</param>
float CalcDiffuseFromFresnel(float3 N, float3 L, float3 V)
{
    // step-4 フレネル反射を考慮した拡散反射光を求める
    // 法線と光源に向かうベクトルがどれだけ似ているか
    float dotNL = saturate(dot(N,L));

    // 法線と視線に向かうベクトルがどれだけ似ているか
    float dotNV = saturate(dot(N,V));

    return (dotNL * dotNV);
}

/// <summary>
/// 頂点シェーダー
/// <summary>
SPSIn VSMain(SVSIn vsIn)
{
    SPSIn psIn;
    psIn.pos = mul(mWorld, vsIn.pos);
    psIn.worldPos = psIn.pos;
    psIn.pos = mul(mView, psIn.pos);
    psIn.pos = mul(mProj, psIn.pos);
    psIn.normal = normalize(mul(mWorld, vsIn.normal));
    psIn.tangent = normalize(mul(mWorld, vsIn.tangent));
    psIn.biNormal = normalize(mul(mWorld, vsIn.biNormal));
    psIn.uv = vsIn.uv;

    return psIn;
}

/// <summary>
/// ピクセルシェーダー
/// </summary>
float4 PSMain(SPSIn psIn) : SV_Target0
{
    // 法線を計算
    float3 normal = GetNormal(psIn.normal, psIn.tangent, psIn.biNormal, psIn.uv);

    // step-2 各種マップをサンプリングする
    float4 albedoColor = g_albedo.Sample(g_sampler, psIn.uv);
    float3 specColor = g_albedoColor; // スペキュラカラーはアルベドカラーと同じとみなす.
    float metallic = g_metallicSmoothMap.Sample(g_sampler, psIn.uv).r;
    float smooth = g_metallicSmoothMap.Sample(g_sampler, psIn.uv).a;

    // 視線に向かって伸びるベクトルを計算する
    float3 toEye = normalize(eyePos - psIn.worldPos);

    float3 lig = 0;
    for(int ligNo = 0; ligNo < NUM_DIRECTIONAL_LIGHT; ligNo++)
    {
        // step-3 シンプルなディズニーベースの拡散反射を実装する
        // フレネル反射
        float diffuseFromFresnel = CalcDiffuseFromFresnel(normal, -directionalLight[ligNo].direction, toEye);

        // 正規化Lambert拡散反射
        float NdotL = saturate(dot(normal, -directionalLight[ligNo].direction));
        float3 lambertDiffuse = directionalLight[ligNo].color * NdotL / PI;

        float3 diffuse = albedoColor * diffuseFromFresnel * lambertDiffuse;

        // step-5 Cook-Torranceモデルを利用した鏡面反射率を計算する
        // 金属性が強いものほどスペキュラカラー､そうでないものほど白に近づく
        spec *= lerp(float3(1.0f,1.0f,1.0f), specColor, metallic);

        // step-6 滑らかさを使って、拡散反射光と鏡面反射光を合成する
        lig += diffuse * (1.0f - smooth) + spec;
    }

    // 環境光による底上げ
    lig += ambientLight * albedoColor;

    float4 finalColor = 1.0f;
    finalColor.xyz = lig;
    return finalColor;
}

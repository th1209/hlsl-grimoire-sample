/*!
 * @brief ポイントライトの影響範囲をタイルベースで計算するコンピュートシェーダー
 */

// 一度に実行されるスレッド数
#define TILE_WIDTH 16
#define TILE_HEIGHT 16

// タイルの総数
#define TILE_SIZE (TILE_WIDTH * TILE_HEIGHT)

// ディレクションライト
struct DirectionLight
{
    float3 color;       // ライトのカラー
    float3 direction;   // ライトの方向
};

// ポイントライト
struct PointLight
{
    float3 position;        // 座標
    float3 positionInView;  // カメラ空間での座標
    float3 color;           // カラー
    float range;            // 範囲
};

static const int NUM_DIRECTION_LIGHT = 4;   // ディレクションライトの数
static const int MAX_POINT_LIGHT = 1000;    // ポイントライトの最大数

// 定数バッファー
cbuffer cbCameraParam : register(b0)
{
    float4x4 mtxProj : packoffset(c0);      // 投影行列
    float4x4 mtxProjInv : packoffset(c4);   //  投影行列の逆行列
    float4x4 mtxViewRot : packoffset(c8);
    float4 screenParam : packoffset(c12);   // スクリーンパラメーター（near, far, screenWidth, screenHeight）
};

cbuffer Light : register(b1)
{
    DirectionLight directionLight[NUM_DIRECTION_LIGHT];
    PointLight pointLight[MAX_POINT_LIGHT];
    float4x4 mViewProjInv;  // ビュープロジェクション行列の逆行列
    float3 eyePos;          // 視点
    float specPow;          // スペキュラの絞り
    int numPointLight;      // ポイントライトの数
};

// 入力
// 深度テクスチャ
Texture2D depthTexture : register(t0);

// 出力用のバッファー
RWStructuredBuffer<uint> rwLightIndices : register(u0); // ライトインデックスバッファー

// 共有メモリ
groupshared uint sMinZ; // タイルの最小深度
groupshared uint sMaxZ; // タイルの最大深度
groupshared uint sTileLightIndices[MAX_POINT_LIGHT];    // タイルに接触しているポイントライトのインデックス
groupshared uint sTileNumLights;                        // タイルに接触しているポイントライトの数

groupshared uint ligNum = 0;

/*!
 * @brief タイルごとの視推台平面を求める
 */
void GetTileFrustumPlane(out float4 frustumPlanes[6], uint3 groupId)
{
    // タイルの最大・最小深度を浮動小数点に変換
    float minTileZ = asfloat(sMinZ);
    float maxTileZ = asfloat(sMaxZ);

    float2 tileScale = screenParam.zw * rcp(float(2 * TILE_WIDTH));
    float2 tileBias = tileScale - float2(groupId.xy);

    float4 c1 = float4(mtxProj._11 * tileScale.x, 0.0, tileBias.x, 0.0);
    float4 c2 = float4(0.0, -mtxProj._22 * tileScale.y, tileBias.y, 0.0);
    float4 c4 = float4(0.0, 0.0, 1.0, 0.0);

    frustumPlanes[0] = c4 - c1;     // Right
    frustumPlanes[1] = c4 + c1;     // Left
    frustumPlanes[2] = c4 - c2;     // Top
    frustumPlanes[3] = c4 + c2;     // Bottom
    frustumPlanes[4] = float4(0.0, 0.0, 1.0, -minTileZ);
    frustumPlanes[5] = float4(0.0, 0.0, -1.0, maxTileZ);

    // 法線が正規化されていない4面についてだけ正規化する
    for (uint i = 0; i < 4; ++i)
    {
        frustumPlanes[i] *= rcp(length(frustumPlanes[i].xyz));
    }
}

/*!
 * @brief カメラ空間での座標を計算する
 */
float3 ComputePositionInCamera(uint2 globalCoords)
{
    float2 st = ((float2)globalCoords + 0.5) * rcp(screenParam.zw);
    st = st * float2(2.0, -2.0) - float2(1.0, -1.0);
    float3 screenPos;
    screenPos.xy = st.xy;
    screenPos.z = depthTexture.Load(uint3(globalCoords, 0.0f));
    float4 cameraPos = mul(mtxProjInv, float4(screenPos, 1.0f));

    return cameraPos.xyz / cameraPos.w;
}

/*!
 * @brief CSMain
 */
[numthreads(TILE_WIDTH, TILE_HEIGHT, 1)]
void CSMain(
    uint3 groupId          : SV_GroupID,
    uint3 dispatchThreadId : SV_DispatchThreadID,
    uint3 groupThreadId    : SV_GroupThreadID)
{
    // step-7 タイル内でのインデックスを求める
    // ※スレッドは､タイル内のピクセル数分生成されている
    uint groupIndex = groupThreadId.y * TILE_WIDTH + groupThreadId.x;

    // step-8 共有メモリを初期化する
    if(groupIndex == 0)
    {
        sTileNumLights = 0;
        sMinZ = 0x7F7FFFFF;
        sMaxZ = 0;
    }

    // step-9 このスレッドが担当するピクセルのカメラ空間での座標を計算する
    uint2 frameUV = dispatchThreadId.xy;
    float3 posInView = ComputePositionInCamera(frameUV);

    // step-10 全てのスレッドがここに到達するまで同期を取る(↑共有メモリ変数の初期化を待ちたいので)
    GroupMemoryBarrierWithGroupSync();

    // step-11 タイルの最大・最小深度を求める
    InterlockedMin(sMinZ, asuint(posInView.z));
    InterlockedMax(sMaxZ, asuint(posInView.z));

    // ここで同期を取り､タイルの最小/最大深度を正しいものにする
    GroupMemoryBarrierWithGroupSync();

    // step-12 タイルの視錘台を構成する6つの平面を求める
    float4 frustumPlanes[6];
    GetTileFrustumPlane(frustumPlanes, groupId);

    // step-13 タイルとポイントライトの衝突判定を行う
    // for文の条件に注目. スレッドごとに処理するライトを分散している.
    //   0番目のスレッド: 0番のポイントライト､256番のポイントライト...
    //   1番目のスレッド: 1番のポイントライト､257番のポイントライト...
    for (uint lightIndex = groupIndex; lightIndex < numPointLight; lightIndex += TILE_SIZE)
    {
        PointLight light = pointLight[lightIndex];

        bool inFrustum = true;
        for (uint i = 0; i < 6; ++i)
        {
            // ライトの座標と平面の法線とで内積を取り､ライトと平面の距離を計算
            float4 lp = float4(light.positionInView, 1.0f);
            float d = dot(frustumPlanes[i], lp);

            // ライトと平面の距離を使い､衝突判定を行う
            inFrustum = inFrustum && (d >= -light.range);
        }

        if (inFrustum)
        {
            // 衝突した場合､衝突したポイントライトの番号を､影響リストに積んでいく
            uint listIndex;
            InterlockedAdd(sTileNumLights, 1, listIndex);
            sTileLightIndices[listIndex] = lightIndex;
        }
    }

    // sTileLightIndicesの同期を取る
    GroupMemoryBarrierWithGroupSync();

    // step-14 ライトインデックスを出力バッファーに出力
    uint numCellX = (screenParam.z + TILE_WIDTH - 1) / TILE_WIDTH;
    uint tileIndex = floor(frameUV.x / TILE_WIDTH) + floor(frameUV.y / TILE_WIDTH) * numCellX;
    uint lightStart = numPointLight * tileIndex;
    for (uint lightIndex = groupIndex; lightIndex < sTileNumLights; lightIndex += TILE_SIZE)
    {
        rwLightIndices[lightStart + lightIndex] = sTileLightIndices[lightIndex];
    }

    // step-15 最後に番兵を設定する
    if ((groupIndex == 0) && (sTileNumLights < numPointLight))
    {
        rwLightIndices[lightStart + sTileNumLights] = 0xffffffff;
    }
}

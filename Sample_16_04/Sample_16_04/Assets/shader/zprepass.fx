/*!
 * @brief ZPrepass
 */

// step-4 ZPrepassシェーダーを実装する

cbuffer ModelCb: register(b0)
{
    float4x4 mWorld;
    float4x4 mView;
    float4x4 mProj;
};

struct SVSIn
{
    float4 pos : POSITION;
};

struct SPSIn
{
    float4 pos : SV_POSITION;
};

SPSIn VSMain(SVSIn vsIn, uniform bool hasSkin)
{
    SPSIn psIn;
    psIn.pos = mul(mWorld, vsIn.pos);
    psIn.pos = mul(mView, psIn.pos);
    psIn.pos = mul(mProj, psIn.pos);
    return psIn;
}

float4 PSMain(SPSIn psIn): SV_Target0
{
    return float4(psIn.pos.z, psIn.pos.z, psIn.pos.z, 1.0f);
}
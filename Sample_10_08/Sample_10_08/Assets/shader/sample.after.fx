/*!
 *@brief �Z�p�`�u���[
 */

// �u���[��������e�N�X�`���̕�
static const float BLUR_TEX_W = 1280.0f;

// �u���[��������e�N�X�`���̍���
static const float BLUR_TEX_H = 720.0f;

// �u���[���a�B���̐��l��傫������ƘZ�p�`�{�P���傫���Ȃ�
static const float BLUR_RADIUS = 8.0f;

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

cbuffer cb : register(b0)
{
    float4x4 mvp;       // MVP�s��
    float4 mulColor;    // ��Z�J���[
};

// step-6  �����A�Ίp���u���[�̏o�͍\���̂��`
struct PSOutput
{
    float4 color_0 : SV_Target0;    // �����u���[�̏o�͐�
    float4 color_1 : SV_Target1;    // �΂߃u���[�̏o�͐�
};

/*!
 *@brief ���_�V�F�[�_�[
 */
PSInput VSMain(VSInput In)
{
    PSInput psIn;
    psIn.pos = mul(mvp, In.pos);
    psIn.uv = In.uv;
    return psIn;
}

Texture2D<float4> srcTexture : register(t0); // �u���[��������O�̃I���W�i���e�N�X�`��

// �T���v���[�X�e�[�g
sampler g_sampler : register(s0);

/*!
 *@brief �����A�΂߃u���[�̃s�N�Z���V�F�[�_�[
 */
PSOutput PSVerticalDiagonalBlur(PSInput pIn)
{
    PSOutput psOut = (PSOutput)0;

    // �u���[��������e�N�X�`���̃J���[���擾
    float4 srcColor = srcTexture.Sample(
        g_sampler, pIn.uv );

    // step-7 �u���[���a�iBLUR_RADIUS�j����u���[�X�e�b�v�̒��������߂�
    float blurStepLen = BLUR_RADIUS / 4.0f;

    // step-8 ����������UV�I�t�Z�b�g���v�Z
    float2 uvOffset = float2(0.0f, 1.0f / BLUR_TEX_H);
    uvOffset *= blurStepLen;

    // step-9 ���������ɃJ���[���T���v�����O���ĕ��ς���
    // 1�X�e�b�v�i�߂�
    psOut.color_0 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset);

    // 2�X�e�b�v�i�߂�
    psOut.color_0 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 2);

    // 3�X�e�b�v�i�߂�
    psOut.color_0 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 3);

    // 4�X�e�b�v�i�߂�
    psOut.color_0 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 4);

    // ���ω�
    psOut.color_0 /= 4.0f;

    // step-10 �Ίp��������UV�I�t�Z�b�g���v�Z
    uvOffset.x = 0.86602f / BLUR_TEX_W;
    uvOffset.y = -0.5f / BLUR_TEX_H;
    uvOffset *= blurStepLen;

    // step-11 �Ίp�������ɃJ���[���T���v�����O���ĕ��ω�����
    psOut.color_1 = srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset);

    psOut.color_1 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 2);

    psOut.color_1 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 3);

    psOut.color_1 += srcTexture.Sample(
        g_sampler, pIn.uv + uvOffset * 4);

    psOut.color_1 += srcColor;
    psOut.color_1 /= 5.0f;

    // ���������ɕ��ω�
    psOut.color_1 += psOut.color_0;
    psOut.color_1 /= 2.0f;

    return psOut;
}

Texture2D<float4> blurTexture_0 : register(t0); // �u���[�e�N�X�`��_0�B1�p�X�ڂō쐬���ꂽ�e�N�X�`��
Texture2D<float4> blurTexture_1 : register(t1); // �u���[�e�N�X�`��_1�B1�p�X�ڂō쐬���ꂽ�e�N�X�`��

/*!
 *@brief �Z�p�`�쐬�u���[
 */
float4 PSRhomboidBlur(PSInput pIn) : SV_Target0
{
    // �u���[�X�e�b�v�̒��������߂�
    float blurStepLen = BLUR_RADIUS / 4.0f;

    // step-12 ���΂߉������ւ�UV�I�t�Z�b�g���v�Z����
    float2 uvOffset;
    uvOffset.x = 0.86602f / BLUR_TEX_W;
    uvOffset.y = -0.5f / BLUR_TEX_H;
    uvOffset *= blurStepLen;

    // step-13 ���΂߉������ɃJ���[���T���v�����O����
    float4 color = blurTexture_0.Sample(
        g_sampler, pIn.uv + uvOffset);

    color += blurTexture_0.Sample(
        g_sampler, pIn.uv + uvOffset * 2);

    color += blurTexture_0.Sample(
        g_sampler, pIn.uv + uvOffset * 3);

    color += blurTexture_0.Sample(
        g_sampler, pIn.uv + uvOffset * 4);

    // step-14 �E�΂߉������ւ�UV�I�t�Z�b�g���v�Z����
    uvOffset.x = -0.86602f / BLUR_TEX_W * blurStepLen;

    // step-15 �E�΂߉������ɃJ���[���T���v�����O����
    color += blurTexture_1.Sample(
        g_sampler, pIn.uv);

    color += blurTexture_1.Sample(
        g_sampler, pIn.uv + uvOffset);

    color += blurTexture_1.Sample(
        g_sampler, pIn.uv + uvOffset * 2);

    color += blurTexture_1.Sample(
        g_sampler, pIn.uv + uvOffset * 3);

    color += blurTexture_1.Sample(
        g_sampler, pIn.uv + uvOffset * 4);

    // step-16 ���ω�
    color /= 9.0f;

    return color;
}

#include "stdafx.h"
#include "system/system.h"

const int NUM_DIRECTIONAL_LIGHT = 4; // ディレクションライトの数

/// <summary>
/// ディレクションライト
/// </summary>
struct DirectionalLight
{
    Vector3 direction;  // ライトの方向
    float pad0;         // パディング
    Vector4 color;      // ライトのカラー
};

/// <summary>
/// ライト構造体
/// </summary>
struct Light
{
    DirectionalLight directionalLight[NUM_DIRECTIONAL_LIGHT]; // ディレクションライト
    Vector3 eyePos;                 // カメラの位置
    float specPow;                  // スペキュラの絞り
    Vector3 ambinetLight;           // 環境光
};

const int NUM_WEIGHTS = 8;
/// <summary>
/// ブラー用のパラメーター
/// </summary>
struct SBlurParam
{
    float weights[NUM_WEIGHTS];
};

// 関数宣言
void InitRootSignature(RootSignature& rs);
void InitModel(Model& plModel);
///////////////////////////////////////////////////////////////////
// ウィンドウプログラムのメイン関数
///////////////////////////////////////////////////////////////////
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow)
{
    // ゲームの初期化
    InitGame(hInstance, hPrevInstance, lpCmdLine, nCmdShow, TEXT("Game"));

    //////////////////////////////////////
    //  ここから初期化を行うコードを記述する
    //////////////////////////////////////

    RootSignature rs;
    InitRootSignature(rs);

    // step-1 メインレンダリングターゲットを作成する
    RenderTarget mainRenderTarget;
    mainRenderTarget.Create(1280, 720, 1, 1,
        DXGI_FORMAT_R32G32B32A32_FLOAT,// HDRレンダリングなので､カラーバッファのフォーマットを32bit浮動小数点に
        DXGI_FORMAT_D32_FLOAT);

    // step-2 強い光のライトを用意する
    Light light;
    light.directionalLight[0].color.x = 5.8f;
    light.directionalLight[0].color.y = 5.8f;
    light.directionalLight[0].color.z = 5.8f;

    light.directionalLight[0].direction.x = 0.0f;
    light.directionalLight[0].direction.y = 0.0f;
    light.directionalLight[0].direction.z = -1.0f;
    light.directionalLight[0].direction.Normalize();

    light.ambinetLight.x = 0.5f;
    light.ambinetLight.y = 0.5f;
    light.ambinetLight.z = 0.5f;
    light.eyePos = g_camera3D->GetPosition();


    // モデルの初期化情報を設定する
    ModelInitData plModelInitData;

    // tkmファイルを指定する
    plModelInitData.m_tkmFilePath = "Assets/modelData/sample.tkm";

    // シェーダーファイルを指定する
    plModelInitData.m_fxFilePath = "Assets/shader/sample3D.fx";

    // ユーザー拡張の定数バッファーに送るデータを指定する
    plModelInitData.m_expandConstantBuffer = &light;

    // ユーザー拡張の定数バッファーに送るデータのサイズを指定する
    plModelInitData.m_expandConstantBufferSize = sizeof(light);

    // レンダリングするカラーバッファーのフォーマットを指定する
    plModelInitData.m_colorBufferFormat[0] = DXGI_FORMAT_R32G32B32A32_FLOAT;

    // 設定した初期化情報をもとにモデルを初期化する
    Model plModel;
    plModel.Init(plModelInitData);

    // step-3 輝度抽出用のレンダリングターゲットを作成
    RenderTarget luminnceRenderTarget;
    luminnceRenderTarget.Create(1280, 720, 1, 1,
        DXGI_FORMAT_R32G32B32A32_FLOAT,// HDRレンダリングなので､カラーバッファのフォーマットを32bit浮動小数点に
        DXGI_FORMAT_D32_FLOAT);


    // step-4 輝度抽出用のスプライトを初期化
    SpriteInitData luminanceSpriteInitData;
    luminanceSpriteInitData.m_fxFilePath = "Assets/shader/samplePostEffect.fx";
    luminanceSpriteInitData.m_vsEntryPointFunc = "VSMain";
    luminanceSpriteInitData.m_psEntryPoinFunc = "PSSamplingLuminance";
    luminanceSpriteInitData.m_width = 1280;
    luminanceSpriteInitData.m_height = 720;
    luminanceSpriteInitData.m_textures[0] = &mainRenderTarget.GetRenderTargetTexture();
    luminanceSpriteInitData.m_colorBufferFormat[0] = DXGI_FORMAT_R32G32B32A32_FLOAT;

    Sprite luminanceSprite;
    luminanceSprite.Init(luminanceSpriteInitData);

    

    // step-5 ガウシアンブラーを初期化
    GaussianBlur gaussianBlur;
    gaussianBlur.Init(&luminnceRenderTarget.GetRenderTargetTexture());

    // step-6 ボケ画像を加算合成するスプライトを初期化
    SpriteInitData finalSpriteInitData;
    finalSpriteInitData.m_textures[0] = &gaussianBlur.GetBokeTexture();
    finalSpriteInitData.m_width = 1280;
    finalSpriteInitData.m_height = 720;
    finalSpriteInitData.m_fxFilePath = "Assets/shader/sample2D.fx";
    finalSpriteInitData.m_alphaBlendMode = AlphaBlendMode_Add;
    finalSpriteInitData.m_colorBufferFormat[0] = DXGI_FORMAT_R32G32B32A32_FLOAT;

    Sprite finalSprite;
    finalSprite.Init(finalSpriteInitData);


    // step-7 テクスチャを貼り付けるためのスプライトを初期化する
    SpriteInitData spriteInitData;
    spriteInitData.m_textures[0] = &mainRenderTarget.GetRenderTargetTexture();
    spriteInitData.m_width = 1280;
    spriteInitData.m_height = 720;
    spriteInitData.m_fxFilePath = "Assets/shader/sample2D.fx";
    Sprite copyToFrameBufferSprite;
    copyToFrameBufferSprite.Init(spriteInitData);
        

    //////////////////////////////////////
    // 初期化を行うコードを書くのはここまで！！！
    //////////////////////////////////////
    auto& renderContext = g_graphicsEngine->GetRenderContext();

    // ここからゲームループ
    while (DispatchWindowMessage())
    {
        // 1フレームの開始
        g_engine->BeginFrame();

        //////////////////////////////////////
        // ここから絵を描くコードを記述する
        //////////////////////////////////////

        // step-8 レンダリングターゲットをmainRenderTargetに変更する
        renderContext.WaitUntilToPossibleSetRenderTarget(mainRenderTarget);
        renderContext.SetRenderTargetAndViewport(mainRenderTarget);
        renderContext.ClearRenderTargetView(mainRenderTarget);

        // step-9 mainRenderTargetに各種モデルを描画する
        plModel.Draw(renderContext);
        renderContext.WaitUntilFinishDrawingToRenderTarget(mainRenderTarget);

        // step-10 輝度抽出
        renderContext.WaitUntilToPossibleSetRenderTarget(luminnceRenderTarget);
        renderContext.SetRenderTargetAndViewport(luminnceRenderTarget);
        renderContext.ClearRenderTargetView(luminnceRenderTarget);

        luminanceSprite.Draw(renderContext);
        renderContext.WaitUntilFinishDrawingToRenderTarget(luminnceRenderTarget);

        // step-11 ガウシアンブラーを実行する
        gaussianBlur.ExecuteOnGPU(renderContext, 20);

        // step-12 ボケ画像をメインレンダリングターゲットに加算合成
        renderContext.WaitUntilToPossibleSetRenderTarget(mainRenderTarget);
        renderContext.SetRenderTargetAndViewport(mainRenderTarget);
        finalSprite.Draw(renderContext);
        renderContext.WaitUntilFinishDrawingToRenderTarget(mainRenderTarget);

        // step-13 メインレンダリングターゲットの絵をフレームバッファーにコピー
        renderContext.SetRenderTarget(
            g_graphicsEngine->GetCurrentFrameBuffuerRTV(),
            g_graphicsEngine->GetCurrentFrameBuffuerDSV()
        );
        copyToFrameBufferSprite.Draw(renderContext);

        // ライトの強さを変更する
        light.directionalLight[0].color.x += g_pad[0]->GetLStickXF() * 0.5f;
        light.directionalLight[0].color.y += g_pad[0]->GetLStickXF() * 0.5f;
        light.directionalLight[0].color.z += g_pad[0]->GetLStickXF() * 0.5f;

        //////////////////////////////////////
        //絵を描くコードを書くのはここまで！！！
        //////////////////////////////////////
        // 1フレーム終了
        g_engine->EndFrame();
    }
    return 0;
}

// ルートシグネチャの初期化
void InitRootSignature( RootSignature& rs )
{
    rs.Init(D3D12_FILTER_MIN_MAG_MIP_LINEAR,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP);
}

﻿#include "stdafx.h"
#include "system/system.h"
#include "RenderingEngine.h"
#include "ModelRender.h"

// 関数宣言
void InitRootSignature(RootSignature& rs);

///////////////////////////////////////////////////////////////////
// ウィンドウプログラムのメイン関数
///////////////////////////////////////////////////////////////////
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow)
{
    // ゲームの初期化
    InitGame(hInstance, hPrevInstance, lpCmdLine, nCmdShow, TEXT("Game"));

    //////////////////////////////////////
    // ここから初期化を行うコードを記述する
    //////////////////////////////////////

    // ルートシグネチャを作成
    RootSignature rootSignature;
    InitRootSignature(rootSignature);

    //レンダリングエンジンを初期化
    myRenderer::RenderingEngine renderingEngine;
    renderingEngine.Init();

    // 背景モデルのレンダラーを初期化
    myRenderer::ModelRender bgModelRender;
    bgModelRender.InitDeferredRendering(renderingEngine, "Assets/modelData/bg/bg.tkm", true);

    // step-1 ティーポットの描画処理を初期化する
    myRenderer::ModelInitDataFR modelInitData;
    modelInitData.m_tkmFilePath = "Assets/modelData/teapot.tkm";
    modelInitData.m_fxFilePath = "Assets/shader/sample.fx";
    // レンダリングエンジンのZPrepassで作成された深度テクスチャを利用
    modelInitData.m_expandShaderResourceView[0] = &renderingEngine.GetZPrepassDepthTexture();

    myRenderer::ModelRender teapotModelRender;
    // フォワードレンダリングで描画
    teapotModelRender.InitForwardRendering(renderingEngine, modelInitData);
    teapotModelRender.SetShadowCasterFlag(true);
    teapotModelRender.UpdateWorldMatrix({ 0.0f, 50.0f, 0.0f }, g_quatIdentity, g_vec3One);

    //////////////////////////////////////
    // 初期化を行うコードを書くのはここまで！！！
    //////////////////////////////////////
    auto& renderContext = g_graphicsEngine->GetRenderContext();

    // ここからゲームループ
    while (DispatchWindowMessage())
    {
        // レンダリング開始
        g_engine->BeginFrame();
        g_camera3D->MoveForward(g_pad[0]->GetLStickYF());
        g_camera3D->MoveRight(g_pad[0]->GetLStickXF());
        g_camera3D->MoveUp(g_pad[0]->GetRStickYF());

        //////////////////////////////////////
        // ここから絵を描くコードを記述する
        //////////////////////////////////////

        bgModelRender.Draw();

        // step-2 ティーポットを描画する
        teapotModelRender.Draw();

        //レンダリングエンジンを実行
        renderingEngine.Execute(renderContext);

        /////////////////////////////////////////
        // 絵を描くコードを書くのはここまで！！！
        //////////////////////////////////////
        // レンダリング終了
        g_engine->EndFrame();
    }

    return 0;
}

// ルートシグネチャの初期化
void InitRootSignature(RootSignature& rs)
{
    rs.Init(D3D12_FILTER_MIN_MAG_MIP_LINEAR,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP,
            D3D12_TEXTURE_ADDRESS_MODE_WRAP);
}

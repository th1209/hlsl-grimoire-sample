#include "stdafx.h"
#include "system/system.h"
#include "Bitmap.h"
#include "sub.h"

// 構造体定義
// テクスチャ情報用の定数バッファー
struct TexInfo
{
    int originalTexSize[2]; // オリジナルテクスチャのサイズ
    int xBlurTexSize[2];    // Xブラーの出力先のテクスチャのサイズ
    int yBlurTexSize[2];    // Yブラーの出力先のテクスチャのサイズ
};


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

    // ルートシグネチャの初期化
    RootSignature rs;
    InitRootSignature(rs);

    // step-1 画像データをメインメモリ上にロードする
    Bitmap imagebmp;
    imagebmp.Load("Assets/image/original.bmp");

    // step-2 ブレンディング係数を送るための定数バッファーを作成する
    ConstantBuffer weightsCB;
    weightsCB.Init(sizeof(float) * 8, nullptr);

    // step-3 テクスチャ情報を送るための定数バッファーを作成する
    TexInfo texInfo;
    texInfo.originalTexSize[0] = imagebmp.GetWidth();
    texInfo.originalTexSize[1] = imagebmp.GetHeight();
    texInfo.xBlurTexSize[0] = texInfo.originalTexSize[0] / 2;
    texInfo.xBlurTexSize[1] = texInfo.originalTexSize[1];
    texInfo.yBlurTexSize[0] = texInfo.originalTexSize[0] / 2;
    texInfo.yBlurTexSize[1] = texInfo.originalTexSize[1] / 2;
    ConstantBuffer texInfoCB;
    texInfoCB.Init(sizeof(texInfo), &texInfo);

    // step-4 各種構造化バッファーを作成する
    StructuredBuffer inputImageBmpSB;
    inputImageBmpSB.Init(
        imagebmp.GetPixelSizeInBytes(), // 1ピクセルのサイズ
        imagebmp.GetNumPixel(),
        imagebmp.GetImageAddress() // 画像データの先頭アドレス
    );

    // 横方向にブラーを書けた画像を出力するためのバッファ
    RWStructuredBuffer outputXBlurImageRWSB;
    outputXBlurImageRWSB.Init(
        imagebmp.GetPixelSizeInBytes(),
        imagebmp.GetNumPixel() / 2, // 横方向にダウンサンプリングされているので､ピクセル数は1/2
        nullptr
    );

    // 縦方向にブラーを書けた画像を出力するためのバッファ
    RWStructuredBuffer outputYBlurImageRWSB;
    outputYBlurImageRWSB.Init(
        imagebmp.GetPixelSizeInBytes(),
        imagebmp.GetNumPixel() / 4, // 横・縦方向にダウンサンプリングされているので､ピクセル数は1/4
        nullptr
    );

    // 最終結果を出力するためのバッファ
    RWStructuredBuffer finalImageRWSB;
    finalImageRWSB.Init(
        imagebmp.GetPixelSizeInBytes(),
        imagebmp.GetNumPixel(),
        nullptr
    );

    // step-5 各種ディスクリプタヒープを作成する(コンピュートシェーダーへのディスパッチが3回なので､3つ必要)
    DescriptorHeap xBlurDS;
    xBlurDS.RegistShaderResource(0, inputImageBmpSB);
    xBlurDS.RegistConstantBuffer(0, weightsCB);
    xBlurDS.RegistConstantBuffer(1, texInfoCB);
    xBlurDS.RegistUnorderAccessResource(0, outputXBlurImageRWSB);
    xBlurDS.Commit();

    DescriptorHeap yBlurDS;
    yBlurDS.RegistShaderResource(0, outputXBlurImageRWSB);
    yBlurDS.RegistConstantBuffer(0, weightsCB);
    yBlurDS.RegistConstantBuffer(1, texInfoCB);
    yBlurDS.RegistUnorderAccessResource(0, outputYBlurImageRWSB);
    yBlurDS.Commit();

    DescriptorHeap finalDS;
    finalDS.RegistShaderResource(0, outputYBlurImageRWSB);
    finalDS.RegistConstantBuffer(0, weightsCB);
    finalDS.RegistConstantBuffer(1, texInfoCB);
    finalDS.RegistUnorderAccessResource(0, finalImageRWSB);
    finalDS.Commit();

    // step-6 各種シェーダーのロード&パイプラインステートを作成する(ディスパッチの度にシェーダーが変更されるため､パイプラインステートも3つ必要)
    Shader xblurCS;
    xblurCS.LoadCS("Assets/shader/sample.fx", "XBlur");
    PipelineState xBlurPipelineState;
    InitPipelineState(rs, xBlurPipelineState, xblurCS);

    Shader yblurCS;
    yblurCS.LoadCS("Assets/shader/sample.fx", "YBlur");
    PipelineState yBlurPipelineState;
    InitPipelineState(rs, yBlurPipelineState, yblurCS);

    Shader finalCS;
    finalCS.LoadCS("Assets/shader/sample.fx", "Final");
    PipelineState finalPipelineState;
    InitPipelineState(rs, finalPipelineState, finalCS);

    //////////////////////////////////////
    // 初期化を行うコードを書くのはここまで！！！
    //////////////////////////////////////
    auto& renderContext = g_graphicsEngine->GetRenderContext();

    // ここからゲームループ
    while (DispatchWindowMessage())
    {
        // フレーム開始
        g_engine->BeginFrame();

        // ガウス関数を使って重みを計算し、グラフィックスメモリに転送
        // ※毎ループする必要はない. ここでは1回でループを抜けるのでこういうコード.
        float total = 0;
        float weights[8];
        for (int i = 0; i < 8; i++)
        {
            weights[i] = expf(-0.5f * (float)(i * i) / 100.0f);
            if (i == 0)
            {
                total += weights[i];
            }
            else
            {
                total += 2.0f * weights[i];
            }
        }
        // 規格化
        for (int i = 0; i < 8; i++)
        {
            weights[i] /= total;
        }

        // step-7 重みテーブルをVRAMに転送
        weightsCB.CopyToVRAM(weights);

        //////////////////////////////////////
        // ここからDirectComputeへのディスパッチ命令
        //////////////////////////////////////
        renderContext.SetComputeRootSignature(rs);

        // step-8 各種コンピュートシェーダーをディスパッチ
        // ※スレッド数は[numthreads(4, 4, 1)]なので､1/4している
        renderContext.SetPipelineState(xBlurPipelineState);
        renderContext.SetComputeDescriptorHeap(xBlurDS);
        renderContext.Dispatch(texInfo.xBlurTexSize[0] / 4, texInfo.xBlurTexSize[1] / 4, 1);

        renderContext.SetPipelineState(yBlurPipelineState);
        renderContext.SetComputeDescriptorHeap(yBlurDS);
        renderContext.Dispatch(texInfo.yBlurTexSize[0] / 4, texInfo.yBlurTexSize[1] / 4, 1);

        renderContext.SetPipelineState(finalPipelineState);
        renderContext.SetComputeDescriptorHeap(finalDS);
        renderContext.Dispatch(texInfo.originalTexSize[0] / 4, texInfo.originalTexSize[1] / 4, 1);

        // フレーム終了
        g_engine->EndFrame();

        // step-9 画像を取得し、保存する
        imagebmp.Copy(finalImageRWSB.GetResourceOnCPU());
        imagebmp.Save("Assets/image/blur.bmp");

        MessageBox(nullptr, L"完成", L"通知", MB_OK);
        // デストロイ
        DestroyWindow(g_hWnd);
    }
    return 0;
}

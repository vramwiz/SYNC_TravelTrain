unit SYNC_TravelTrain_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 旅行列車をメディアオブジェクトとして登録し、各インスタンスの描画資源を管理する。

interface

uses AviUtl2FilterTypes;

const
  TRAVELTRAIN_REQUIRED_VERSION = 2011600;

// DLL所有のテーブルを返す。呼び出し側では解放しない。
function GetTravelTrainFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses System.SysUtils, System.SyncObjs, Winapi.Windows, PluginFilterTable,
  TravelTrain_Settings, TravelTrain_Parameters, TravelTrain_Renderer;

type
  TTrainSession = class
    Lock: TCriticalSection;
    Renderer: TTrainRenderer;
    constructor Create;
    destructor Destroy; override;
  end;

var
  TableInitialized: Boolean;

constructor TTrainSession.Create;
begin
  inherited;
  Lock := TCriticalSection.Create;
  Renderer := TTrainRenderer.Create;
end;

destructor TTrainSession.Destroy;
begin
  Renderer.Free;
  Lock.Free;
  inherited;
end;

function CreateTrain(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TTrainSession.Create;
  except
    // 失敗時は nil をホストへ返す。
  end;
end;

procedure DestroyTrain(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TTrainSession(UserData).Free;
  except
    // DLL の外へ例外を送出しない。
  end;
end;

function RenderTrain(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  S: TTrainSettings;
  Session: TTrainSession;
  Width, Height: Integer;
begin
  Result := 0;
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) or
    not Assigned(Video^.SetImageData) then Exit;
  try
    S := ReadTrainSettings;
    Width := Round(S.Tracks[ttWidth]);
    Height := Round(S.Tracks[ttHeight]);
    if Video^.Scene <> nil then
    begin
      if Width = 0 then Width := Video^.Scene^.Width;
      if Height = 0 then Height := Video^.Scene^.Height;
    end;
    if (Width <= 0) or (Height <= 0) or (Width > TRAIN_MAX_DIMENSION) or
      (Height > TRAIN_MAX_DIMENSION) or (Int64(Width) * Height > TRAIN_MAX_PIXELS) then Exit;
    Session := TTrainSession(Video^.UserData);
    Session.Lock.Acquire;
    try
      Session.Renderer.Render(Video, Width, Height, S, Video^.Object_^.Time);
    finally
      Session.Lock.Release;
    end;
    Result := 1;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_TravelTrain video: ' + E.Message));
  end;
end;

function GetTravelTrainFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      '旅行列車', 'SYNC', '旅行列車 / SYNC_TravelTrain v1.0.0', RenderTrain, nil);
    RegisterTrainParameters;
    GetPluginTable^.Func_Create := CreateTrain;
    GetPluginTable^.Func_Destroy := DestroyTrain;
    TableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.

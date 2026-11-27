unit TravelTrain_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// シーン、列車、レイヤー、設定項目の初期値を定義する。

interface

const
  DESIGN_W = 1280;
  DESIGN_H = 720;
  RUN_BODY_BOTTOM = 625;
  RUN_RAIL_Y = 690;
  RUN_TRAIN_RISE = 36;
  WIDE_CAR_LENGTH = 820;
  WIDE_TRAIN_SCALE = 1.5;
  WIDE_CAR_COUNT = 3;
  WIDE_TRAIN_NOSE = 1116;
  WIDE_DEPART_DISTANCE = DESIGN_W - WIDE_TRAIN_NOSE +
    WIDE_CAR_COUNT * WIDE_CAR_LENGTH * WIDE_TRAIN_SCALE + 48;
  WIDE_ARRIVAL_RAIL_Y = 645;
  WIDE_DEPARTURE_RAIL_Y = 568;
  TRAIN_MAX_DIMENSION = 8192;
  TRAIN_MAX_PIXELS = 33554432;

type
  TTrainScene = (tsArrival, tsBoard, tsRun, tsExit, tsDeparture);
  TTrainStyle = (trStainless, trPainted, trExpress, trStreamlined);
  TTrainScenery = (scCountryside, scTown, scCoast, scResidential);
  TTrainLayer = (lyArrivalPlatform, lyArrivalTrain, lyBoardPlatform, lyBoardDoors,
    lyBoardCabin, lyRunRear, lyRunFront, lyExitRear, lyExitDoors, lyDeparture);
  TTrainTrack = (ttArrivalBefore, ttArrivalMove, ttArrivalAfter,
    ttDoorBefore, ttDoorOpen, ttDoorHold, ttDoorClose, ttDoorAfter,
    ttRunBefore, ttRunAccelerate, ttRunCruise, ttRunBrake, ttRunAfter,
    ttExitBefore, ttExitOpen, ttExitHold, ttExitClose, ttExitAfter,
    ttDepartBefore, ttDepartMove, ttDepartAfter,
    ttSpeed, ttElevation, ttZoom, ttSeed, ttWidth, ttHeight);
  TTrainTracks = array[TTrainTrack] of Double;
  TTrainLayers = set of TTrainLayer;
  TTrainColors = record
    Body, Stripe: Cardinal;
  end;
  TTrainSettings = record
    Scene: TTrainScene;
    Style: TTrainStyle;
    Scenery: TTrainScenery;
    Colors: TTrainColors;
    Layers: TTrainLayers;
    ForegroundPoles: Boolean;
    Tracks: TTrainTracks;
  end;
  TTrackDefinition = record
    Name: PWideChar;
    Initial, Minimum, Maximum, Step: Double;
  end;
  TTrackRange = record
    First, Last: TTrainTrack;
  end;

const
  SCENE_NAMES: array[TTrainScene] of PWideChar = ('到着', '乗車', '走行', '降車', '発車');
  STYLE_NAMES: array[TTrainStyle] of PWideChar = ('通勤電車（ステンレス車体）',
    '通勤電車（塗装車体）', '特急電車（箱型）', '特急電車（流線型）');
  SCENERY_NAMES: array[TTrainScenery] of PWideChar = ('田園', 'ビル街', '海岸', '住宅街');
  LAYER_NAMES: array[TTrainLayer] of PWideChar = ('到着：ホーム背景', '到着：列車本体',
    '乗車：ホーム背景', '乗車：扉', '乗車：車内', '走行：風景・車内・座席',
    '走行：車体・窓・前景物', '降車：ホーム・車体・車内', '降車：扉', '発車：ホーム・列車');
  SCENE_LAYERS: array[TTrainScene] of TTrainLayers = ([lyArrivalPlatform, lyArrivalTrain],
    [lyBoardPlatform, lyBoardDoors, lyBoardCabin], [lyRunRear, lyRunFront],
    [lyExitRear, lyExitDoors], [lyDeparture]);
  SCENE_TIMES: array[TTrainScene] of TTrackRange = (
    (First: ttArrivalBefore; Last: ttArrivalAfter), (First: ttDoorBefore; Last: ttDoorAfter),
    (First: ttRunBefore; Last: ttRunAfter), (First: ttExitBefore; Last: ttExitAfter),
    (First: ttDepartBefore; Last: ttDepartAfter)
  );
  TRAIN_PALETTES: array[TTrainStyle] of TTrainColors = (
    (Body: $BFCAD0; Stripe: $197F78), (Body: $E7DBAB; Stripe: $B36539),
    (Body: $E5DED0; Stripe: $883F55), (Body: $D8E6EA; Stripe: $365D9B)
  );
  TRAIN_TRACKS: array[TTrainTrack] of TTrackDefinition = (
    (Name:'到着前待機時間'; Initial:0.65; Minimum:0; Maximum:120; Step:0.01),
    (Name:'到着時間'; Initial:3.25; Minimum:0; Maximum:120; Step:0.01),
    (Name:'到着・停止後待機時間'; Initial:0.75; Minimum:0; Maximum:120; Step:0.01),
    (Name:'開扉前待機時間'; Initial:0.45; Minimum:0; Maximum:120; Step:0.01),
    (Name:'開扉時間'; Initial:0.65; Minimum:0; Maximum:120; Step:0.01),
    (Name:'開放時間'; Initial:2.35; Minimum:0; Maximum:120; Step:0.01),
    (Name:'閉扉時間'; Initial:0.65; Minimum:0; Maximum:120; Step:0.01),
    (Name:'閉扉後待機時間'; Initial:0.45; Minimum:0; Maximum:120; Step:0.01),
    (Name:'走行・発車前待機時間'; Initial:0.5; Minimum:0; Maximum:120; Step:0.01),
    (Name:'加速時間'; Initial:2.0; Minimum:0; Maximum:120; Step:0.01),
    (Name:'走行時間'; Initial:5.0; Minimum:0; Maximum:120; Step:0.01),
    (Name:'減速時間'; Initial:2.2; Minimum:0; Maximum:120; Step:0.01),
    (Name:'走行・停止後待機時間'; Initial:0.6; Minimum:0; Maximum:120; Step:0.01),
    (Name:'降車・開扉前待機時間'; Initial:0.35; Minimum:0; Maximum:120; Step:0.01),
    (Name:'降車・開扉時間'; Initial:0.65; Minimum:0; Maximum:120; Step:0.01),
    (Name:'降車・開放時間'; Initial:2.10; Minimum:0; Maximum:120; Step:0.01),
    (Name:'降車・閉扉時間'; Initial:0.65; Minimum:0; Maximum:120; Step:0.01),
    (Name:'降車・閉扉後待機時間'; Initial:0.45; Minimum:0; Maximum:120; Step:0.01),
    (Name:'発車前待機時間'; Initial:0.85; Minimum:0; Maximum:120; Step:0.01),
    (Name:'発車時間'; Initial:3.1; Minimum:0; Maximum:120; Step:0.01),
    (Name:'発車後待機時間'; Initial:0.7; Minimum:0; Maximum:120; Step:0.01),
    (Name:'走行速度（px/秒）'; Initial:510; Minimum:0; Maximum:2000; Step:1),
    (Name:'走行高さ'; Initial:0; Minimum:-1; Maximum:12; Step:0.01),
    (Name:'走行構図のズーム（%）'; Initial:100; Minimum:55; Maximum:145; Step:1),
    (Name:'風景シード'; Initial:27; Minimum:0; Maximum:1000000; Step:1),
    (Name:'描画幅（0＝シーン幅）'; Initial:0; Minimum:0; Maximum:TRAIN_MAX_DIMENSION; Step:1),
    (Name:'描画高さ（0＝シーン高さ）'; Initial:0; Minimum:0; Maximum:TRAIN_MAX_DIMENSION; Step:1)
  );

// 標準配置とシーンごとのリセット値を返す。最初の配置では全レイヤーが有効。
function DefaultTrainSettings(Scene: TTrainScene = tsArrival): TTrainSettings;
// トラックの非有限値を初期値へ置換し、描画に使える範囲へ制限する。
function TrainTrackValue(Track: TTrainTrack; Value: Double): Double;

implementation

uses System.Math;

function DefaultTrainSettings(Scene: TTrainScene): TTrainSettings;
var
  Track: TTrainTrack;
begin
  Result := Default(TTrainSettings);
  Result.Scene := Scene;
  Result.Scenery := scTown;
  Result.Colors := TRAIN_PALETTES[Result.Style];
  Result.Layers := [Low(TTrainLayer)..High(TTrainLayer)];
  Result.ForegroundPoles := True;
  for Track := Low(TTrainTrack) to High(TTrainTrack) do
    Result.Tracks[Track] := TRAIN_TRACKS[Track].Initial;
end;

function TrainTrackValue(Track: TTrainTrack; Value: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Exit(TRAIN_TRACKS[Track].Initial);
  Result := EnsureRange(Value, TRAIN_TRACKS[Track].Minimum, TRAIN_TRACKS[Track].Maximum);
end;

end.

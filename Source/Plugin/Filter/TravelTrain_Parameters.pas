unit TravelTrain_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// プリセットと各シーンの設定をAviUtl2へ登録し、描画用の値を取り出す。

interface

uses TravelTrain_Settings;

// DLLが所有し、アドレスが固定された設定項目をフィルターテーブルへ登録する。
procedure RegisterTrainParameters;
// 現在の値をコピーする。描画からオブジェクトの保存値は変更しない。
function ReadTrainSettings: TTrainSettings;

implementation

uses System.Math, System.SysUtils, Winapi.Windows, AviUtl2FilterTypes, PluginFilterTable;

const
  HIDE_NOT_EQUAL = 1; // FILTER_ITEM_HIDE_RULE::OPERATOR::NOT_EQUAL
  TIME_GROUPS: array[TTrainScene] of PWideChar = (
    '時間（秒）・到着', '時間（秒）・乗車', '時間（秒）・走行', '時間（秒）・降車', '時間（秒）・発車');
  HIDE_GREATER = 2;
  HIDE_LESS = 3;
  SCENERY_GROUP = '風景';
  // 並び順を変更しても、既存プロジェクトの背景の識別値は維持する。
  SCENERY_ORDER: array[0..Ord(High(TTrainScenery))] of TTrainScenery =
    (scTown, scResidential, scCountryside, scCoast);
  SIDE_VIEW_ONLY: array[0..1] of TTrainTrack = (ttSpeed, ttZoom);

var
  SceneItem, StyleItem, SceneryItem: TFILTER_ITEM_SELECT;
  SceneOptions: array[0..Ord(High(TTrainScene)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  StyleOptions: array[0..Ord(High(TTrainStyle)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  SceneryOptions: array[0..Ord(High(TTrainScenery)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  SceneButton, StyleButton: TFILTER_ITEM_BUTTON;
  BodyItem, StripeItem: TFILTER_ITEM_COLOR;
  PoleItem: TFILTER_ITEM_CHECK;
  Tracks: array[TTrainTrack] of TFILTER_ITEM_TRACK;
  Checks: array[TTrainLayer] of TFILTER_ITEM_CHECK;
  TimeGroup, TimeEnd: array[TTrainScene] of TFILTER_ITEM_GROUP;
  LayerGroup, SizeGroup, SceneryGroup, ColorGroup: TFILTER_ITEM_GROUP;
  LayerEnd, SizeEnd, SceneryEnd, ColorEnd: TFILTER_ITEM_GROUP;
  HideTime: array[TTrainScene] of TFILTER_ITEM_HIDE_RULE;
  HideLayer: array[TTrainLayer] of TFILTER_ITEM_HIDE_RULE;
  HideBeforeSideView, HideAfterSideView: array[0..High(SIDE_VIEW_ONLY)] of TFILTER_ITEM_HIDE_RULE;
  HidePole: TFILTER_ITEM_HIDE_RULE;

procedure SetValue(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Name: PWideChar;
  const Value: string);
var
  Encoded: UTF8String;
begin
  Encoded := UTF8String(Value);
  if not Edit^.SetObjectItemValue(Obj, Effect, Name, PAnsiChar(Encoded)) then
    OutputDebugString(PWideChar('SYNC_TravelTrain preset: ' + string(Name)));
end;

function Selection(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect: PWideChar;
  const Selector: TFILTER_ITEM_SELECT; const Names: array of PWideChar): Integer;
var
  I: Integer;
  Saved: PAnsiChar;
  Value: string;
begin
  Result := EnsureRange(Selector.Value, 0, High(Names));
  if not Assigned(Edit^.GetObjectItemValue) then Exit;
  Saved := Edit^.GetObjectItemValue(Obj, Effect, Selector.Name);
  if Saved = nil then Exit;
  Value := string(UTF8String(Saved));
  for I := 0 to High(Names) do
    if Value = string(Names[I]) then Exit(I);
end;

procedure ApplyStyle(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;
var
  Colors: TTrainColors;
begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    Colors := TRAIN_PALETTES[TTrainStyle(Selection(Edit, Obj, Effect, StyleItem, STYLE_NAMES))];
    SetValue(Edit, Obj, Effect, BodyItem.Name, IntToHex(Colors.Body, 6));
    SetValue(Edit, Obj, Effect, StripeItem.Name, IntToHex(Colors.Stripe, 6));
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_TravelTrain style: ' + E.Message));
  end;
end;

procedure ApplyScene(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;
var
  S: TTrainSettings;
  Layer: TTrainLayer;
  procedure ResetTracks(First, Last: TTrainTrack);
  var
    T: TTrainTrack;
  begin
    for T := First to Last do
      SetValue(Edit, Obj, Effect, Tracks[T].Name,
        FloatToStr(S.Tracks[T], TFormatSettings.Invariant));
  end;
begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    S := DefaultTrainSettings(TTrainScene(Selection(Edit, Obj, Effect, SceneItem, SCENE_NAMES)));
    ResetTracks(SCENE_TIMES[S.Scene].First, SCENE_TIMES[S.Scene].Last);
    for Layer := Low(TTrainLayer) to High(TTrainLayer) do
      if Layer in SCENE_LAYERS[S.Scene] then SetValue(Edit, Obj, Effect, Checks[Layer].Name, '1');
    if S.Scene = tsRun then
    begin
      ResetTracks(ttSpeed, ttSeed);
      SetValue(Edit, Obj, Effect, SceneryItem.Name, SCENERY_NAMES[S.Scenery]);
      SetValue(Edit, Obj, Effect, PoleItem.Name, '1');
    end;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_TravelTrain scene: ' + E.Message));
  end;
end;

procedure AddOptions(var Options: array of TFILTER_ITEM_SELECT_ITEM;
  const Names: array of PWideChar);
var
  I: Integer;
begin
  for I := 0 to High(Names) do
  begin
    Options[I].Name := Names[I];
    Options[I].Value := I;
  end;
  Options[High(Options)].Name := nil;
end;

procedure RegisterTrainParameters;
var
  S: TTrainSettings;
  Scene: TTrainScene;
  Layer: TTrainLayer;
  I: Integer;
  procedure AddTracks(First, Last: TTrainTrack);
  var
    Track: TTrainTrack;
    D: TTrackDefinition;
  begin
    for Track := First to Last do
    begin
      D := TRAIN_TRACKS[Track];
      AddTrack(Tracks[Track], D.Name, S.Tracks[Track], D.Minimum, D.Maximum, D.Step);
    end;
  end;
  procedure HideByScene(var Rule: TFILTER_ITEM_HIDE_RULE; Name: PWideChar; Comparison: Integer; Scene: TTrainScene);
  begin
    AddAlwaysHideRule(Rule, Name);
    Rule.ConditionName := SceneItem.Name;
    Rule.ConditionOperator := Comparison;
    Rule.ConditionValue := Ord(Scene);
  end;
begin
  S := DefaultTrainSettings;
  AddOptions(StyleOptions, STYLE_NAMES);
  AddOptions(SceneOptions, SCENE_NAMES);
  for I := Low(SCENERY_ORDER) to High(SCENERY_ORDER) do
  begin
    SceneryOptions[I].Name := SCENERY_NAMES[SCENERY_ORDER[I]];
    SceneryOptions[I].Value := Ord(SCENERY_ORDER[I]);
  end;
  SceneryOptions[High(SceneryOptions)].Name := nil;
  AddSelect(StyleItem, '列車プリセット', Ord(S.Style), @StyleOptions[0]);
  AddButton(StyleButton, '列車の配色を反映', ApplyStyle);
  AddSelect(SceneItem, 'シーンプリセット', Ord(S.Scene), @SceneOptions[0]);
  AddButton(SceneButton, 'シーン設定を初期値に戻す', ApplyScene);

  AddGroup(LayerGroup, '描画レイヤー', 1);
  for Layer := Low(TTrainLayer) to High(TTrainLayer) do
    AddCheck(Checks[Layer], LAYER_NAMES[Layer], 1);
  AddGroup(LayerEnd, '', 0);
  for Scene := Low(TTrainScene) to High(TTrainScene) do
  begin
    AddGroup(TimeGroup[Scene], TIME_GROUPS[Scene], 1);
    AddTracks(SCENE_TIMES[Scene].First, SCENE_TIMES[Scene].Last);
    AddGroup(TimeEnd[Scene], '', 0);
  end;
  AddGroup(SceneryGroup, SCENERY_GROUP, 0);
  AddSelect(SceneryItem, '背景の種類', Ord(S.Scenery), @SceneryOptions[0]);
  AddTracks(ttSpeed, ttSeed);
  AddCheck(PoleItem, '手前の通過電柱', Ord(S.ForegroundPoles));
  AddGroup(SceneryEnd, '', 0);
  AddGroup(ColorGroup, '車体の配色', 0);
  AddColor(BodyItem, '車体色', S.Colors.Body and 255,
    (S.Colors.Body shr 8) and 255, S.Colors.Body shr 16);
  AddColor(StripeItem, '帯色', S.Colors.Stripe and 255,
    (S.Colors.Stripe shr 8) and 255, S.Colors.Stripe shr 16);
  AddGroup(ColorEnd, '', 0);
  AddGroup(SizeGroup, '描画サイズ', 0);
  AddTracks(ttWidth, ttHeight);
  AddGroup(SizeEnd, '', 0);

  for Scene := Low(TTrainScene) to High(TTrainScene) do
  begin
    HideByScene(HideTime[Scene], TIME_GROUPS[Scene], HIDE_NOT_EQUAL, Scene);
    for Layer := Low(TTrainLayer) to High(TTrainLayer) do
      if Layer in SCENE_LAYERS[Scene] then
        HideByScene(HideLayer[Layer], LAYER_NAMES[Layer], HIDE_NOT_EQUAL, Scene);
  end;
  for I := Low(SIDE_VIEW_ONLY) to High(SIDE_VIEW_ONLY) do
  begin
    HideByScene(HideBeforeSideView[I], Tracks[SIDE_VIEW_ONLY[I]].Name, HIDE_LESS, tsRun);
    HideByScene(HideAfterSideView[I], Tracks[SIDE_VIEW_ONLY[I]].Name, HIDE_GREATER, tsExit);
  end;
  HideByScene(HidePole, PoleItem.Name, HIDE_NOT_EQUAL, tsRun);
end;

function ReadTrainSettings: TTrainSettings;
var
  Track: TTrainTrack;
  Layer: TTrainLayer;
  function ReadColor(const Item: TFILTER_ITEM_COLOR): Cardinal;
  begin
    Result := (Cardinal(Item.R) shl 16) or (Cardinal(Item.G) shl 8) or Item.B;
  end;
begin
  Result := Default(TTrainSettings);
  Result.Scene := TTrainScene(EnsureRange(SceneItem.Value, 0, Ord(High(TTrainScene))));
  Result.Style := TTrainStyle(EnsureRange(StyleItem.Value, 0, Ord(High(TTrainStyle))));
  Result.Scenery := TTrainScenery(EnsureRange(SceneryItem.Value, 0, Ord(High(TTrainScenery))));
  Result.Colors.Body := ReadColor(BodyItem);
  Result.Colors.Stripe := ReadColor(StripeItem);
  Result.ForegroundPoles := PoleItem.Value <> 0;
  for Track := Low(TTrainTrack) to High(TTrainTrack) do
    Result.Tracks[Track] := TrainTrackValue(Track, Tracks[Track].Value);
  for Layer := Low(TTrainLayer) to High(TTrainLayer) do
    if (Layer in SCENE_LAYERS[Result.Scene]) and (Checks[Layer].Value <> 0) then
      Include(Result.Layers, Layer);
end;

end.

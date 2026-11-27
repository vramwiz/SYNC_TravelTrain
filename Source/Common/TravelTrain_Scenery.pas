unit TravelTrain_Scenery;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// ホームと走行風景を描く。SYNC_Elevator の視点高と遠近の考え方を横方向の移動へ応用する。

interface

uses TravelTrain_Canvas, TravelTrain_Settings;

// 出力範囲を塗りつぶす固定の駅背景。扉越しの場合はホームを正面から描く。
procedure DrawStation(C: TTrainCanvas; const S: TTrainSettings);
// 距離と高さから毎回同じ風景を作る。電柱は車体より手前に別描画する。
procedure DrawLandscape(C: TTrainCanvas; const S: TTrainSettings; Distance: Double);
// 発車前のホームを距離に応じて画面の外へ流す。風景と線路の間に描く。
procedure DrawRunningStartPlatform(C: TTrainCanvas; Elevation, Distance, RouteLength: Double);
// 地下ホームの壁と天井を車体の奥に描く。
procedure DrawRunningArrivalStation(C: TTrainCanvas; Elevation, Progress: Double);
// 到着するホームを床下と線路より手前に重ねる。Progress は進入の進み具合。
procedure DrawRunningArrivalPlatform(C: TTrainCanvas; Elevation, Progress, Zoom: Double);
// 床下機器より低い位置に線路面を描く。Distance は論理ピクセル、Zoom は百分率。
procedure DrawRunningTrack(C: TTrainCanvas; Elevation, Distance, Zoom: Double);
// 車体の手前に電柱を重ねる。地下への移行中は Opacity と Elevation に応じて薄くする。
procedure DrawPassingPoles(C: TTrainCanvas; Elevation, Distance, Opacity: Double);

implementation

uses System.Math, Winapi.D2D1;

procedure DrawSky(C: TTrainCanvas; Warm: Boolean);
begin
  if Warm then C.Panel(0, 0, DESIGN_W, DESIGN_H, 0, $668EAA, $B9D8DF, $F1E3C2)
  else C.Panel(0, 0, DESIGN_W, DESIGN_H, 0, $6095B7, $B6D7DF, $F2E6C7);
  C.Glow(1004, 132, 298, 240, $FFF2C8, 0.52);
end;

procedure PlatformTiles(C: TTrainCanvas; Y: Single; NearEdge: Boolean;
  VerticalJoints: Boolean = False; Depth: Single = 0);
var
  I, BottomSpacing: Integer;
begin
  C.Panel(0, Y, DESIGN_W, DESIGN_H - Y, 0, Mix($BCB8AF, $A8B1B1, Depth),
    Mix($95958E, $838E91, Depth), Mix($757D7D, $5B686F, Depth));
  BottomSpacing := 175 - Round(75 * Depth);
  if VerticalJoints then BottomSpacing := 100;
  for I := -7 to 7 do
    C.Line(640 + I * 100, Y, 640 + I * BottomSpacing, DESIGN_H, 1.25, $485456, 0.43);
  C.Line(0, Y + 48, DESIGN_W, Y + 48, 1.5, $666D6B, 0.64);
  C.Line(0, Y + 110, DESIGN_W, Y + 110, 1.5, $666D6B, 0.68);
  if NearEdge then
  begin
    C.Box(0, Y, DESIGN_W, 5, 0, $F5E0A2);
    C.Box(0, Y + 12, DESIGN_W, 18, 0, $CFAD58);
    for I := 0 to 79 do
    begin
      C.Oval(7 + I * 16, Y + 18, 3, 2, $F3D480);
      C.Oval(14 + I * 16, Y + 24, 3, 2, $927139, 0.74);
    end;
  end;
end;

procedure DrawWideStationFloor(C: TTrainCanvas; RailY: Single; Scene: TTrainScene; Depth: Single);
var
  I: Integer;
  X, Y, Edge, Ballast, FarRail, NearTop, WallH: Single;
  Gravel: Cardinal;
begin
  Edge := RailY - 59;
  Ballast := RailY - 34;
  FarRail := RailY - 23;
  C.Panel(0, 426, DESIGN_W, Edge - 426, 0, Mix($C1BEB1, $AEB9B9, Depth),
    Mix($A5A79C, $8D9BA0, Depth), Mix($8B938D, $73878E, Depth));
  for I := -9 to 9 do
    C.Line(640 + I * 69, 426, 640 + I * (111 - 42 * Depth), Edge, 1.4, $6A7774, 0.61);
  C.Box(0, Edge - 44, DESIGN_W, 1.6, 0, $6B7874, 0.58);
  if Scene = tsDeparture then
  begin
    C.Box(0, Edge - 24, DESIGN_W, 14, 0, $C9AB64);
    for I := 0 to 89 do
    begin
      C.Box(7 + I * 14.5, Edge - 21, 10, 1.5, 0.7, $F1D590);
      C.Box(7 + I * 14.5, Edge - 15, 10, 1.5, 0.7, $A28953);
    end;
  end;

  C.Panel(0, Edge, DESIGN_W, Ballast - Edge, 0, $868B83, $565E5D, $434D50);
  C.Box(0, Edge - 4, DESIGN_W, 5, 0, $E4DCCA);
  C.Box(0, Edge + 9, DESIGN_W, 2, 0, $A7ACA0);
  for I := 0 to 15 do
    C.Box(I * 89, Edge + 11, 2, 13, 0, $707A76, 0.65);

  C.Panel(0, Ballast, DESIGN_W, DESIGN_H - Ballast, 0, Mix($5F6866, $464F55, Depth),
    Mix($515B5B, $374149, Depth), Mix($454D4F, $2F3941, Depth));
  for I := 0 to 153 do
  begin
    X := (I * 229 mod 1280) + 0.5;
    Y := Ballast + 4 + (I * 111 mod 101);
    Gravel := $7C857D;
    if Odd(I) then Gravel := $343F44;
    C.Oval(X, Y, 1.3 + (I mod 4), 1 + (I mod 2), Gravel, 0.68);
  end;
  for I := -1 to 26 do
  begin
    X := I * 51.5;
    C.Polygon([Pt(X - 5, FarRail - 9), Pt(X + 8, FarRail - 9),
      Pt(X + 25, RailY + 17), Pt(X + 8, RailY + 17)], $2D393D);
    C.Line(X - 3, FarRail - 8, X + 10, RailY + 15, 2, $828A80);
  end;

  // 手前側レールの頭頂を、車輪が接地する高さに合わせる。
  C.Box(0, FarRail, DESIGN_W, 6, 0, $35454A);
  C.Box(0, FarRail, DESIGN_W, 2, 0, $B5BAB0);
  C.Box(0, RailY, DESIGN_W, 9, 0, $2D3A40);
  C.Box(0, RailY, DESIGN_W, 3, 0, $C3C7BE);
  C.Box(0, RailY + 6, DESIGN_W, 1.7, 0, $647572);
  for I := 0 to 24 do
    C.Box(I * 51.5 + 10, RailY + 9, 9, 3, 1, $8C9389);

  NearTop := RailY + 36;
  WallH := 18;
  if Scene = tsArrival then
  begin
    NearTop := RailY + 17;
    WallH := 9;
  end;
  C.Panel(0, NearTop - WallH + 1, DESIGN_W, WallH, 0, $374348, $56615D, $6D7872);
  PlatformTiles(C, NearTop, True, False, Depth);
end;

procedure DrawUndergroundStationWall(C: TTrainCanvas; Left, Right, FloorY, CeilingY,
  Offset, Depth: Single);
const
  TILE_WIDTH = 122;
  LIGHT_PITCH = 286;
var
  WallH, X, Y, BandY, Phase: Single;
  I: Integer;
begin
  if (Depth <= 0) or (Right <= Left) then Exit;
  C.PushClip(Left, 0, Right - Left, FloorY * Depth);
  try
    C.Box(0, 0, DESIGN_W, FloorY, 0, $455259);
    WallH := FloorY - CeilingY;
    BandY := CeilingY + WallH * 0.52;
    C.Panel(0, CeilingY, DESIGN_W, WallH, 0, $C4CBC6, $ADB8B7, $839398);
    Phase := Offset - Floor(Offset / TILE_WIDTH) * TILE_WIDTH;
    for I := -1 to 11 do
    begin
      X := I * TILE_WIDTH - Phase;
      C.Box(X, CeilingY, 1.5, WallH, 0, $607578, 0.47);
      C.Box(X + 1.5, CeilingY, 1, WallH, 0, $DFE3DC, 0.54);
    end;
    for I := 1 to 5 do
    begin
      Y := CeilingY + I * WallH / 6;
      C.Box(0, Y, DESIGN_W, 1.5, 0, $65787A, 0.47);
      C.Box(0, Y + 1.5, DESIGN_W, 1, 0, $E6E8DE, 0.42);
    end;
    C.Box(0, BandY, DESIGN_W, 23, 0, $4D737A);
    C.Box(0, BandY + 3, DESIGN_W, 2, 0, $9DB9B4);
    C.Panel(0, FloorY - 42, DESIGN_W, 42, 0, $687D82, $566C74, $3C5159);

    C.Panel(0, 0, DESIGN_W, CeilingY, 0, $455259, $34454D, $273943);
    C.Box(0, CeilingY - 5, DESIGN_W, 5, 0, $65777B);
    Phase := Offset - Floor(Offset / LIGHT_PITCH) * LIGHT_PITCH;
    for I := -1 to 5 do
    begin
      X := 83 + I * LIGHT_PITCH - Phase;
      C.Box(X - 10, CeilingY - 24, 162, 14, 2, $53666A);
      C.Box(X, CeilingY - 21, 142, 7, 1, $E6E8D7);
      C.Box(X + 5, CeilingY - 20, 132, 3, 1, $FFF6D9);
    end;
  finally
    C.PopClip;
  end;
end;

procedure DrawStationBackdrop(C: TTrainCanvas; const S: TTrainSettings); forward;

procedure DrawStation(C: TTrainCanvas; const S: TTrainSettings);
var
  Y, X, Depth: Single;
  I, J: Integer;
  Scene: TTrainScene;
begin
  Scene := S.Scene;
  Depth := EnsureRange(-S.Tracks[ttElevation], 0.0, 1.0);
  if Depth < 1 then
  begin
    DrawStationBackdrop(C, S);
    C.Box(0, 334, 1280, 98, 0, $839C95);
    for I := 0 to 19 do
      C.Line(I * 69, 352, I * 69, 430, 3, $536C68);
    C.Box(0, 350, 1280, 5, 0, $B9C8B8);
    C.Box(0, 414, 1280, 14, 0, $70817A);
  end
  else
    C.Box(0, 0, DESIGN_W, DESIGN_H, 0, $38454D);
  case Scene of
    tsArrival:
      begin
        Y := WIDE_ARRIVAL_RAIL_Y - 112;
        DrawWideStationFloor(C, WIDE_ARRIVAL_RAIL_Y, Scene, Depth);
      end;
    tsDeparture:
      begin
        Y := WIDE_DEPARTURE_RAIL_Y - 112;
        DrawWideStationFloor(C, WIDE_DEPARTURE_RAIL_Y, Scene, Depth);
      end;
  else
    Y := 432;
    C.Panel(0, 425, 1280, Y - 416, 0, $68716E, $565D5D, $384648);
    PlatformTiles(C, Y, True, True, Depth);
  end;

  if Depth < 1 then
  begin
    // 屋根と柱を、窓越しでも駅と読める高さに配置する。
    if Scene = tsBoard then
      C.Polygon([Pt(0, 10), Pt(1280, 0), Pt(1280, 113), Pt(0, 148)], $465557)
    else
      C.Polygon([Pt(0, 3), Pt(1280, 67), Pt(1280, 113), Pt(0, 172)], $465557);
    for I := 0 to 5 do
    begin
      X := 91 + I * 237;
      if Scene = tsBoard then X := X - 22;
      C.Panel(X - 10, 102, 19, Y - 95, 1, $AAB0A0, $8A9589, $4D6461);
      C.Box(X - 13, Y - 19, 26, 23, 2, $637672);
      C.Box(X - 10, 231, 19, 7, 0, $C7A96E);
      C.Line(X, 123, X + 50, 102, 7, $64716A);
    end;
    if Scene = tsBoard then
      C.Line(0, 144, 1280, 112, 10, $87938A)
    else C.Line(0, 169, 1280, 111, 10, $87938A);
    for I := 0 to 4 do
    begin
      X := 172 + I * 278;
      C.Box(X, 109, 95, 7, 2, $DED5A8);
      C.Box(X + 4, 110, 87, 2, 1, $FFF0BD);
    end;
  end;
  DrawUndergroundStationWall(C, 0, DESIGN_W, 426, 111, 0, Depth);
  C.Panel(521, 190, 238, 53, 5, $465A62, $344953, $293D49);
  C.Box(526, 232, 228, 5, 2, $5E9E90);
  C.Box(542, 205, 22, 20, 3, $7DB6A6);
  C.Box(583, 205, 102, 5, 2, $E9E8D6);
  C.Box(583, 216, 65, 4, 2, $ABC5BC);
  C.Polygon([Pt(718, 205), Pt(733, 215), Pt(718, 225)], $DBDDC4);
  for I := 0 to 1 do
  begin
    X := 209 + 696 * I;
    C.Box(X, Y - 77, 133, 43, 6, $537E72);
    for J := 0 to 2 do C.Box(X + 6, Y - 71 + J * 10, 121, 2, 1, $84A294);
    C.Box(X - 4, Y - 39, 141, 10, 3, $385A55);
    C.Box(X + 12, Y - 29, 8, 27, 1, $4D6262);
    C.Box(X + 113, Y - 29, 8, 27, 1, $4D6262);
  end;
end;

function Variation(Index, Seed: Integer): Single;
var
  N: Cardinal;
begin
  // 整数演算を64ビットで行い、Debugの桁あふれ検査でも同じ値になる。
  N := Cardinal((Int64(Index) * 374761393 + Int64(Seed) * 668265263) and $FFFFFFFF);
  N := Cardinal((UInt64(N xor (N shr 13)) * 1274126177) and $FFFFFFFF);
  Result := (N and $FFFF) / 65535;
end;

procedure DrawFarRidge(C: TTrainCanvas; Offset, Y: Single; Seed: Integer; Color: Cardinal;
  Coast: Boolean);
const
  SPACING = 215;
var
  I, First: Integer;
  X, Rise, NextRise, Peak, Factor: Single;
begin
  First := Floor(Offset / SPACING);
  Factor := 1;
  if Coast then Factor := 0.48;
  for I := First - 1 to First + 7 do
  begin
    X := I * SPACING - Offset;
    Rise := Factor * (8 + Variation(I, Seed) * 51);
    NextRise := Factor * (8 + Variation(I + 1, Seed) * 51);
    Peak := Max(Rise, NextRise) + Factor * (17 + Variation(I, Seed + 91) * 42);
    C.Polygon([Pt(X, Y - Rise), Pt(X + 50, Y - (Rise + Peak) * 0.5),
      Pt(X + 113, Y - Peak), Pt(X + 145, Y - (NextRise + Peak * 3) * 0.25),
      Pt(X + SPACING + 1, Y - NextRise), Pt(X + SPACING + 1, Y + 35), Pt(X, Y + 35)], Color);
  end;
  C.Box(0, Y + 34, DESIGN_W, 3, 0, Color);
end;

procedure DrawMiddleGround(C: TTrainCanvas; Style: TTrainScenery; Offset, Y: Single; Seed: Integer);
const
  SPACING = 144;
var
  I, First: Integer;
  X, H, V: Single;
begin
  First := Floor(Offset / SPACING);
  for I := First - 1 to First + 10 do
  begin
    X := I * SPACING - Offset;
    V := Variation(I, Seed);
    H := 33 + V * 91;
    case Style of
      scCoast:
        begin
          C.Line(X, Y + 12, X + 33 + V * 44, Y + 10, 2, $E7E9CB, 0.61);
          C.Line(X + 42, Y + 28, X + 120, Y + 29, 1.5, $D6E3CF, 0.45);
          if V > 0.76 then
          begin
            C.Polygon([Pt(X + 11, Y), Pt(X + 38, Y + 1), Pt(X + 31, Y + 7), Pt(X + 14, Y + 6)], $627D79);
            C.Polygon([Pt(X + 25, Y - 24), Pt(X + 13, Y - 3), Pt(X + 25, Y - 3)], $F2E9D6);
          end;
        end;
      scCountryside:
        begin
          C.Polygon([Pt(X - 4, Y + 44), Pt(X + 43, Y - 7), Pt(X + 105, Y - 3),
            Pt(X + 167, Y + 48)], Mix($94AA6B, $728F63, V));
          if V > 0.34 then
          begin
            H := H * 0.27;
            C.Box(X + 55, Y - H, 39, H, 1, $E0DCC5);
            C.Polygon([Pt(X + 49, Y - H + 2), Pt(X + 75, Y - H - 14),
              Pt(X + 100, Y - H + 2)], $8A6352);
          end;
        end;
    end;
  end;
end;

procedure DrawCityRow(C: TTrainCanvas; Offset, BaseY: Single; Seed: Integer; Distant: Boolean);
var
  First, I, J, Spacing: Integer;
  X, Y, W, H, FrontW, V, FloorStep: Single;
  Wall, Glass: Cardinal;
begin
  Spacing := 155;
  if Distant then Spacing := 104;
  First := Floor(Offset / Spacing);
  for I := First - 1 to First + Ceil(DESIGN_W / Spacing) do
  begin
    V := Variation(I, Seed);
    X := I * Spacing - Offset + 5 + V * 14;
    W := Spacing * (0.61 + Variation(I, Seed + 7) * 0.29);
    if Distant then
    begin
      H := 238 + Variation(I, Seed + 23) * 153;
      Wall := Mix($B3C2C5, $879FAA, V);
    end
    else
    begin
      H := 205 + Variation(I, Seed + 23) * 201;
      Wall := Mix($A6B6BE, $647F92, V);
    end;
    Y := BaseY - H;
    FrontW := W * 0.81;
    C.Box(X, Y, W, H + 18, 0, Wall);
    C.Box(X + FrontW, Y, W - FrontW, H + 18, 0, Shade(Wall, 0.79));
    if V > 0.41 then
      C.Box(X + W * 0.16, Y - 9 - V * 13, W * 0.43, 10 + V * 13, 0, Shade(Wall, 0.92));
    C.Box(X, Y, W, 3, 0, Shade(Wall, 1.19));
    if Distant then Continue;

    Glass := Mix($567383, $7699A6, Variation(I, Seed + 61));
    C.Box(X + 8, Y + 16, FrontW - 15, H - 25, 0, Glass);
    C.Box(X + 9, Y + 17, FrontW * 0.24, H - 26, 0, Shade(Glass, 1.19));
    FloorStep := 17 + 6 * V;
    for J := 1 to Trunc((H - 26) / FloorStep) do
      C.Box(X + 8, Y + 16 + J * FloorStep, FrontW - 15, 2.4, 0, Wall);
    C.Box(X + FrontW * 0.39, Y + 16, 2, H - 25, 0, Shade(Wall, 1.1));
    C.Box(X + FrontW * 0.66, Y + 16, 2, H - 25, 0, Shade(Wall, 0.93));
  end;
end;

procedure DrawHouseRow(C: TTrainCanvas; Offset, BaseY: Single; Seed: Integer; Distant: Boolean);
var
  First, I, J, Spacing: Integer;
  X, Y, W, H, V, Eave, Peak, RoofH, WindowX, WindowW, WindowY: Single;
  Wall, Roof, Trim: Cardinal;
begin
  Spacing := 162;
  if Distant then Spacing := 139;
  First := Floor(Offset / Spacing);
  for I := First - 1 to First + Ceil(DESIGN_W / Spacing) do
  begin
    V := Variation(I, Seed);
    X := I * Spacing - Offset + 7 + V * 12;
    W := Spacing * (0.62 + Variation(I, Seed + 3) * 0.22);
    H := 83 + Variation(I, Seed + 29) * 47;
    Wall := Mix($F1E3CD, $ABB8B7, V);
    Roof := Mix($8D6156, $536D76, Variation(I, Seed + 57));
    if Distant then
    begin
      H := H * 0.87;
      Wall := Mix(Wall, $B9C9C7, 0.32);
      Roof := Mix(Roof, $A2B1B0, 0.35);
    end;
    Y := BaseY - H;
    Eave := Y + 4;
    Peak := X + W * (0.34 + Variation(I, Seed + 41) * 0.29);
    RoofH := 27 + V * 23;

    C.Box(X, Y, W, H + 14, 0, Wall);
    C.Box(X + W * 0.79, Y, W * 0.21, H + 14, 0, Shade(Wall, 0.79));
    C.Polygon([Pt(X - 6, Eave), Pt(Peak, Y - RoofH), Pt(X + W + 7, Eave)], Roof);
    C.Polygon([Pt(Peak, Y - RoofH), Pt(X + W + 7, Eave), Pt(X + W * 0.75, Eave)], Shade(Roof, 0.79));
    C.Box(X - 5, Eave, W + 11, 4, 0, Shade(Roof, 0.70));
    Trim := Shade(Wall, 1.24);
    WindowW := W * 0.17;
    for J := 0 to 1 do
    begin
      WindowX := X + W * (0.14 + J * 0.32);
      WindowY := Y + H * 0.22;
      C.Box(WindowX - 2, WindowY - 2, WindowW + 4, 23, 0, Trim);
      C.Box(WindowX, WindowY, WindowW, 19, 0, $5A7C89);
      C.Box(WindowX + WindowW * 0.48, WindowY, 1.3, 19, 0, $CAD8CC);
    end;
    if Distant then Continue;
    C.Box(X + W * 0.11, BaseY - 7, W * 0.73, 8, 0, Shade(Wall, 0.74));
    C.Box(X + W * 0.47, BaseY - 39, WindowW, 34, 0, Shade(Roof, 0.87));
    C.Box(X + W * 0.13, BaseY - 45, WindowW + 7, 16, 0, $74939A);
    C.Box(X + W * 0.13, BaseY - 30, WindowW + 7, 3, 0, Trim);
  end;
end;

procedure DrawBuiltSkyline(C: TTrainCanvas; Style: TTrainScenery; Distance, BaseY: Single; Seed: Integer);
begin
  case Style of
    scTown:
      begin
        C.Box(0, BaseY - 3, DESIGN_W, DESIGN_H - BaseY + 3, 0, $899A9B);
        DrawCityRow(C, Distance * 0.35 + 38, BaseY - 21, Seed + 93, True);
        DrawCityRow(C, Distance * 0.66, BaseY, Seed, False);
      end;
    scResidential:
      begin
        C.Box(0, BaseY - 40, DESIGN_W, DESIGN_H - BaseY + 40, 0, $A0AA9B);
        DrawHouseRow(C, Distance * 0.35 + 48, BaseY - 54, Seed + 93, True);
        DrawHouseRow(C, Distance * 0.66, BaseY, Seed, False);
      end;
  end;
end;

procedure DrawStationBackdrop(C: TTrainCanvas; const S: TTrainSettings);
var
  Seed: Integer;
  Shift: Single;
  Previous: TD2D1Matrix3x2F;
begin
  DrawSky(C, (S.Scene = tsDeparture) or (S.Scenery = scCoast));
  Seed := Round(S.Tracks[ttSeed]);
  Shift := 76 * (1 - Exp(-Max(0.0, S.Tracks[ttElevation]) * 0.26));
  Previous := C.ApplyTransform(TD2D1Matrix3x2F.Translation(0, Shift));
  try
    case S.Scenery of
      scTown, scResidential:
        DrawBuiltSkyline(C, S.Scenery, 0, 426, Seed);
      scCoast:
        begin
          DrawFarRidge(C, 0, 257, Seed + 31, $9CADAD, True);
          DrawFarRidge(C, 0, 276, Seed + 11, $769B98, True);
          C.Panel(0, 274, DESIGN_W, DESIGN_H - 274, 0, $A3CFCA, $76A9AB, $5B8E99);
          DrawMiddleGround(C, scCoast, 0, 296, Seed);
        end;
      scCountryside:
        begin
          C.Polygon([Pt(0, 301), Pt(106, 268), Pt(230, 293), Pt(413, 255), Pt(578, 306),
            Pt(770, 263), Pt(967, 294), Pt(1111, 256), Pt(1280, 299), Pt(1280, 421), Pt(0, 421)], $799792);
          C.Polygon([Pt(0, 344), Pt(103, 315), Pt(263, 351), Pt(400, 320), Pt(549, 347),
            Pt(780, 313), Pt(1023, 343), Pt(1198, 302), Pt(1280, 333), Pt(1280, 421), Pt(0, 421)], $617D77);
        end;
    end;
  finally
    C.RestoreTransform(Previous);
  end;
end;

procedure DrawTunnel(C: TTrainCanvas; Distance: Double; Depth: Single);
var
  I: Integer;
  X, Y: Single;
begin
  // 地下側の壁が滑らかに上から迫り、-1で窓の外を完全に覆う。
  Y := -DESIGN_H * (1 - Depth);
  C.PushClip(0, 0, DESIGN_W, DESIGN_H);
  try
    C.Panel(0, Y, DESIGN_W, DESIGN_H, 0, $151F28, $3C454A, $21292A);
    C.Box(0, Y + 490, DESIGN_W, 46, 0, $555853);
    C.Box(0, Y + 530, DESIGN_W, 5, 0, $A08752, 0.66);
    C.Box(0, Y + 624, DESIGN_W, 43, 0, $141E25);
    for I := -1 to 5 do
    begin
      X := I * 298 - (Distance - Floor(Distance / 298) * 298);
      C.Box(X, Y, 14, 720, 0, $202C34);
      C.Box(X + 15, Y, 4, 720, 0, $596163);
      C.Glow(X + 159, Y + 237, 83, 53, $FAD78C, 0.32);
      C.Box(X + 112, Y + 231, 93, 9, 2, $E7C78C);
      C.Box(X + 120, Y + 232, 77, 3, 2, $FFF1C7);
    end;
  finally
    C.PopClip;
  end;
end;

procedure DrawLandscape(C: TTrainCanvas; const S: TTrainSettings; Distance: Double);
var
  Altitude, RidgeY, GroundY, X, H: Single;
  I, First, Seed: Integer;
  Ground: Cardinal;
begin
  if S.Tracks[ttElevation] <= -1 then
  begin
    DrawTunnel(C, Distance, 1);
    Exit;
  end;
  DrawSky(C, S.Scenery = scCoast);
  Altitude := Max(0.0, S.Tracks[ttElevation]);
  RidgeY := 326 - 5 * Min(Altitude, 8);
  GroundY := 409 + 100 * (1 - Exp(-Altitude * 0.25));
  Seed := Round(S.Tracks[ttSeed]);
  if S.Scenery in [scTown, scResidential] then
    DrawBuiltSkyline(C, S.Scenery, Distance, GroundY, Seed)
  else
  begin
    DrawFarRidge(C, Distance * 0.12, RidgeY - 5, Seed + 31, $9CADAD, S.Scenery = scCoast);
    DrawFarRidge(C, Distance * 0.22, RidgeY + 33, Seed + 11, $769B98, S.Scenery = scCoast);
    Ground := $A2AD77;
    if S.Scenery = scCoast then Ground := $76A9AB;
    C.Panel(0, RidgeY + 67, DESIGN_W, DESIGN_H - RidgeY - 67, 0,
      Shade(Ground, 1.17), Ground, Shade(Ground, 0.72));
    DrawMiddleGround(C, S.Scenery, Distance * 0.47, GroundY, Seed);
  end;
  if S.Scenery = scCountryside then
  begin
    First := Floor(Distance * 0.81 / 125);
    for I := First - 1 to First + 11 do
    begin
      X := I * 125 - Distance * 0.81;
      H := 34 + Variation(I, Seed + 79) * 64;
      C.Box(X - 2, GroundY + 42, 6, 66, 1, $687559);
      C.Oval(X, GroundY + 57 - H * 0.32, H * 0.47, H * 0.62, $597D66);
      C.Oval(X - H * 0.13, GroundY + 52 - H * 0.25, H * 0.32, H * 0.47, $709477);
    end;
  end;
  if Altitude > 0 then
  begin
    H := Min(Altitude * 48, 101.0);
    C.Box(0, DESIGN_H - H, DESIGN_W, H, 0, $87958E);
    C.Box(0, DESIGN_H - H + 6, DESIGN_W, 4, 0, $D4D7C1);
    X := Distance - Floor(Distance / 114) * 114;
    for I := -1 to 12 do C.Box(I * 114 - X, DESIGN_H - H + 8, 3, H, 0, $697B76);
  end;
  if S.Tracks[ttElevation] < 0 then DrawTunnel(C, Distance, -S.Tracks[ttElevation]);
end;

procedure DrawRunningStartPlatform(C: TTrainCanvas; Elevation, Distance, RouteLength: Double);
const
  CANOPY_TOP = -24;
  CANOPY_BOTTOM = 34;
  PLATFORM_Y = 289;
  PLATFORM_B = 366;
  LENGTH = DESIGN_W + 220;
var
  Offset, Edge, X, Depth: Single;
  I: Integer;
  Roof, Surface, Post, Tactile: Cardinal;
begin
  Offset := 0;
  if RouteLength > 0 then
    Offset := LENGTH * Distance / Min(LENGTH / 1.25, RouteLength * 0.48);
  Edge := Min(Single(DESIGN_W), LENGTH - Offset);
  if Edge <= 0 then Exit;
  Depth := EnsureRange(-Elevation, 0.0, 1.0);
  Roof := Mix($526469, $2C363C, Depth);
  Surface := Mix($B7B8AC, $747977, Depth);
  Post := Mix($B4BCAF, $677471, Depth);
  Tactile := Mix($D3B160, $A48C54, Depth);
  C.PushClip(0, 0, Edge, DESIGN_H);
  try
    C.Panel(0, 254, Edge, PLATFORM_Y - 254, 0, Shade(Post, 1.06), Post, Shade(Post, 0.77));
    C.Box(0, 254, Edge, 4, 0, Shade(Post, 1.27));
    C.Panel(0, PLATFORM_Y, Edge, PLATFORM_B - PLATFORM_Y, 0, Shade(Surface, 1.19), Surface, Shade(Surface, 0.78));
    C.Box(0, PLATFORM_Y + 12, Edge, 12, 0, Tactile);
    C.Box(0, PLATFORM_Y + 12, Edge, 2, 0, Shade(Tactile, 1.29));
    C.Box(0, PLATFORM_B - 10, Edge, 10, 0, $67756E);
    C.Box(0, PLATFORM_B, Edge, 10, 0, $47565A);
    for I := 0 to 14 do
    begin
      X := I * 112 - Offset;
      C.Line(X, PLATFORM_Y + 26, X + 12, PLATFORM_B - 11, 1.4, Shade(Surface, 0.73), 0.70);
    end;

    // 下端を車両の屋根より高く置き、屋根上機器との間に空が見えるようにする。
    C.Panel(0, CANOPY_TOP, Edge, CANOPY_BOTTOM - CANOPY_TOP, 0,
      Shade(Roof, 1.42), Roof, Shade(Roof, 0.69));
    C.Box(0, CANOPY_BOTTOM - 5, Edge, 4, 0, Shade(Roof, 1.46));
    DrawUndergroundStationWall(C, 0, Edge, 254, CANOPY_BOTTOM, Offset, Depth);
    for I := 0 to 6 do
    begin
      X := 73 + I * 226 - Offset;
      if (X < -38) or (X > Edge + 10) then Continue;
      C.Panel(X, CANOPY_BOTTOM - 1, 15, PLATFORM_Y - CANOPY_BOTTOM + 11, 0,
        Shade(Post, 1.26), Post, Shade(Post, 0.67));
      C.Box(X - 3, PLATFORM_Y - 5, 21, 13, 1, Shade(Post, 0.63));
      C.Box(X + 18, CANOPY_BOTTOM - 13, 109, 5, 2, $E9E1BC);
    end;
    for I := 0 to 2 do
    begin
      X := 214 + I * 410 - Offset;
      if (X < -195) or (X > Edge) then Continue;
      C.Box(X + 9, CANOPY_BOTTOM, 3, 220 - CANOPY_BOTTOM, 0, $607473);
      C.Box(X + 155, CANOPY_BOTTOM, 3, 220 - CANOPY_BOTTOM, 0, $607473);
      C.Panel(X, 216, 174, 37, 4, $526771, $354A56, $293B48);
      C.Box(X + 9, 244, 156, 4, 1, $5E9E90);
      C.Box(X + 15, 226, 16, 14, 3, $7DB6A6);
      C.Box(X + 45, 227, 79, 4, 1, $E9E8D6);
      C.Polygon([Pt(X + 143, 223), Pt(X + 156, 233), Pt(X + 143, 241)], $DBDDC4);
      C.Box(X + 15, 266, 115, 22, 4, $547A71);
      C.Box(X + 16, 286, 114, 5, 1, $355751);
      C.Box(X + 26, 290, 5, 9, 1, $50615E);
      C.Box(X + 112, 290, 5, 9, 1, $50615E);
    end;
  finally
    C.PopClip;
  end;
end;

function RunningArrivalPlatformX(Progress: Double): Single;
const
  ENTRY_MARGIN = 42;
begin
  Result := DESIGN_W + ENTRY_MARGIN - (DESIGN_W + 3 * ENTRY_MARGIN) * Progress;
end;

procedure DrawRunningArrivalStation(C: TTrainCanvas; Elevation, Progress: Double);
var
  Edge: Single;
begin
  if (Elevation >= 0) or (Progress <= 0) then Exit;
  Edge := RunningArrivalPlatformX(Progress);
  DrawUndergroundStationWall(C, Max(0.0, Edge), DESIGN_W, 452, 48, -Edge,
    EnsureRange(-Elevation, 0.0, 1.0));
end;

procedure DrawRunningArrivalPlatform(C: TTrainCanvas; Elevation, Progress, Zoom: Double);
const
  SURFACE_Y = 574;
  METAL_WIDTH = 10;
  TACTILE_INSET = 26;
  TACTILE_END_GAP = 64;
var
  X, Y, Left, TileX, Offset, Depth, StripeLeft, StripeY: Single;
  I: Integer;
  FloorColor, StripeColor: Cardinal;
begin
  if Progress <= 0 then Exit;
  X := RunningArrivalPlatformX(Progress);
  if X >= DESIGN_W then Exit;
  Y := DESIGN_H * 0.5 + (SURFACE_Y - DESIGN_H * 0.5) * Zoom / 100;
  if Y >= DESIGN_H then Exit;

  Left := Max(0.0, X);
  Depth := EnsureRange(-Elevation, 0.0, 1.0);
  FloorColor := Mix($AFB0A3, $676C69, Depth);
  StripeColor := Mix($D1AE59, $A18B50, Depth);
  C.PushClip(Left, Y, DESIGN_W - Left, DESIGN_H - Y);
  try
    C.Panel(0, Y, DESIGN_W, DESIGN_H - Y, 0, Shade(FloorColor, 1.19), FloorColor, Shade(FloorColor, 0.72));
    Offset := X - Floor(X / 118) * 118;
    for I := -1 to 11 do
    begin
      TileX := I * 118 + Offset;
      C.Line(TileX, Y + 44, TileX, DESIGN_H, 1.4, Shade(FloorColor, 0.64), 0.75);
    end;
    C.Box(0, Y + 49, DESIGN_W, 1.5, 0, Shade(FloorColor, 0.64), 0.71);

    // 点字ブロックは線路側の縁と進入端のどちらからも離す。
    StripeLeft := Max(Left, X + TACTILE_END_GAP);
    StripeY := Y + TACTILE_INSET;
    if StripeLeft < DESIGN_W then
    begin
      C.Box(StripeLeft, StripeY, DESIGN_W - StripeLeft, 16, 0, StripeColor);
      for I := Ceil((StripeLeft + 3 - X) / 16) to Floor((DESIGN_W - X) / 16) do
      begin
        TileX := X + I * 16;
        C.Oval(TileX, StripeY + 5, 2.8, 1.7, Shade(StripeColor, 1.35));
        C.Oval(TileX + 7, StripeY + 11, 2.8, 1.7, Shade(StripeColor, 0.78));
      end;
    end;

    C.Panel(0, Y, DESIGN_W, METAL_WIDTH, 0, $CED7D1, $929F9E, $596B70);
    C.Box(0, Y + 2, DESIGN_W, 1.4, 0, $D9E1DC);
    C.Panel(X, Y + METAL_WIDTH, METAL_WIDTH, DESIGN_H - Y - METAL_WIDTH, 0,
      $9EA9A5, $77878A, $52646A);
    C.Box(X + 2, Y + METAL_WIDTH, 1.6, DESIGN_H - Y - METAL_WIDTH, 0, $C5D0CA, 0.83);
  finally
    C.PopClip;
  end;
end;

procedure DrawPassingPoles(C: TTrainCanvas; Elevation, Distance, Opacity: Double);
const
  WIDTH = 42;
  EXTENSION = 28;
var
  I: Integer;
  X, Offset, Alpha: Single;
begin
  if Elevation <= -1 then Exit;
  Alpha := Opacity * 0.78 * EnsureRange(1 + Elevation * 2, 0.0, 1.0);
  if Alpha = 0 then Exit;
  Offset := Distance * 1.7;
  X := 1133 - (Offset - Floor(Offset / 1350) * 1350);
  for I := 0 to 1 do
  begin
    C.Box(X - WIDTH * 0.5, -EXTENSION, WIDTH, DESIGN_H + 2 * EXTENSION, 1, $3D5350, Alpha);
    C.Box(X - WIDTH * 0.5 + 5, -EXTENSION, 7, DESIGN_H + 2 * EXTENSION, 0, $B0AE8C, Alpha * 0.60);
    C.Box(X + WIDTH * 0.5 - 5, -EXTENSION, 5, DESIGN_H + 2 * EXTENSION, 0, $243A39, Alpha * 0.47);
    C.Box(X - 53, 99, 106, 12, 3, $4A5D58, Alpha);
    C.Box(X - 50, 101, 100, 2, 1, $8B9C8C, Alpha * 0.53);
    X := X + 1350;
  end;
end;

procedure DrawRunningTrack(C: TTrainCanvas; Elevation, Distance, Zoom: Double);
var
  X, Y, Offset, Height, Depth: Single;
  Bed, Rail: Cardinal;
  I: Integer;
begin
  Y := DESIGN_H * 0.5 + (RUN_RAIL_Y - DESIGN_H * 0.5) * Zoom / 100 - 18;
  if Y >= DESIGN_H then Exit;
  Height := Min(49.0, DESIGN_H - Y);
  Depth := 0;
  if Elevation < 0 then Depth := -Elevation;
  if Elevation >= 0 then
    Bed := Mix($6A7166, $9A9F95, EnsureRange(Elevation * 0.5, 0.0, 1.0))
  else
    Bed := Mix($6A7166, $2B3539, Depth);
  Rail := Shade(Bed, 1.46);
  C.Panel(0, Y, DESIGN_W, Height, 0, Shade(Bed, 0.66), Bed, Shade(Bed, 0.88));
  Offset := Distance - Floor(Distance / 54) * 54;
  for I := -1 to 24 do
  begin
    X := I * 54 - Offset;
    C.Polygon([Pt(X + 6, Y + 7), Pt(X + 13, Y + 7), Pt(X + 22, Y + 33), Pt(X + 9, Y + 33)],
      Shade(Bed, 0.62));
  end;
  C.Box(0, Y + 18, DESIGN_W, 3, 0, Rail);
  C.Box(0, Y + 21, DESIGN_W, 4, 0, Shade(Bed, 0.58));
  C.Box(0, Y + 35, DESIGN_W, 4, 0, Shade(Bed, 0.78));
end;

end.

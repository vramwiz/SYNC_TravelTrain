unit TravelTrain_Scenery;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// ホームと走行風景を描く。SYNC_Elevator の視点高と遠近の考え方を横方向の移動へ応用する。

interface

uses TravelTrain_Canvas, TravelTrain_Settings;

// 出力範囲を塗りつぶす固定の駅背景。扉越しの場合はホームを正面から描く。
procedure DrawStation(C: TTrainCanvas; Scene: TTrainScene);
// 距離と高さから毎回同じ風景を作る。電柱は車体より手前に別描画する。
procedure DrawLandscape(C: TTrainCanvas; const S: TTrainSettings; Distance: Double);
// 床下機器より低い位置に線路面を描く。高さに応じて道床の材質を変える。
procedure DrawRunningTrack(C: TTrainCanvas; Elevation, Distance, Zoom: Double);
procedure DrawPassingPoles(C: TTrainCanvas; Elevation, Distance: Double);

implementation

uses System.Math, Winapi.D2D1;

procedure DrawSky(C: TTrainCanvas; Warm: Boolean);
begin
  if Warm then C.Panel(0, 0, DESIGN_W, DESIGN_H, 0, $668EAA, $B9D8DF, $F1E3C2)
  else C.Panel(0, 0, DESIGN_W, DESIGN_H, 0, $6095B7, $B6D7DF, $F2E6C7);
  C.Glow(1004, 132, 298, 240, $FFF2C8, 0.52);
end;

procedure PlatformTiles(C: TTrainCanvas; Y: Single; NearEdge: Boolean);
var
  I: Integer;
begin
  C.Panel(0, Y, DESIGN_W, DESIGN_H - Y, 0, $BCB8AF, $95958E, $757D7D);
  for I := -7 to 7 do
    C.Line(640 + I * 100, Y, 640 + I * 175, 720, 1.25, $485456, 0.43);
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

procedure DrawWideStationFloor(C: TTrainCanvas; RailY: Single; NearPlatform: Boolean);
var
  I: Integer;
  X, Y, Edge, Ballast, FarRail: Single;
  Gravel: Cardinal;
begin
  Edge := RailY - 59;
  Ballast := RailY - 34;
  FarRail := RailY - 23;
  C.Panel(0, 426, DESIGN_W, Edge - 426, 0, $C1BEB1, $A5A79C, $8B938D);
  for I := -9 to 9 do
    C.Line(640 + I * 69, 426, 640 + I * 111, Edge, 1.4, $6A7774, 0.61);
  C.Box(0, Edge - 44, DESIGN_W, 1.6, 0, $6B7874, 0.58);
  C.Box(0, Edge - 24, DESIGN_W, 14, 0, $C9AB64);
  for I := 0 to 89 do
  begin
    C.Box(7 + I * 14.5, Edge - 21, 10, 1.5, 0.7, $F1D590);
    C.Box(7 + I * 14.5, Edge - 15, 10, 1.5, 0.7, $A28953);
  end;

  C.Panel(0, Edge, DESIGN_W, Ballast - Edge, 0, $868B83, $565E5D, $434D50);
  C.Box(0, Edge - 4, DESIGN_W, 5, 0, $E4DCCA);
  C.Box(0, Edge + 9, DESIGN_W, 2, 0, $A7ACA0);
  for I := 0 to 15 do
    C.Box(I * 89, Edge + 11, 2, 13, 0, $707A76, 0.65);

  C.Panel(0, Ballast, DESIGN_W, DESIGN_H - Ballast, 0, $5F6866, $515B5B, $454D4F);
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

  if NearPlatform then
  begin
    C.Panel(0, RailY + 19, DESIGN_W, 18, 0, $374348, $56615D, $6D7872);
    PlatformTiles(C, RailY + 36, True);
  end;
end;

procedure DrawStation(C: TTrainCanvas; Scene: TTrainScene);
var
  Y, X: Single;
  I, J: Integer;
begin
  DrawSky(C, Scene = tsDeparture);
  C.Polygon([Pt(0, 301), Pt(106, 268), Pt(230, 293), Pt(413, 255), Pt(578, 306),
    Pt(770, 263), Pt(967, 294), Pt(1111, 256), Pt(1280, 299), Pt(1280, 421), Pt(0, 421)], $799792);
  C.Polygon([Pt(0, 344), Pt(103, 315), Pt(263, 351), Pt(400, 320), Pt(549, 347),
    Pt(780, 313), Pt(1023, 343), Pt(1198, 302), Pt(1280, 333), Pt(1280, 421), Pt(0, 421)], $617D77);
  C.Box(0, 334, 1280, 98, 0, $839C95);
  for I := 0 to 19 do
    C.Line(I * 69, 352, I * 69, 430, 3, $536C68);
  C.Box(0, 350, 1280, 5, 0, $B9C8B8);
  C.Box(0, 414, 1280, 14, 0, $70817A);
  case Scene of
    tsArrival:
      begin
        Y := WIDE_ARRIVAL_RAIL_Y - 112;
        DrawWideStationFloor(C, WIDE_ARRIVAL_RAIL_Y, False);
      end;
    tsDeparture:
      begin
        Y := WIDE_DEPARTURE_RAIL_Y - 112;
        DrawWideStationFloor(C, WIDE_DEPARTURE_RAIL_Y, True);
      end;
  else
    Y := 432;
    C.Panel(0, 425, 1280, Y - 416, 0, $68716E, $565D5D, $384648);
    PlatformTiles(C, Y, True);
  end;

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
  I, J, First: Integer;
  X, H, W, V: Single;
  Color: Cardinal;
begin
  First := Floor(Offset / SPACING);
  for I := First - 1 to First + 10 do
  begin
    X := I * SPACING - Offset;
    V := Variation(I, Seed);
    H := 33 + V * 91;
    case Style of
      scTown:
        begin
          W := 53 + Variation(I, Seed + 7) * 65;
          Color := Mix($9CAFA7, $627F83, V);
          C.Box(X, Y - H, W, H + 15, 1, Color);
          C.Box(X + W * 0.68, Y - H, W * 0.32, H + 15, 0, Shade(Color, 0.76));
          C.Box(X + W * 0.16, Y - H - 8, W * 0.42, 9, 0, Shade(Color, 0.84));
          for J := 1 to Trunc(H / 16) do
          begin
            C.Box(X + 8, Y - J * 16, W * 0.16, 5, 0, $DEE0BC, 0.74);
            C.Box(X + W * 0.36, Y - J * 16, W * 0.15, 5, 0, $D8DCC5, 0.75);
          end;
        end;
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
  DrawFarRidge(C, Distance * 0.12, RidgeY - 5, Seed + 31, $9CADAD, S.Scenery = scCoast);
  DrawFarRidge(C, Distance * 0.22, RidgeY + 33, Seed + 11, $769B98, S.Scenery = scCoast);
  case S.Scenery of
    scTown: Ground := $819C90;
    scCoast: Ground := $76A9AB;
  else
    Ground := $A2AD77;
  end;
  C.Panel(0, RidgeY + 67, DESIGN_W, DESIGN_H - RidgeY - 67, 0,
    Shade(Ground, 1.17), Ground, Shade(Ground, 0.72));
  DrawMiddleGround(C, S.Scenery, Distance * 0.47, GroundY, Seed);
  if S.Scenery <> scCoast then
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

procedure DrawPassingPoles(C: TTrainCanvas; Elevation, Distance: Double);
var
  I: Integer;
  X, Offset, Alpha: Single;
begin
  if Elevation <= -1 then Exit;
  Alpha := 0.78 * EnsureRange(1 + Elevation * 2, 0.0, 1.0);
  if Alpha = 0 then Exit;
  Offset := Distance * 1.7;
  X := 1133 - (Offset - Floor(Offset / 1350) * 1350);
  for I := 0 to 1 do
  begin
    C.Box(X - 9, 68, 19, 652, 2, $3D5350, Alpha);
    C.Box(X - 7, 68, 3, 652, 0, $B0AE8C, Alpha * 0.60);
    C.Box(X - 36, 99, 69, 9, 2, $4A5D58, Alpha);
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

unit TravelTrain_Art;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 全シーンで共用する車体・窓・扉と、立ち絵を挟む静止層を描く。

interface

uses TravelTrain_Settings, TravelTrain_Canvas;

// 引きの車両側面。Shift は論理ピクセル単位の進行位置。
procedure DrawWideTrain(C: TTrainCanvas; const S: TTrainSettings; Shift: Single;
  Departure: Boolean);
// 乗車と降車は同じ開口とストロークを共有し、内外面の仕上げを切り替える。
procedure DrawSlidingDoors(C: TTrainCanvas; const S: TTrainSettings; Opening: Single;
  Inside: Boolean);
// 足元は立ち絵の後ろ、扉枠と座席の前縁は立ち絵の手前に置く。
procedure DrawBoardFloor(C: TTrainCanvas);
procedure DrawBoardCabin(C: TTrainCanvas; const S: TTrainSettings);
procedure DrawExitRear(C: TTrainCanvas; const S: TTrainSettings);
// 走行時の窓と座席は同じ固定座標とズームを使う。
procedure DrawRunCabin(C: TTrainCanvas; const S: TTrainSettings);
procedure DrawRunBody(C: TTrainCanvas; const S: TTrainSettings);

implementation

uses System.Math, Winapi.D2D1;

const
  DOOR_L = 399;
  DOOR_R = 881;
  DOOR_T = 106;
  DOOR_B = 592;
  DOOR_W = DOOR_R - DOOR_L;
  DOOR_H = DOOR_B - DOOR_T;
  BOARD_L = 459;
  BOARD_R = DESIGN_W - BOARD_L;
  BOARD_T = 148;
  BOARD_B = 653;
  BOARD_W = BOARD_R - BOARD_L;
  BOARD_H = BOARD_B - BOARD_T;
  BOARD_SIDE_X = -55;
  BOARD_SIDE_Y = 172;
  BOARD_SIDE_W = 286;
  BOARD_SIDE_H = 271;
  BOARD_SIDE_RADIUS = 22;
  RUN_WINDOW_X: array[0..2] of Single = (-134, 472, 1124);
  RUN_WINDOW_W: array[0..2] of Single = (290, 336, 290);
  RUN_WINDOW_Y = 248;
  RUN_WINDOW_H = 178;
  RUN_WINDOW_B = RUN_WINDOW_Y + RUN_WINDOW_H;
  RUN_DOOR_W = 228;
  RUN_DOOR_LEFT = 200;
  RUN_BODY_L = -155;
  RUN_BODY_R = 1435;

function WindowRadius(Style: TTrainStyle): Single;
begin
  case Style of
    trExpress: Result := 20;
    trStreamlined: Result := 31;
  else
    Result := 12;
  end;
end;

procedure Skin(C: TTrainCanvas; const S: TTrainSettings; X, Y, W, H, Radius: Single);
begin
  if S.Style = trStainless then C.Metal(X, Y, W, H, Radius, S.Colors.Body)
  else C.Panel(X, Y, W, H, Radius, Shade(S.Colors.Body, 1.26), S.Colors.Body,
    Shade(S.Colors.Body, 0.76));
end;

procedure Livery(C: TTrainCanvas; const S: TTrainSettings; X, Y, W, H: Single);
begin
  C.Box(X, Y, W, H, 0, S.Colors.Stripe);
  C.Box(X, Y, W, 2, 0, Shade(S.Colors.Stripe, 1.48), 0.75);
  if S.Style in [trExpress, trStreamlined] then
    C.Box(X, Y + H + 5, W, Max(2.0, H * 0.16), 0, S.Colors.Stripe)
  else
    C.Box(X, Y + H - 3, W, 3, 0, Shade(S.Colors.Stripe, 0.73));
end;

procedure OpaqueWindow(C: TTrainCanvas; X, Y, W, H, Radius: Single);
begin
  C.Box(X - 4, Y - 4, W + 8, H + 8, Radius + 3, $23343F);
  C.Panel(X, Y, W, H, Radius, $4D6D7A, $365560, $21353F);
  C.Box(X + 4, Y + 5, W - 8, 3, 1, $B2CECF, 0.41);
  C.Polygon([Pt(X + W * 0.16, Y + 8), Pt(X + W * 0.42, Y + 8),
    Pt(X + W * 0.24, Y + H - 7), Pt(X + 8, Y + H - 7)], $AACBCB, 0.15);
end;

const
  WIDE_BODY_H = 182;
  WIDE_UNDERFRAME_H = 42;
  WIDE_WHEEL_RADIUS = 17;
  WIDE_SIDE_DOOR_W = 78;

type
  TRailCarEnd = (ceMiddle, ceFront, ceRear);

procedure SmallSideDoors(C: TTrainCanvas; const S: TTrainSettings; X: Single);
const
  Y = 30;
  H = WIDE_BODY_H - Y - 10;
var
  Edge: Cardinal;
begin
  Edge := Shade(S.Colors.Body, 0.60);
  C.BoxEdge(X, Y, WIDE_SIDE_DOOR_W, H, 5, 2.5, Edge);
  C.Line(X + WIDE_SIDE_DOOR_W / 2, Y + 2, X + WIDE_SIDE_DOOR_W / 2, Y + H - 2, 2, Edge);
  OpaqueWindow(C, X + 9, Y + 13, 22, 62, 5);
  OpaqueWindow(C, X + 47, Y + 13, 22, 62, 5);
  C.Box(X + 5, Y + H - 6, WIDE_SIDE_DOOR_W - 10, 4, 1, $718080);
end;

procedure DrawBogie(C: TTrainCanvas; Center: Single);
const
  AXLE_Y = WIDE_BODY_H + WIDE_UNDERFRAME_H - WIDE_WHEEL_RADIUS;
var
  X: Single;
  Wheel: Integer;
begin
  for Wheel := -1 to 1 do
  begin
    if Wheel = 0 then Continue;
    X := Center + Wheel * 29;
    C.Oval(X, AXLE_Y, WIDE_WHEEL_RADIUS, WIDE_WHEEL_RADIUS, $242E33);
    C.Oval(X, AXLE_Y, 13.5, 13.5, $758382);
    C.Oval(X, AXLE_Y, 11, 11, $444F51);
    C.Oval(X, AXLE_Y, 6.5, 6.5, $667572);
    C.Oval(X, AXLE_Y, 3.2, 3.2, $B0B4A7);
  end;
  C.Polygon([Pt(Center - 50, AXLE_Y - 10), Pt(Center - 38, AXLE_Y - 7),
    Pt(Center - 18, AXLE_Y - 10), Pt(Center + 18, AXLE_Y - 10),
    Pt(Center + 38, AXLE_Y - 7), Pt(Center + 50, AXLE_Y - 10),
    Pt(Center + 45, AXLE_Y + 2), Pt(Center + 21, AXLE_Y + 5),
    Pt(Center - 21, AXLE_Y + 5), Pt(Center - 45, AXLE_Y + 2)], $35434A);
  C.Line(Center - 19, AXLE_Y + 1, Center + 19, AXLE_Y + 1, 2.5, $7B8883);
  C.Box(Center - 15, AXLE_Y - 17, 30, 10, 3, $64736D);
  C.Box(Center - 10, AXLE_Y - 15, 20, 3, 1, $303B3D);
  C.Box(Center - 10, AXLE_Y - 10, 20, 2, 1, $303B3D);
end;

procedure DrawUnderframe(C: TTrainCanvas; CarEnd: TRailCarEnd; BodyColor: Cardinal);
const
  Y = WIDE_BODY_H;
  W = WIDE_CAR_LENGTH;
var
  I: Integer;
begin
  C.Box(16, Y - 5, W - 32, 12, 3, $36444A);
  C.Box(23, Y + 4, W - 46, 4, 1, $67746E);
  DrawBogie(C, 157);
  DrawBogie(C, W - 157);
  C.Panel(245, Y + 4, 111, 24, 3, $677670, $485753, $2B383E);
  for I := 0 to 5 do
    C.Box(253 + I * 15, Y + 11, 10, 1.8, 0, $2E3E42);
  C.Panel(371, Y + 5, 98, 20, 8, $73807B, $515E5B, $2E4044);
  C.Box(385, Y + 5, 4, 20, 1, $35434A);
  C.Box(452, Y + 5, 4, 20, 1, $35434A);
  C.Panel(482, Y + 4, 76, 27, 2, $62716A, $434F51, $2D373E);
  for I := 0 to 3 do
    C.Box(490 + I * 13, Y + 13, 8, 6, 1, $364246);
  C.Box(564, Y + 5, 26, 12, 2, $56615D);
  if CarEnd <> ceMiddle then
  begin
    // 運転台下で床下を覆う排障器。中央寄りを切り欠いて連結器を見せる。
    C.Polygon([Pt(W - 99, Y - 4), Pt(W - 12, Y - 4), Pt(W - 18, Y + 14),
      Pt(W - 26, Y + 30), Pt(W - 61, Y + 30), Pt(W - 63, Y + 18),
      Pt(W - 79, Y + 18)], $303F48);
    C.Polygon([Pt(W - 97, Y - 2), Pt(W - 13, Y - 2), Pt(W - 19, Y + 11),
      Pt(W - 86, Y + 11)], Shade(BodyColor, 0.66));
    C.Box(W - 75, Y + 13, 23, 9, 2, $202A30);
    C.Box(W - 64, Y + 14, 13, 4, 1, $70817E);
  end;
end;

procedure DrawWideCar(C: TTrainCanvas; const S: TTrainSettings; CarEnd: TRailCarEnd);
const
  W = WIDE_CAR_LENGTH;
  H = WIDE_BODY_H;
var
  Radius, Crown, Shoulder, Face: Single;
  I: Integer;
  BodyOutline: array[0..8] of TD2D1Point2F;
  Light, GlowColor: Cardinal;
begin
  DrawUnderframe(C, CarEnd, S.Colors.Body);
  case S.Style of
    trStreamlined:
      begin
        Crown := 139;
        Shoulder := 73;
        Face := 30;
      end;
    trExpress:
      begin
        Crown := 33;
        Shoulder := 15;
        Face := 9;
      end;
  else
    Crown := 43;
    Shoulder := 19;
    Face := 10;
  end;
  if CarEnd = ceMiddle then
  begin
    Crown := 18;
    Shoulder := 9;
    Face := 7;
  end;

  C.Panel(224, -12, 182, 17, 5, $ADB9B5, $7B8B8B, $495959);
  C.Box(245, -10, 138, 2, 1, $C7CEC5);
  C.Box(268, -7, 92, 2, 1, $698081);
  C.Panel(492, -8, 54, 11, 3, $95A4A0, $6E8181, $4B5D62);
  BodyOutline[0] := Pt(8, 20);
  BodyOutline[1] := Pt(14, 7);
  BodyOutline[2] := Pt(28, 0);
  BodyOutline[3] := Pt(W - Crown, 0);
  BodyOutline[4] := Pt(W - Shoulder, 23);
  BodyOutline[5] := Pt(W - Face, 60);
  BodyOutline[6] := Pt(W - 7, H - 15);
  BodyOutline[7] := Pt(W - 18, H);
  BodyOutline[8] := Pt(8, H);
  C.PushShapeClip(D2D1RectF(0, 0, W, H), BodyOutline);
  try
    Skin(C, S, 0, 0, W, H, 0);
    C.Panel(0, 0, W, 25, 0, $617679, $B2BEBA, Shade(S.Colors.Body, 0.85));
    C.Line(17, 23, W - 6, 23, 2.5, Shade(S.Colors.Body, 1.38));
    Livery(C, S, 0, 115, W, 22);
    C.Box(0, H - 12, W, 6, 0, Shade(S.Colors.Body, 0.64), 0.70);

    Radius := WindowRadius(S.Style) * 0.49;
    if S.Style in [trExpress, trStreamlined] then
    begin
      SmallSideDoors(C, S, 24);
      for I := 0 to 4 do
        OpaqueWindow(C, 125 + I * 96, 49, 77, 56, Radius);
      SmallSideDoors(C, S, 614);
    end
    else
    begin
      SmallSideDoors(C, S, 66);
      SmallSideDoors(C, S, 329);
      SmallSideDoors(C, S, 579);
      OpaqueWindow(C, 167, 48, 63, 59, Radius);
      OpaqueWindow(C, 246, 48, 63, 59, Radius);
      OpaqueWindow(C, 428, 48, 59, 59, Radius);
      OpaqueWindow(C, 505, 48, 56, 59, Radius);
    end;

    if CarEnd = ceMiddle then
      OpaqueWindow(C, W - 113, 49, 91, 56, Radius)
    else
    begin
      C.Line(W - 118, 34, W - 118, H - 12, 2, Shade(S.Colors.Body, 0.61));
      if S.Style = trStreamlined then
      begin
        C.Polygon([Pt(W - 99, 30), Pt(W - 76, 30), Pt(W - 59, 55),
          Pt(W - 59, 108), Pt(W - 94, 108)], $23343F);
        C.GradientPolygon([Pt(W - 94, 35), Pt(W - 79, 35), Pt(W - 64, 57),
          Pt(W - 64, 103), Pt(W - 89, 103)], Pt(W - 95, 35), Pt(W - 70, 103),
          $4D6D7A, $365560, $21353F);
        C.Polygon([Pt(W - 90, 39), Pt(W - 80, 39), Pt(W - 83, 96),
          Pt(W - 87, 96)], $9DBEC0, 0.42);
      end
      else
        OpaqueWindow(C, W - 78, 35, 30, 74, Radius);
      if CarEnd = ceRear then
      begin
        Light := $B74E48;
        GlowColor := $FF9B87;
      end
      else
      begin
        Light := $DFC99B;
        GlowColor := $FFF1C9;
      end;
      C.Box(W - 44, 123, 30, 11, 4, $394B51);
      C.Box(W - 41, 125, 24, 6, 3, Light);
      C.Box(W - 37, 125, 14, 2, 1, GlowColor);
    end;
  finally
    C.PopShapeClip;
  end;
end;

procedure DrawWideTrain(C: TTrainCanvas; const S: TTrainSettings; Shift: Single;
  Departure: Boolean);
const
  Y = -WIDE_BODY_H - WIDE_UNDERFRAME_H;
var
  X, RailY, Nose, JoinX, Left, Right: Single;
  Car: Integer;
  CarEnd: TRailCarEnd;
  Transform, Previous, View: TD2D1Matrix3x2F;
begin
  RailY := WIDE_ARRIVAL_RAIL_Y;
  if Departure then RailY := WIDE_DEPARTURE_RAIL_Y;
  Nose := WIDE_TRAIN_NOSE + Shift;
  Left := -Nose / WIDE_TRAIN_SCALE;
  Right := (DESIGN_W - Nose) / WIDE_TRAIN_SCALE;

  // 車輪の下端をローカル座標の Y=0 に置き、拡大後もレールに合わせる。
  View := C.ApplyTransform(TD2D1Matrix3x2F.Scale(WIDE_TRAIN_SCALE, WIDE_TRAIN_SCALE, Pt(0, 0)) *
    TD2D1Matrix3x2F.Translation(Nose, RailY));
  try
    for Car := 1 to WIDE_CAR_COUNT - 1 do
    begin
      JoinX := -Car * WIDE_CAR_LENGTH;
      if (JoinX < Left - 15) or (JoinX > Right + 15) then Continue;
      C.Box(JoinX - 10, Y + 27, 20, WIDE_BODY_H - 36, 2, $2F3A3E);
      C.Line(JoinX, Y + 34, JoinX, Y + WIDE_BODY_H - 14, 2, $65716E);
      C.Box(JoinX - 15, Y + WIDE_BODY_H + 3, 30, 10, 2, $29363E);
    end;
    for Car := WIDE_CAR_COUNT - 1 downto 0 do
    begin
      X := -(Car + 1) * WIDE_CAR_LENGTH;
      if (X >= Right) or (X + WIDE_CAR_LENGTH <= Left) then Continue;
      C.Oval(X + WIDE_CAR_LENGTH / 2, 4, WIDE_CAR_LENGTH * 0.48, 7, $1D2527, 0.32);
      CarEnd := ceMiddle;
      if Car = 0 then CarEnd := ceFront
      else if Car = WIDE_CAR_COUNT - 1 then CarEnd := ceRear;
      Transform := TD2D1Matrix3x2F.Translation(X, Y);
      if CarEnd = ceRear then
        Transform := TD2D1Matrix3x2F.Scale(-1, 1, Pt(0, 0)) *
          TD2D1Matrix3x2F.Translation(X + WIDE_CAR_LENGTH, Y);
      Previous := C.ApplyTransform(Transform);
      try
        DrawWideCar(C, S, CarEnd);
      finally
        C.RestoreTransform(Previous);
      end;
    end;
  finally
    C.RestoreTransform(View);
  end;
end;

procedure DoorLeaf(C: TTrainCanvas; const S: TTrainSettings; X: Single; Left: Boolean);
var
  W, Seam, GlassX, Radius: Single;
  Color, Edge: Cardinal;
begin
  W := DOOR_W / 2 + 1;
  Color := S.Colors.Body;
  Edge := Shade(Color, 0.58);
  GlassX := X + 29;
  Radius := WindowRadius(S.Style) * 0.65;
  C.Panel(X, DOOR_T, W, 57, 0, Shade(Color, 0.81), Color, Shade(Color, 1.14));
  C.Panel(X, DOOR_T + 247, W, DOOR_H - 247, 0,
    Shade(Color, 1.15), Color, Shade(Color, 0.77));
  C.Box(X, DOOR_T + 57, 29, 190, 0, Color);
  C.Box(X + W - 29, DOOR_T + 57, 29, 190, 0, Color);
  C.Box(GlassX, DOOR_T + 57, W - 58, 190, 0, $335764, 0.50);
  C.BoxEdge(GlassX, DOOR_T + 57, W - 58, 190, Radius, 7, $2A3C44);
  C.Box(GlassX + 9, DOOR_T + 66, W - 76, 4, 2, $E4EBCE, 0.50);
  C.Polygon([Pt(GlassX + 30, DOOR_T + 74), Pt(GlassX + 66, DOOR_T + 74),
    Pt(GlassX + 22, DOOR_T + 230), Pt(GlassX + 11, DOOR_T + 230)], $E2ECE1, 0.15);
  Livery(C, S, X, DOOR_T + 265, W, 43);
  C.Box(X + 10, DOOR_B - 29, W - 20, 17, 2, Shade(Color, 0.68));
  Seam := X;
  if Left then Seam := X + W - 5;
  C.Box(Seam, DOOR_T, 5, DOOR_H, 0, $26363C);
  C.BoxEdge(X + 2, DOOR_T + 3, W - 4, DOOR_H - 7, 2, 2, Edge);
end;

procedure BoardDoorLeaf(C: TTrainCanvas; const S: TTrainSettings; X: Single; Left: Boolean);
const
  W = BOARD_W / 2 + 1;
  GLASS_Y = BOARD_T + 25;
  GLASS_W = W - 54;
  GLASS_H = 254;
  GLASS_RADIUS = 22;
var
  GlassX, Seam, OuterEdge: Single;
  Paint: Cardinal;
begin
  GlassX := X + 27;
  Paint := Mix($E2E5E1, S.Colors.Body, 0.26);
  if Left then
  begin
    Seam := X + W - 4;
    OuterEdge := X;
  end
  else
  begin
    Seam := X;
    OuterEdge := X + W - 13;
  end;
  C.PushCutouts(D2D1RectF(X, BOARD_T, X + W, BOARD_B),
    [D2D1RoundedRect(D2D1RectF(GlassX, GLASS_Y, GlassX + GLASS_W, GLASS_Y + GLASS_H),
      GLASS_RADIUS, GLASS_RADIUS)]);
  try
    C.Panel(X, BOARD_T, W, BOARD_H, 0, Shade(Paint, 1.27), Paint, Shade(Paint, 0.87));
    C.Line(X + 17, BOARD_T + 6, X + 17, BOARD_B - 43, 1.5, Shade(Paint, 1.35), 0.66);
    C.Metal(X, BOARD_B - 43, W, 43, 0, $A7B0AD);
    C.Box(X, BOARD_B - 43, W, 3, 0, $DDE4DD);
    C.Box(X, BOARD_B - 7, W, 5, 0, $6E7E7C);
    C.Box(OuterEdge, BOARD_T, 13, BOARD_H - 43, 0, $DEA93D);
    C.Box(OuterEdge + 2, BOARD_T, 3, BOARD_H - 43, 0, $FFDA79);
    C.Box(Seam, BOARD_T, 4, BOARD_H, 0, $313A3A);
  finally
    C.PopShapeClip;
  end;
  C.Box(GlassX, GLASS_Y, GLASS_W, GLASS_H, GLASS_RADIUS, $9CC9CD, 0.17);
  C.BoxEdge(GlassX, GLASS_Y, GLASS_W, GLASS_H, GLASS_RADIUS, 10, $303D42);
  C.BoxEdge(GlassX + 5, GLASS_Y + 5, GLASS_W - 10, GLASS_H - 10, GLASS_RADIUS - 5,
    2, $768F91, 0.84);
  C.Line(GlassX + 22, GLASS_Y + 10, GlassX + GLASS_W - 23, GLASS_Y + 10, 2.5, $EAF6EF, 0.68);
  C.Polygon([Pt(GlassX + 25, GLASS_Y + 14), Pt(GlassX + 49, GLASS_Y + 14),
    Pt(GlassX + 26, GLASS_Y + GLASS_H - 18), Pt(GlassX + 13, GLASS_Y + GLASS_H - 32)],
    $E0F6F1, 0.20);
  C.Box(GlassX + GLASS_W - 25, GLASS_Y + GLASS_H - 31, 12, 17, 3, $E2EBD4, 0.78);
end;

procedure DrawSlidingDoors(C: TTrainCanvas; const S: TTrainSettings; Opening: Single;
  Inside: Boolean);
type
  TDoorPainter = procedure(C: TTrainCanvas; const S: TTrainSettings; X: Single; Left: Boolean);
var
  X, Y, W, H, Stroke: Single;
  PaintDoor: TDoorPainter;
begin
  if Opening >= 1 then Exit;
  if Inside then
  begin
    X := BOARD_L;
    Y := BOARD_T;
    W := BOARD_W;
    H := BOARD_H;
    PaintDoor := BoardDoorLeaf;
  end
  else
  begin
    X := DOOR_L;
    Y := DOOR_T;
    W := DOOR_W;
    H := DOOR_H;
    PaintDoor := DoorLeaf;
  end;
  Stroke := Opening * (W * 0.5 + 1);
  C.PushClip(X, Y, W, H);
  try
    PaintDoor(C, S, X - Stroke, True);
    PaintDoor(C, S, X + W * 0.5 + Stroke, False);
  finally
    C.PopClip;
  end;
end;

procedure DrawBoardFloor(C: TTrainCanvas);
var
  X, Y: Integer;
begin
  C.Panel(0, BOARD_B, DESIGN_W, DESIGN_H - BOARD_B, 0, $647173, $39474C, $26343A);
  C.Polygon([Pt(BOARD_L - 12, BOARD_B + 8), Pt(BOARD_R + 12, BOARD_B + 8),
    Pt(BOARD_R + 105, DESIGN_H - 5), Pt(BOARD_L - 105, DESIGN_H - 5)], $8D9A98, 0.68);
  C.Metal(BOARD_L - 9, BOARD_B, BOARD_W + 18, 15, 2, $B3BCB4);
  C.Box(BOARD_L - 9, BOARD_B + 9, BOARD_W + 18, 4, 0, $EBC469);
  C.Line(0, BOARD_B + 24, BOARD_L - 45, BOARD_B + 24, 1.5, $6F8182, 0.75);
  C.Line(BOARD_R + 45, BOARD_B + 24, DESIGN_W, BOARD_B + 24, 1.5, $6F8182, 0.75);
  for Y := 0 to 7 do
    for X := -20 - Y to 20 + Y do
      C.Box(DESIGN_W / 2 + X * 9 + (Y mod 2) * 3, BOARD_B + 20 + Y * 5,
        2.7, 1.6, 0.5, $3B4A4D, 0.65);
end;

procedure DrawBoardSide(C: TTrainCanvas; Seat: Cardinal);
begin
  // 側窓は後ろのホームが透ける。片側の形を反転し、反対側にも同じ構造を描く。
  C.Box(BOARD_SIDE_X, BOARD_SIDE_Y, BOARD_SIDE_W, BOARD_SIDE_H, BOARD_SIDE_RADIUS, $8BBFC5, 0.14);
  C.BoxEdge(BOARD_SIDE_X, BOARD_SIDE_Y, BOARD_SIDE_W, BOARD_SIDE_H, BOARD_SIDE_RADIUS, 12, $334348);
  C.BoxEdge(BOARD_SIDE_X - 8, BOARD_SIDE_Y - 8, BOARD_SIDE_W + 16, BOARD_SIDE_H + 16,
    BOARD_SIDE_RADIUS + 8, 4, $A3B0AC);
  C.BoxEdge(BOARD_SIDE_X + 6, BOARD_SIDE_Y + 6, BOARD_SIDE_W - 12, BOARD_SIDE_H - 12,
    BOARD_SIDE_RADIUS - 6, 2, $C5D6D0, 0.78);
  C.Polygon([Pt(47, BOARD_SIDE_Y + 13), Pt(94, BOARD_SIDE_Y + 13),
    Pt(33, BOARD_SIDE_Y + BOARD_SIDE_H - 13), Pt(10, BOARD_SIDE_Y + BOARD_SIDE_H - 21)],
    $DFEFEA, 0.19);
  C.Line(3, BOARD_SIDE_Y + BOARD_SIDE_H + 7, 240, BOARD_SIDE_Y + BOARD_SIDE_H + 7,
    4, $E0E5DA);

  C.Panel(269, 221, 132, 96, 4, $DCE2DD, $A2B4AC, $819790);
  C.BoxEdge(269, 221, 132, 96, 4, 3, $7F908A);
  C.Box(279, 233, 111, 72, 2, $A7B8AF);
  C.Polygon([Pt(287, 236), Pt(320, 236), Pt(309, 300), Pt(288, 300)], $D9E3D7, 0.54);
  C.Box(328, 250, 49, 4, 1, $D4DFD5);
  C.Box(328, 262, 35, 3, 1, $D4DFD5);

  // ロングシートと丸みのある袖仕切り。手前側の支柱と座席の脚を別の材質で描く。
  C.Metal(-16, 600, 384, 50, 4, $869592);
  C.Panel(-22, 444, 385, 131, 18, Shade(Seat, 1.27), Seat, Shade(Seat, 0.51));
  C.Line(0, 453, 310, 453, 2, Shade(Seat, 1.19));
  C.Line(111, 460, 111, 558, 2, Shade(Seat, 0.72));
  C.Line(228, 460, 228, 558, 2, Shade(Seat, 0.72));
  C.Panel(-23, 553, 387, 79, 21, Shade(Seat, 1.38), Seat, Shade(Seat, 0.58));
  C.Line(0, 614, 290, 614, 2, Shade(Seat, 0.63));
  C.Polygon([Pt(249, 616), Pt(255, 564), Pt(267, 502), Pt(285, 447),
    Pt(310, 398), Pt(337, 371), Pt(365, 356), Pt(398, 350), Pt(403, 607),
    Pt(386, 624), Pt(349, 639), Pt(308, 648), Pt(276, 646), Pt(258, 636)], $344248);
  C.GradientPolygon([Pt(259, 615), Pt(269, 564), Pt(280, 508), Pt(296, 456),
    Pt(320, 407), Pt(345, 381), Pt(371, 368), Pt(394, 363), Pt(397, 604),
    Pt(380, 619), Pt(346, 632), Pt(305, 640), Pt(278, 639), Pt(265, 629)],
    Pt(272, 388), Pt(398, 642), $F2F0E4, $D3DCD7, $A6B2AC);
  C.StrokePath([Pt(266, 623), Pt(273, 572), Pt(289, 508), Pt(307, 464),
    Pt(330, 418), Pt(355, 393)], 2, $EBEDE4);

  C.StrokePath([Pt(207, 157), Pt(220, 166), Pt(229, 181), Pt(233, 204),
    Pt(233, 485), Pt(236, 503), Pt(246, 517), Pt(260, 521), Pt(273, 521)],
    15, $667573);
  C.StrokePath([Pt(207, 155), Pt(220, 164), Pt(228, 180), Pt(231, 202),
    Pt(231, 485), Pt(234, 499), Pt(245, 513), Pt(261, 518), Pt(273, 518)],
    8, $BDC8C0);
  C.StrokePath([Pt(209, 159), Pt(220, 168), Pt(229, 188), Pt(232, 215),
    Pt(232, 471)], 12, $C99440);
  C.StrokePath([Pt(211, 158), Pt(222, 174), Pt(230, 200), Pt(230, 464)], 4, $F9CA6E);
  C.StrokePath([Pt(427, 330), Pt(435, 343), Pt(438, 359), Pt(438, 492), Pt(430, 501)],
    10, $A6783D);
  C.StrokePath([Pt(427, 329), Pt(433, 344), Pt(435, 365), Pt(435, 493), Pt(429, 498)],
    5, $F3C670);
end;

procedure DrawBoardDisplays(C: TTrainCanvas; Stripe: Cardinal);
var
  I: Integer;
begin
  C.Panel(BOARD_L - 26, 27, BOARD_W + 52, BOARD_T - 30, 8, $5F6F70, $414F53, $2C3B40);
  C.Box(BOARD_L - 7, 48, 167, 70, 5, $162B33);
  C.Box(BOARD_L - 2, 54, 157, 57, 3, $E5ECE3);
  C.Box(BOARD_L - 2, 54, 157, 14, 2, Mix($3B716F, Stripe, 0.40));
  C.Box(BOARD_L + 14, 76, 67, 4, 1.5, $53747B);
  C.Box(BOARD_L + 14, 93, 118, 2, 1, $A0B7B1);
  for I := 0 to 4 do
  begin
    C.Oval(BOARD_L + 17 + I * 27, 94, 3.5, 3.5, $4E7772);
    C.Oval(BOARD_L + 17 + I * 27, 94, 1.8, 1.8, $DAE9DD);
  end;
  C.Box(BOARD_R - 160, 48, 167, 70, 5, $172C35);
  C.Panel(BOARD_R - 155, 53, 157, 59, 3, $769CA7, $456878, $35585E);
  C.Polygon([Pt(BOARD_R - 151, 108), Pt(BOARD_R - 112, 82), Pt(BOARD_R - 91, 96),
    Pt(BOARD_R - 61, 69), Pt(BOARD_R - 3, 109)], $A4BFB5, 0.83);
  C.Box(BOARD_R - 142, 59, 78, 3, 1, $E2EAE0, 0.87);
  C.Box(BOARD_R - 142, 67, 51, 2.6, 1, $D8E5DC, 0.68);
  C.Box(BOARD_L + 90, BOARD_T - 13, BOARD_W - 180, 3, 1, $D0DDD2, 0.75);
end;

procedure DrawBoardStraps(C: TTrainCanvas);
const
  X: array[0..7] of Integer = (45, 165, 290, 440, 840, 990, 1115, 1235);
  Y: array[0..7] of Integer = (90, 58, 72, 96, 96, 72, 58, 90);
var
  I: Integer;
begin
  C.Line(0, 10, DESIGN_W, 10, 7, $D2D8CE);
  C.Line(0, 8, DESIGN_W, 8, 2, $F7F8EA);
  for I := Low(X) to High(X) do
  begin
    C.Line(X[I], 12, X[I], Y[I] - 22, 8, $A8A89A);
    C.Line(X[I] - 1, 12, X[I] - 1, Y[I] - 23, 3, $D7D3BF);
    C.Box(X[I] - 7, Y[I] - 34, 14, 24, 3, $BC9048);
    C.Box(X[I] - 5, Y[I] - 33, 4, 21, 1.5, $EBC778);
    C.Ring(X[I], Y[I], 21, 23, 8, $B78239);
    C.Ring(X[I] - 1, Y[I] - 1, 21, 23, 3.5, $F0C575);
  end;
end;

procedure DrawBoardCabin(C: TTrainCanvas; const S: TTrainSettings);
var
  Seat, Wall: Cardinal;
  Holes: array[0..2] of TD2D1RoundedRect;
  Previous: TD2D1Matrix3x2F;
begin
  Seat := Mix($294B44, S.Colors.Stripe, 0.34);
  Wall := Mix($DADED7, S.Colors.Body, 0.22);
  C.Panel(0, 0, DESIGN_W, BOARD_T, 0, $FBFAF1, $EFEEE5, $D3DDD7);
  C.Box(36, 23, 286, 9, 3, $FFFCF1);
  C.Box(DESIGN_W - 322, 23, 286, 9, 3, $FFFCF1);
  C.Box(0, BOARD_T - 10, DESIGN_W, 10, 0, $788985);
  C.Line(0, BOARD_T - 8, DESIGN_W, BOARD_T - 8, 2, $CBD5CC);
  Holes[0] := D2D1RoundedRect(D2D1RectF(BOARD_L, BOARD_T, BOARD_R, BOARD_B), 0, 0);
  Holes[1] := D2D1RoundedRect(D2D1RectF(BOARD_SIDE_X, BOARD_SIDE_Y,
    BOARD_SIDE_X + BOARD_SIDE_W, BOARD_SIDE_Y + BOARD_SIDE_H), BOARD_SIDE_RADIUS, BOARD_SIDE_RADIUS);
  Holes[2] := D2D1RoundedRect(D2D1RectF(DESIGN_W - BOARD_SIDE_X - BOARD_SIDE_W, BOARD_SIDE_Y,
    DESIGN_W - BOARD_SIDE_X, BOARD_SIDE_Y + BOARD_SIDE_H), BOARD_SIDE_RADIUS, BOARD_SIDE_RADIUS);
  C.PushCutouts(D2D1RectF(BOARD_SIDE_X - 12, BOARD_T, DESIGN_W - BOARD_SIDE_X + 12, BOARD_B), Holes);
  try
    C.Panel(0, BOARD_T, DESIGN_W, BOARD_H, 0, Shade(Wall, 1.22), Wall, Shade(Wall, 0.78));
    C.Metal(0, BOARD_B - 46, DESIGN_W, 46, 0, $A6B1AC);
  finally
    C.PopShapeClip;
  end;
  DrawBoardSide(C, Seat);
  Previous := C.ApplyTransform(TD2D1Matrix3x2F.Scale(-1, 1, Pt(DESIGN_W / 2, 0)));
  try
    DrawBoardSide(C, Seat);
  finally
    C.RestoreTransform(Previous);
  end;
  C.Box(BOARD_L - 14, BOARD_T, 14, BOARD_H, 1, $475956);
  C.Box(BOARD_R, BOARD_T, 14, BOARD_H, 1, $475956);
  C.Box(BOARD_L - 10, BOARD_T, 6, BOARD_H - 43, 1, $E2B65D);
  C.Box(BOARD_R + 4, BOARD_T, 6, BOARD_H - 43, 1, $E2B65D);
  C.Line(BOARD_L - 16, BOARD_T + 1, BOARD_R + 16, BOARD_T + 1, 5, $304348);
  DrawBoardDisplays(C, S.Colors.Stripe);
  DrawBoardStraps(C);
end;

procedure DrawExitRear(C: TTrainCanvas; const S: TTrainSettings);
var
  I: Integer;
  X: Single;
begin
  C.Panel(0, 0, DESIGN_W, DESIGN_H, 0, $617F8B, $A1B9B5, $536A69);
  C.Box(0, 22, DESIGN_W, 603, 24, $283E46);
  Skin(C, S, 0, 41, DESIGN_W, 578, 12);
  Livery(C, S, 0, DOOR_T + 265, DESIGN_W, 43);
  C.Box(0, 536, DESIGN_W, 3, 0, Shade(S.Colors.Body, 0.67), 0.7);
  C.Box(DOOR_L - 16, DOOR_T - 13, DOOR_W + 32, DOOR_H + 26, 12, $30434A);
  C.PushClip(DOOR_L, DOOR_T, DOOR_W, DOOR_H);
  try
    C.Panel(DOOR_L, DOOR_T, DOOR_W, DOOR_H, 0, $A5997F, $CED0B7, $5F7774);
    C.Polygon([Pt(DOOR_L, DOOR_T), Pt(DOOR_R, DOOR_T), Pt(775, 170),
      Pt(505, 170)], $E1D6B4);
    C.Box(537, 139, 206, 7, 3, $FFF0BC);
    OpaqueWindow(C, 513, 211, 254, 153, 13);
    C.Panel(438, 351, 93, 151, 14, $79958F, $4E7973, $2C534F);
    C.Panel(749, 351, 93, 151, 14, $79958F, $4E7973, $2C534F);
    C.Polygon([Pt(DOOR_L, DOOR_B), Pt(DOOR_R, DOOR_B), Pt(777, 469),
      Pt(503, 469)], $617F81);
    for I := -3 to 3 do C.Line(640 + I * 70, DOOR_B, 640 + I * 43, 474, 2, $ACB9AD, 0.6);
    C.Box(DOOR_L, DOOR_B - 7, DOOR_W, 7, 0, $D3C08A);
    C.Box(DOOR_L, DOOR_T, 8, DOOR_H, 0, $25343D);
    C.Box(DOOR_R - 8, DOOR_T, 8, DOOR_H, 0, $25343D);
  finally
    C.PopClip;
  end;
  for I := 0 to 1 do
  begin
    X := 56 + I * 877;
    OpaqueWindow(C, X, 166, 290, 190, WindowRadius(S.Style));
    C.Box(X + 6, 433, 278, 6, 2, Shade(S.Colors.Body, 0.7));
  end;
  C.Panel(0, 612, DESIGN_W, 108, 0, $B9B4A7, $92948A, $707D7D);
  C.Box(0, 618, DESIGN_W, 25, 0, $C8A962);
  for I := 0 to 91 do C.Oval(7 + I * 14, 627 + (I mod 2) * 8, 3, 2, $F2D28B);
  for I := -8 to 8 do C.Line(640 + I * 90, 654, 640 + I * 133, 720, 2, $626D6D, 0.72);
end;

procedure DrawRunCabin(C: TTrainCanvas; const S: TTrainSettings);
const
  SEAT_TOP = RUN_WINDOW_B - 78;
var
  I: Integer;
  X, W: Single;
  Seat: Cardinal;
begin
  Seat := Mix($466F74, S.Colors.Stripe, 0.55);
  for I := Low(RUN_WINDOW_X) to High(RUN_WINDOW_X) do
  begin
    X := RUN_WINDOW_X[I];
    W := RUN_WINDOW_W[I];
    C.PushClip(X + 5, RUN_WINDOW_Y + 5, W - 10, RUN_WINDOW_H - 10);
    try
      C.Box(X + 4, RUN_WINDOW_Y + 3, W - 8, 21, 3, $AAB3A7);
      C.Box(X + 28, RUN_WINDOW_Y + 9, W - 56, 4, 2, $FFF1C2, 0.81);
      C.Box(X + 3, RUN_WINDOW_B - 68, W - 6, 68, 6, $7D9691);
      C.Box(X + 4, RUN_WINDOW_B - 68, W - 8, 5, 1, $C5CEB4);
      C.Panel(X + 15, RUN_WINDOW_B - 45, W - 30, 62, 15, Shade(Seat, 1.27), Seat, Shade(Seat, 0.64));
      C.Panel(X + 15, SEAT_TOP, W * 0.22, 97, 13, Shade(Seat, 1.16), Seat, Shade(Seat, 0.68));
      C.Panel(X + W * 0.78 - 15, SEAT_TOP, W * 0.22, 97, 13,
        Shade(Seat, 1.16), Seat, Shade(Seat, 0.68));
      C.Box(X + 23, SEAT_TOP + 9, W * 0.16, 3, 1.5, Shade(Seat, 1.38), 0.75);
      C.Box(X + W * 0.84 - 23, SEAT_TOP + 9, W * 0.16, 3, 1.5, Shade(Seat, 1.38), 0.75);
      C.Line(X + W * 0.5, RUN_WINDOW_B - 39, X + W * 0.5, RUN_WINDOW_B - 3, 2, Shade(Seat, 0.55));
    finally
      C.PopClip;
    end;
  end;
end;

procedure DrawRunSideDoor(C: TTrainCanvas; const S: TTrainSettings; X: Single);
const
  Y = RUN_WINDOW_Y - 26;
  B = 574;
  W = RUN_DOOR_W;
  GLASS_W = 54;
  GLASS_INSET = (W div 2 - GLASS_W) div 2;
  GLASS_H = RUN_WINDOW_H - 10;
var
  Paint: Cardinal;
begin
  Paint := Mix(S.Colors.Body, S.Colors.Stripe, 0.76);
  C.Box(X - 5, Y - 6, W + 10, B - Y + 13, 9, Shade(S.Colors.Body, 0.51));
  C.Panel(X, Y, W, B - Y, 6, Shade(Paint, 1.23), Paint, Shade(Paint, 0.76));
  C.BoxEdge(X + 2, Y + 2, W - 4, B - Y - 4, 5, 3, Shade(Paint, 1.36));
  C.Box(X + W / 2 - 2, Y, 4, B - Y, 0, $34464B);
  OpaqueWindow(C, X + GLASS_INSET, RUN_WINDOW_Y, GLASS_W, GLASS_H, 7);
  OpaqueWindow(C, X + W / 2 + GLASS_INSET, RUN_WINDOW_Y, GLASS_W, GLASS_H, 7);
  C.Box(X + W / 2 - 12, RUN_WINDOW_B + 10, 4, 25, 2, Shade(Paint, 0.51));
  C.Box(X + W / 2 + 8, RUN_WINDOW_B + 10, 4, 25, 2, Shade(Paint, 0.51));
  C.Box(X + 5, B - 11, W - 10, 7, 2, Shade(S.Colors.Body, 0.83));
end;

procedure DrawRunTruckCover(C: TTrainCanvas; X: Single);
const
  Y = RUN_BODY_BOTTOM;
  B = RUN_RAIL_Y + RUN_TRAIN_RISE - 6;
  W = 220;
begin
  C.Polygon([Pt(X, Y), Pt(X + W, Y), Pt(X + W - 8, B - 11),
    Pt(X + W - 24, B), Pt(X + 25, B), Pt(X + 9, B - 11)], $293437);
  C.Panel(X + 13, Y + 15, W - 26, 30, 4, $576460, $3E4B49, $303A3C);
  C.Box(X + 16, Y + 18, W - 32, 4, 1, $6B7670);
  C.Box(X + 35, Y + 28, 38, 11, 2, $2C383B);
  C.Box(X + W - 73, Y + 28, 38, 11, 2, $2C383B);
  C.Line(X + 29, B - 4, X + W - 29, B - 4, 2, $1C292D);
end;

procedure DrawRunUnderframe(C: TTrainCanvas);
const
  Y = RUN_BODY_BOTTOM;
var
  I: Integer;
begin
  C.Panel(RUN_BODY_L + 12, Y - 5, RUN_BODY_R - RUN_BODY_L - 24, 23, 4,
    $59665F, $3F4D4B, $263438);
  DrawRunTruckCover(C, RUN_BODY_L + 134);
  DrawRunTruckCover(C, RUN_BODY_R - 354);
  C.Line(196, Y + 30, 1085, Y + 30, 8, $313E41);
  C.Line(196, Y + 27, 1085, Y + 27, 2, $697873);

  C.Panel(252, Y + 9, 262, 47, 4, $687971, $495654, $303B3D);
  C.BoxEdge(263, Y + 19, 239, 28, 3, 2, $364447);
  for I := 0 to 12 do
  begin
    C.Box(272 + I * 17, Y + 23, 10, 19, 1, $303D41);
    C.Box(272 + I * 17, Y + 23, 2, 19, 0, $7A8880);
  end;
  C.Box(266, Y + 10, 9, 6, 1, $7B8982);
  C.Box(491, Y + 10, 9, 6, 1, $7B8982);

  C.Panel(533, Y + 17, 173, 34, 15, $65746E, $526461, $303E41);
  C.Line(548, Y + 24, 692, Y + 24, 2, $8A978C);
  C.Box(562, Y + 16, 6, 37, 1, $344247);
  C.Box(670, Y + 16, 6, 37, 1, $344247);
  C.Box(697, Y + 31, 17, 6, 1, $42534F);

  C.Panel(726, Y + 10, 176, 49, 4, $64736C, $4F5E59, $313C3F);
  C.BoxEdge(735, Y + 18, 158, 33, 2, 2, $354347);
  C.Line(814, Y + 18, 814, Y + 50, 2, $364347);
  C.Box(747, Y + 30, 17, 4, 1, $9CA99B);
  C.Box(827, Y + 30, 17, 4, 1, $9CA99B);
  C.Panel(928, Y + 10, 112, 36, 3, $69766F, $475753, $303B3F);
  C.Box(937, Y + 20, 31, 11, 2, $364549);
  C.Box(976, Y + 20, 52, 11, 2, $364549);
end;

procedure DrawRunBody(C: TTrainCanvas; const S: TTrainSettings);
var
  Holes: array[0..2] of TD2D1RoundedRect;
  I: Integer;
  X, W, R: Single;
begin
  DrawRunUnderframe(C);
  R := WindowRadius(S.Style);
  for I := Low(Holes) to High(Holes) do
    Holes[I] := D2D1RoundedRect(D2D1RectF(RUN_WINDOW_X[I], RUN_WINDOW_Y,
      RUN_WINDOW_X[I] + RUN_WINDOW_W[I], RUN_WINDOW_B), R, R);
  C.PushCutouts(D2D1RectF(RUN_BODY_L, 109, RUN_BODY_R, RUN_BODY_BOTTOM), Holes);
  try
    C.Panel(RUN_BODY_L + 3, 110, RUN_BODY_R - RUN_BODY_L - 6, 70, 21,
      $AFBDB8, $879896, $4B6069);
    Skin(C, S, RUN_BODY_L, 149, RUN_BODY_R - RUN_BODY_L, RUN_BODY_BOTTOM - 149, 23);
    Livery(C, S, RUN_BODY_L, 534, RUN_BODY_R - RUN_BODY_L, 42);
    DrawRunSideDoor(C, S, RUN_DOOR_LEFT);
    DrawRunSideDoor(C, S, DESIGN_W - RUN_DOOR_LEFT - RUN_DOOR_W);
    C.Line(RUN_BODY_L + 14, 592, RUN_BODY_R - 14, 592, 3, Shade(S.Colors.Body, 0.58), 0.67);
    C.Line(RUN_BODY_L + 17, 614, RUN_BODY_R - 17, 614, 5, $3B4F56, 0.73);
    C.Box(594, 162, 92, 13, 5, $50676D);
    C.Box(613, 166, 54, 4, 2, $BDD4BB);
  finally
    C.PopShapeClip;
  end;
  for I := Low(Holes) to High(Holes) do
  begin
    X := RUN_WINDOW_X[I];
    W := RUN_WINDOW_W[I];
    C.Box(X, RUN_WINDOW_Y, W, RUN_WINDOW_H, R, $7DAEB8, 0.13);
    C.BoxEdge(X, RUN_WINDOW_Y, W, RUN_WINDOW_H, R, 10, $263D49);
    C.BoxEdge(X - 7, RUN_WINDOW_Y - 7, W + 14, RUN_WINDOW_H + 14, R + 7, 3, $A4B3B2, 0.83);
    C.Line(X + R + 8, RUN_WINDOW_Y + 13, X + W - R - 9, RUN_WINDOW_Y + 13, 3, $D8EBE1, 0.41);
    C.Polygon([Pt(X + 34, RUN_WINDOW_Y + 20), Pt(X + 65, RUN_WINDOW_Y + 20),
      Pt(X + 23, RUN_WINDOW_B - 19), Pt(X + 14, RUN_WINDOW_B - 19)], $BFE4E6, 0.17);
    C.Polygon([Pt(X + W - 43, RUN_WINDOW_Y + 20), Pt(X + W - 32, RUN_WINDOW_Y + 20),
      Pt(X + W - 55, RUN_WINDOW_B - 63), Pt(X + W - 64, RUN_WINDOW_B - 63)], $E6F0E1, 0.13);
  end;
end;

end.

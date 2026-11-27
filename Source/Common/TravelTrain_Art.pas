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
  WIDE_WHEEL_RADIUS = 17;
  CAR_WINDOW_Y = 49;
  CAR_WINDOW_H = 59;
  CAR_DOOR_Y = 45;
  CAR_DOOR_H = CAR_DOOR_B - CAR_DOOR_Y;
  CAR_DOOR_W = 78;
  CAR_DOOR_LEAF_W = CAR_DOOR_W / 2 + 0.5;
  CAR_GLASS_W = 23;
  CAR_GLASS_H = 58;
  CAR_GLASS_Y = CAR_DOOR_Y + 7;
  CAR_GLASS_RADIUS = 4;
  CAR_STRIPE_Y = 115;
  CAR_STRIPE_H = 22;
  RUN_CAR_SCALE = 2.8;
  RECLINING_SEAT_W = 200;
  RECLINING_SEAT_H = 270;

  BOARD_T = 148;
  BOARD_B = 653;
  BOARD_H = BOARD_B - BOARD_T;
  BOARD_CAR_SCALE = BOARD_H / CAR_DOOR_H;
  BOARD_W = CAR_DOOR_W * BOARD_CAR_SCALE;
  BOARD_L = (DESIGN_W - BOARD_W) * 0.5;
  BOARD_R = BOARD_L + BOARD_W;
  BOARD_SIDE_X = -55;
  BOARD_SIDE_Y = 172;
  BOARD_SIDE_W = 286;
  BOARD_SIDE_H = 271;
  BOARD_SIDE_RADIUS = 22;

type
  TRailCarEnd = (ceMiddle, ceFront, ceRear);
  TRailCarView = (cvWide, cvSide);
  TTrainSideLayer = (tslCabin, tslBody, tslDoors);
  TRailWindow = record
    X, Width: Single;
  end;
  TRailSideLayout = record
    Windows: array[0..5] of TRailWindow;
    Doors: array[0..2] of Integer;
    WindowCount, DoorCount: Integer;
    ViewCenterX: Single; // 走行・降車の画角中心。窓の寸法とは独立。
  end;

const
  EXPRESS_LEFT_DOOR_X = 126;
  EXPRESS_RIGHT_DOOR_X = 544;
  // 扉際も窓同士と同じ間隔で空け、残りを3枚の窓に等分する。
  EXPRESS_WINDOW_GAP = 16;
  EXPRESS_WINDOW_X = EXPRESS_LEFT_DOOR_X + CAR_DOOR_W + EXPRESS_WINDOW_GAP;
  EXPRESS_WINDOW_W = (EXPRESS_RIGHT_DOOR_X - EXPRESS_LEFT_DOOR_X - CAR_DOOR_W -
    4 * EXPRESS_WINDOW_GAP) / 3;
  EXPRESS_WINDOW_PITCH = EXPRESS_WINDOW_W + EXPRESS_WINDOW_GAP;
  EXPRESS_RIGHT_WINDOW_X = EXPRESS_RIGHT_DOOR_X + CAR_DOOR_W + EXPRESS_WINDOW_GAP;
  EXPRESS_END_WINDOW_X = EXPRESS_RIGHT_WINDOW_X + EXPRESS_WINDOW_PITCH;

  // 最後の窓は中間車にだけある。先頭車・最後尾車では同じ位置が運転台になる。
  COMMUTER_SIDE: TRailSideLayout = (
    Windows: ((X: 167; Width: 63), (X: 246; Width: 63), (X: 431; Width: 121),
      (X: 707; Width: 91), (X: 0; Width: 0), (X: 0; Width: 0));
    Doors: (66, 329, 569); WindowCount: 4; DoorCount: 3; ViewCenterX: 491.5
  );
  EXPRESS_SIDE: TRailSideLayout = (
    Windows: ((X: 25; Width: 77), (X: EXPRESS_WINDOW_X; Width: EXPRESS_WINDOW_W),
      (X: EXPRESS_WINDOW_X + EXPRESS_WINDOW_PITCH; Width: EXPRESS_WINDOW_W),
      (X: EXPRESS_WINDOW_X + 2 * EXPRESS_WINDOW_PITCH; Width: EXPRESS_WINDOW_W),
      (X: EXPRESS_RIGHT_WINDOW_X; Width: EXPRESS_WINDOW_W),
      (X: EXPRESS_END_WINDOW_X; Width: WIDE_CAR_LENGTH - 20 - EXPRESS_END_WINDOW_X));
    Doors: (EXPRESS_LEFT_DOOR_X, EXPRESS_RIGHT_DOOR_X, 0); WindowCount: 6; DoorCount: 2;
    ViewCenterX: 465
  );

function IsCommuter(Style: TTrainStyle): Boolean;
begin
  Result := Style in [trStainless, trPainted];
end;

function RailSide(Style: TTrainStyle): TRailSideLayout;
begin
  if IsCommuter(Style) then Exit(COMMUTER_SIDE);
  Result := EXPRESS_SIDE;
end;

function DoorGlassX(LeafX: Single): Single;
begin
  Result := LeafX + (CAR_DOOR_LEAF_W - CAR_GLASS_W) * 0.5;
end;

function DoorGlassCutout(LeafX: Single): TD2D1RoundedRect;
var
  X: Single;
begin
  X := DoorGlassX(LeafX);
  Result := D2D1RoundedRect(D2D1RectF(X, CAR_GLASS_Y, X + CAR_GLASS_W, CAR_GLASS_Y + CAR_GLASS_H),
    CAR_GLASS_RADIUS, CAR_GLASS_RADIUS);
end;

function CabinSeatColor(const S: TTrainSettings): Cardinal;
begin
  if IsCommuter(S.Style) then Exit(Mix($294B44, S.Colors.Stripe, 0.34));
  Result := Mix($364E96, S.Colors.Stripe, 0.17);
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

procedure DrawRecliningSeat(C: TTrainCanvas; X, Y, Scale: Single; Seat: Cardinal);
var
  Panel, Frame: Cardinal;
  Previous: TD2D1Matrix3x2F;
begin
  Panel := Mix($345D89, Seat, 0.28);
  Frame := Shade(Panel, 0.55);
  Previous := C.ApplyTransform(TD2D1Matrix3x2F.Scale(Scale, Scale, Pt(0, 0)) *
    TD2D1Matrix3x2F.Translation(X, Y));
  try
    C.Oval(128, 267, 67, 3, $26343A, 0.23);
    // 奥側の背もたれと、座面の奥行き。
    C.Polygon([Pt(34, 24), Pt(43, 8), Pt(78, 8), Pt(89, 22), Pt(99, 72),
      Pt(119, 128), Pt(107, 148), Pt(69, 147), Pt(44, 91)], Shade(Seat, 0.74));
    C.Polygon([Pt(48, 11), Pt(76, 11), Pt(84, 24), Pt(90, 51), Pt(59, 57)], $C88FA2);
    C.GradientPolygon([Pt(93, 125), Pt(179, 119), Pt(190, 130), Pt(198, 180),
      Pt(188, 208), Pt(70, 208), Pt(51, 173)], Pt(93, 124), Pt(125, 203),
      Shade(Seat, 1.12), Seat, Shade(Seat, 0.72));
    // 手前の背もたれの側面と、座面へ向かう傾斜。
    C.Polygon([Pt(3, 21), Pt(9, 7), Pt(40, 0), Pt(54, 9), Pt(60, 73),
      Pt(79, 118), Pt(111, 155), Pt(100, 179), Pt(59, 212), Pt(35, 184),
      Pt(15, 138), Pt(4, 88)], Shade(Seat, 0.88));
    C.Polygon([Pt(17, 18), Pt(41, 4), Pt(54, 9), Pt(60, 73), Pt(79, 118),
      Pt(111, 155), Pt(99, 172), Pt(71, 159), Pt(46, 129), Pt(23, 77)], Shade(Seat, 1.24));
    C.Polygon([Pt(17, 15), Pt(42, 3), Pt(54, 9), Pt(58, 52), Pt(31, 65), Pt(23, 55)], $DFA4AF);
    // 肘掛けから足元まで続く手前の側板。
    C.GradientPolygon([Pt(58, 181), Pt(194, 181), Pt(198, 190), Pt(198, 239),
      Pt(169, 266), Pt(92, 266), Pt(58, 239)], Pt(128, 181), Pt(128, 266),
      Shade(Panel, 1.23), Panel, Shade(Panel, 0.76));
    C.StrokePath([Pt(61, 182), Pt(69, 169), Pt(87, 154), Pt(153, 154),
      Pt(177, 164), Pt(192, 182)], 7, Frame);
    C.Line(88, 154, 152, 154, 5, $9CBABC);
    C.Line(63, 184, 193, 184, 3, Shade(Panel, 1.47));
  finally
    C.RestoreTransform(Previous);
  end;
end;

procedure DrawRecliningSeatPair(C: TTrainCanvas; X, Y, Pitch, Scale: Single; Seat: Cardinal);
begin
  DrawRecliningSeat(C, X, Y, Scale, Seat);
  DrawRecliningSeat(C, X + Pitch, Y, Scale, Seat);
end;

procedure DrawTiedCurtain(C: TTrainCanvas; X, Y, W, H: Single);
var
  I: Integer;
begin
  C.GradientPolygon([Pt(X, Y), Pt(X + W, Y), Pt(X + W * 0.75, Y + H * 0.26),
    Pt(X + W * 0.45, Y + H * 0.55), Pt(X + W * 0.62, Y + H * 0.78),
    Pt(X + W * 0.78, Y + H), Pt(X, Y + H)], Pt(X, Y), Pt(X + W, Y + H),
    $D3C6A1, $A39372, $685E4C);
  for I := 1 to 3 do
    C.StrokePath([Pt(X + W * (I * 0.22), Y + H * 0.035),
      Pt(X + W * (I * 0.115), Y + H * 0.55),
      Pt(X + W * (I * 0.18), Y + H * 0.96)], Max(0.55, W * 0.037),
      Shade($AA997B, 0.68 + I * 0.12));
  C.Line(X, Y + H * 0.55, X + W * 0.47, Y + H * 0.55, Max(1.0, W * 0.095), $E0CF9E);
end;

procedure DrawWindowCurtains(C: TTrainCanvas; X, Y, W, H, CurtainW: Single);
var
  Previous: TD2D1Matrix3x2F;
begin
  DrawTiedCurtain(C, X, Y, CurtainW, H);
  Previous := C.ApplyTransform(TD2D1Matrix3x2F.Scale(-1, 1, Pt(X + W * 0.5, 0)));
  try
    DrawTiedCurtain(C, X, Y, CurtainW, H);
  finally
    C.RestoreTransform(Previous);
  end;
end;

procedure DrawLuggageRack(C: TTrainCanvas; X, Y, W, H: Single);
var
  Lip, Trim: Single;
begin
  Lip := H * 0.31;
  Trim := Max(0.55, H * 0.075);
  C.Box(X, Y, W, H - Lip, 0, $AAB8B4);
  C.Box(X, Y, W, Trim, 0, $CFD8D0);
  C.Box(X, Y + H - Lip, W, Lip, 0, $5D7473);
  C.Box(X, Y + H - Lip, W, Trim, 0, $D6DED3);
end;

procedure DrawExpressSeatRows(C: TTrainCanvas; Left, Right: Single; Seat: Cardinal);
const
  SCALE = 0.235;
  SEAT_WIDTH = RECLINING_SEAT_W * SCALE;
  SEAT_PITCH = 62;
  SEAT_TOP = 80;
  DOOR_CLEARANCE = 16;
  FIRST_SEAT_X = 18;
  LAST_SEAT_LIMIT = WIDE_CAR_LENGTH - 8;

  procedure DrawRow(StartX, EndX: Single);
  var
    X: Single;
  begin
    X := StartX;
    while X + SEAT_WIDTH <= EndX do
    begin
      if (X < Right) and (X + SEAT_WIDTH > Left) then
        DrawRecliningSeat(C, X, SEAT_TOP, SCALE, Seat);
      X := X + SEAT_PITCH;
    end;
  end;

begin
  // 車内座標で座席を並べ、扉前は空ける。窓の幅は座席の座標にも寸法にも使わない。
  DrawRow(FIRST_SEAT_X, EXPRESS_LEFT_DOOR_X - DOOR_CLEARANCE);
  DrawRow(EXPRESS_LEFT_DOOR_X + CAR_DOOR_W + DOOR_CLEARANCE,
    EXPRESS_RIGHT_DOOR_X - DOOR_CLEARANCE);
  DrawRow(EXPRESS_RIGHT_DOOR_X + CAR_DOOR_W + DOOR_CLEARANCE, LAST_SEAT_LIMIT);
end;

procedure DrawExpressWindow(C: TTrainCanvas; X, Y, W, H: Single; Seat: Cardinal);
begin
  C.PushClip(X + 2, Y + 2, W - 4, H - 4);
  try
    C.Box(X + 2, Y + H * 0.72, W - 4, H * 0.28, 0, $A7AC9E);
    C.Box(X + 2, Y + H * 0.71, W - 4, 1.7, 0, $D2D7BF);
    DrawWindowCurtains(C, X + 3, Y + 4, W - 6, H - 7, Min(13.0, W * 0.18));
    DrawLuggageRack(C, X + 4, Y + 3, W - 8, H * 0.105);
    DrawExpressSeatRows(C, X + 2, X + W - 2, Seat);
  finally
    C.PopClip;
  end;
end;

procedure DrawClearCarGlass(C: TTrainCanvas; X, Y, W, H, Radius: Single);
var
  OuterRadius: Single;
begin
  OuterRadius := 0;
  if Radius > 0 then OuterRadius := Radius + 2.4;
  C.Box(X, Y, W, H, Radius, $7DAEB8, 0.13);
  C.BoxEdge(X, Y, W, H, Radius, 3.4, $263D49);
  C.BoxEdge(X - 2.4, Y - 2.4, W + 4.8, H + 4.8, OuterRadius, 1.2, $A4B3B2, 0.83);
  C.Line(X + Radius + 4, Y + 4.5, X + W - Radius - 4, Y + 4.5, 1.2, $D8EBE1, 0.41);
  C.Polygon([Pt(X + W * 0.15, Y + 6), Pt(X + W * 0.29, Y + 6),
    Pt(X + W * 0.1, Y + H - 6), Pt(X + W * 0.06, Y + H - 6)], $BFE4E6, 0.17);
end;

procedure DrawExteriorDoorLeaf(C: TTrainCanvas; const S: TTrainSettings; X: Single;
  Left, TransparentGlass: Boolean);
const
  W = CAR_DOOR_LEAF_W;
var
  Edge, Paint: Cardinal;
  GlassX, Seam: Single;
  procedure DrawPanel;
  begin
    C.Panel(X, CAR_DOOR_Y, W, CAR_DOOR_H, 0, Shade(Paint, 1.25), Paint, Shade(Paint, 0.78));
    Livery(C, S, X, CAR_STRIPE_Y, W, CAR_STRIPE_H);
    C.Box(X + 2, CAR_DOOR_B - 8, W - 4, 5, 1, Shade(Paint, 0.74));
    C.Box(Seam, CAR_DOOR_Y, 1.8, CAR_DOOR_H, 0, Edge);
  end;
begin
  Paint := Mix(S.Colors.Body, S.Colors.Stripe, 0.12);
  Edge := Shade(S.Colors.Body, 0.55);
  GlassX := DoorGlassX(X);
  Seam := X;
  if Left then Seam := X + W - 1.8;
  if TransparentGlass then
  begin
    C.PushCutouts(D2D1RectF(X, CAR_DOOR_Y, X + W, CAR_DOOR_B), [DoorGlassCutout(X)]);
    try
      DrawPanel;
    finally
      C.PopShapeClip;
    end;
  end
  else
  begin
    DrawPanel;
    C.Panel(GlassX, CAR_GLASS_Y, CAR_GLASS_W, CAR_GLASS_H, CAR_GLASS_RADIUS, $4D6D7A, $365560, $21353F);
  end;
  DrawClearCarGlass(C, GlassX, CAR_GLASS_Y, CAR_GLASS_W, CAR_GLASS_H, CAR_GLASS_RADIUS);
  C.BoxEdge(X + 1, CAR_DOOR_Y + 1, W - 2, CAR_DOOR_H - 2, 0, 1, Edge, 0.65);
end;

procedure DrawExteriorDoor(C: TTrainCanvas; const S: TTrainSettings; X, Opening: Single;
  TransparentGlass: Boolean);
var
  Stroke: Single;
begin
  if Opening >= 1 then Exit;
  Stroke := Opening * (CAR_DOOR_W * 0.5 + 0.5);
  C.PushClip(X, CAR_DOOR_Y, CAR_DOOR_W, CAR_DOOR_H);
  try
    DrawExteriorDoorLeaf(C, S, X - Stroke, True, TransparentGlass);
    DrawExteriorDoorLeaf(C, S, X + CAR_DOOR_W * 0.5 + Stroke, False, TransparentGlass);
  finally
    C.PopClip;
  end;
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

procedure DrawRailTruckCover(C: TTrainCanvas; Center: Single);
const
  Y = WIDE_BODY_H;
  B = Y + (RUN_RAIL_Y - RUN_BODY_BOTTOM + RUN_TRAIN_RISE - 6) / RUN_CAR_SCALE;
begin
  C.Polygon([Pt(Center - 62, Y), Pt(Center + 62, Y), Pt(Center + 58, B - 5),
    Pt(Center + 47, B), Pt(Center - 48, B), Pt(Center - 58, B - 5)], $293437);
  C.Panel(Center - 54, Y + 8, 108, 15, 2, $576460, $3E4B49, $303A3C);
  C.Box(Center - 52, Y + 9, 104, 2, 0.6, $6B7670);
  C.Box(Center - 42, Y + 14, 24, 6, 1, $2C383B);
  C.Box(Center + 18, Y + 14, 24, 6, 1, $2C383B);
  C.Line(Center - 45, B - 3, Center + 45, B - 3, 1, $1C292D);
end;

procedure DrawUnderframe(C: TTrainCanvas; CarEnd: TRailCarEnd; BodyColor: Cardinal;
  ShowWheels: Boolean);
const
  Y = WIDE_BODY_H;
  W = WIDE_CAR_LENGTH;
var
  I: Integer;
begin
  C.Box(16, Y - 5, W - 32, 12, 3, $36444A);
  C.Box(23, Y + 4, W - 46, 4, 1, $67746E);
  if ShowWheels then
  begin
    DrawBogie(C, 157);
    DrawBogie(C, W - 157);
  end
  else
  begin
    DrawRailTruckCover(C, 157);
    DrawRailTruckCover(C, W - 157);
  end;
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

procedure DrawRailCar(C: TTrainCanvas; const S: TTrainSettings; CarEnd: TRailCarEnd;
  View: TRailCarView);
const
  W = WIDE_CAR_LENGTH;
  H = WIDE_BODY_H;
var
  Radius, CabRadius, CabDividerX, CabGlassX, Crown, Shoulder, Face: Single;
  I, WindowCount, DoorX: Integer;
  BodyOutline: array[0..8] of TD2D1Point2F;
  Cutouts: TArray<TD2D1RoundedRect>;
  Side: TRailSideLayout;
  Bounds: TD2D1RectF;
  Light, GlowColor: Cardinal;

  procedure DrawSkin;
  begin
    Skin(C, S, 0, 0, W, H, 0);
    C.Panel(0, 0, W, 25, 0, $617679, $B2BEBA, Shade(S.Colors.Body, 0.85));
    C.Line(17, 23, W - 6, 23, 2.5, Shade(S.Colors.Body, 1.38));
    Livery(C, S, 0, CAR_STRIPE_Y, W, CAR_STRIPE_H);
    C.Box(0, H - 12, W, 6, 0, Shade(S.Colors.Body, 0.64), 0.70);
  end;

begin
  Side := RailSide(S.Style);
  Radius := 12 * 0.49;
  CabRadius := Radius;
  CabDividerX := W - 118;
  if not IsCommuter(S.Style) then
  begin
    Radius := 0;
    CabRadius := 20 * 0.49;
    CabDividerX := EXPRESS_RIGHT_WINDOW_X + EXPRESS_WINDOW_W + 6;
  end;
  WindowCount := Side.WindowCount;
  if CarEnd <> ceMiddle then Dec(WindowCount);
  DrawUnderframe(C, CarEnd, S.Colors.Body, View = cvWide);
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
  Bounds := D2D1RectF(0, 0, W, H);
  if View <> cvWide then
  begin
    SetLength(Cutouts, WindowCount + Side.DoorCount);
    for I := 0 to WindowCount - 1 do
      Cutouts[I] := D2D1RoundedRect(D2D1RectF(Side.Windows[I].X, CAR_WINDOW_Y,
        Side.Windows[I].X + Side.Windows[I].Width, CAR_WINDOW_Y + CAR_WINDOW_H), Radius, Radius);
    for I := 0 to Side.DoorCount - 1 do
    begin
      DoorX := Side.Doors[I];
      Cutouts[WindowCount + I] := D2D1RoundedRect(D2D1RectF(DoorX, CAR_DOOR_Y,
        DoorX + CAR_DOOR_W, CAR_DOOR_B), 0, 0);
    end;
  end;
  C.PushShapeClip(Bounds, BodyOutline);
  try
    if Length(Cutouts) > 0 then
    begin
      C.PushCutouts(Bounds, Cutouts);
      try
        DrawSkin;
      finally
        C.PopShapeClip;
      end;
    end
    else DrawSkin;

    for I := 0 to Side.DoorCount - 1 do
    begin
      DoorX := Side.Doors[I];
      if View = cvWide then DrawExteriorDoor(C, S, DoorX, 0, False);
      C.BoxEdge(DoorX - 1.2, CAR_DOOR_Y - 1.2, CAR_DOOR_W + 2.4, CAR_DOOR_H + 2.4,
        2.4, 2.2, Shade(S.Colors.Body, 0.53));
      C.Box(DoorX + 3, CAR_DOOR_SILL_Y, CAR_DOOR_W - 6, CAR_DOOR_SILL_H, 1, $718080);
    end;

    for I := 0 to WindowCount - 1 do
    begin
      if View = cvWide then
      begin
        C.Panel(Side.Windows[I].X, CAR_WINDOW_Y, Side.Windows[I].Width, CAR_WINDOW_H, Radius,
          $4D6D7A, $365560, $21353F);
        if not IsCommuter(S.Style) then
        begin
          DrawExpressWindow(C, Side.Windows[I].X, CAR_WINDOW_Y, Side.Windows[I].Width,
            CAR_WINDOW_H, CabinSeatColor(S));
          C.Box(Side.Windows[I].X, CAR_WINDOW_Y, Side.Windows[I].Width, CAR_WINDOW_H,
            Radius, $233947, 0.41);
        end;
      end;
      DrawClearCarGlass(C, Side.Windows[I].X, CAR_WINDOW_Y, Side.Windows[I].Width, CAR_WINDOW_H, Radius);
    end;

    if CarEnd <> ceMiddle then
    begin
      C.Line(CabDividerX, 34, CabDividerX, H - 12, 2, Shade(S.Colors.Body, 0.61));
      if S.Style = trStreamlined then
      begin
        CabGlassX := W - 81;
        C.Polygon([Pt(CabGlassX, 38), Pt(CabGlassX + 23, 38), Pt(CabGlassX + 40, 55),
          Pt(CabGlassX + 40, 108), Pt(CabGlassX + 5, 108)], $23343F);
        C.GradientPolygon([Pt(CabGlassX + 5, 43), Pt(CabGlassX + 20, 43), Pt(CabGlassX + 35, 57),
          Pt(CabGlassX + 35, 103), Pt(CabGlassX + 10, 103)], Pt(CabGlassX + 4, 43),
          Pt(CabGlassX + 29, 103), $4D6D7A, $365560, $21353F);
        C.Polygon([Pt(CabGlassX + 9, 47), Pt(CabGlassX + 19, 47), Pt(CabGlassX + 16, 96),
          Pt(CabGlassX + 12, 96)], $9DBEC0, 0.42);
      end
      else
        OpaqueWindow(C, W - 78, 35, 30, 74, CabRadius);
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

procedure DrawRailCoupling(C: TTrainCanvas; X, Y: Single);
begin
  C.Box(X - 10, Y + 27, 20, WIDE_BODY_H - 36, 2, $2F3A3E);
  C.Line(X, Y + 34, X, Y + WIDE_BODY_H - 14, 2, $65716E);
  C.Box(X - 15, Y + WIDE_BODY_H + 3, 30, 10, 2, $29363E);
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
      DrawRailCoupling(C, JoinX, Y);
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
        DrawRailCar(C, S, CarEnd, cvWide);
      finally
        C.RestoreTransform(Previous);
      end;
    end;
  finally
    C.RestoreTransform(View);
  end;
end;

function ApplyTrainSideView(C: TTrainCanvas; const S: TTrainSettings;
  const Side: TRailSideLayout): TD2D1Matrix3x2F;
const
  Y = RUN_BODY_BOTTOM - WIDE_BODY_H * RUN_CAR_SCALE;
var
  Zoom: Single;
begin
  Zoom := S.Tracks[ttZoom] / 100;
  Result := C.ApplyTransform(TD2D1Matrix3x2F.Scale(RUN_CAR_SCALE, RUN_CAR_SCALE, Pt(0, 0)) *
    TD2D1Matrix3x2F.Translation(DESIGN_W * 0.5 - Side.ViewCenterX * RUN_CAR_SCALE, Y - RUN_TRAIN_RISE) *
    TD2D1Matrix3x2F.Scale(Zoom, Zoom, Pt(DESIGN_W * 0.5, DESIGN_H * 0.5)));
end;

procedure BoardDoorLeaf(C: TTrainCanvas; const S: TTrainSettings; X: Single; Left: Boolean);
const
  W = BOARD_W / 2 + 1;
  GLASS_Y = BOARD_T + (CAR_GLASS_Y - CAR_DOOR_Y) * BOARD_CAR_SCALE;
  GLASS_W = CAR_GLASS_W * BOARD_CAR_SCALE;
  GLASS_H = CAR_GLASS_H * BOARD_CAR_SCALE;
  GLASS_RADIUS = CAR_GLASS_RADIUS * BOARD_CAR_SCALE;
var
  GlassX, Seam, OuterEdge: Single;
  Paint: Cardinal;
begin
  GlassX := X + (W - GLASS_W) * 0.5;
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
  if IsCommuter(S.Style) then
    C.Box(GlassX + 19, GLASS_Y + 14, 24, GLASS_H - 32, 1, $E0F6F1, 0.20)
  else
    C.Polygon([Pt(GlassX + 25, GLASS_Y + 14), Pt(GlassX + 49, GLASS_Y + 14),
      Pt(GlassX + 26, GLASS_Y + GLASS_H - 18), Pt(GlassX + 13, GLASS_Y + GLASS_H - 32)],
      $E0F6F1, 0.20);
  C.Box(GlassX + GLASS_W - 25, GLASS_Y + GLASS_H - 31, 12, 17, 3, $E2EBD4, 0.78);
end;

procedure DrawBoardFloor(C: TTrainCanvas);
var
  X, Y: Integer;
begin
  C.Panel(0, BOARD_B, DESIGN_W, DESIGN_H - BOARD_B, 0, $647173, $39474C, $26343A);
  C.Box(BOARD_L - 12, BOARD_B + 8, BOARD_W + 24, DESIGN_H - BOARD_B - 13, 0, $8D9A98, 0.68);
  C.Metal(BOARD_L - 9, BOARD_B, BOARD_W + 18, 15, 2, $B3BCB4);
  C.Box(BOARD_L - 9, BOARD_B + 9, BOARD_W + 18, 4, 0, $EBC469);
  C.Line(0, BOARD_B + 24, BOARD_L - 45, BOARD_B + 24, 1.5, $6F8182, 0.75);
  C.Line(BOARD_R + 45, BOARD_B + 24, DESIGN_W, BOARD_B + 24, 1.5, $6F8182, 0.75);
  for Y := 0 to 7 do
    for X := -18 to 18 do
      C.Box(DESIGN_W / 2 + X * 9, BOARD_B + 20 + Y * 5, 2.7, 1.6, 0.5, $3B4A4D, 0.65);
end;

procedure DrawBoardSideGlass(C: TTrainCanvas; VerticalReflection: Boolean);
begin
  // 側窓は後ろのホームが透ける。片側の形を反転し、反対側にも同じ構造を描く。
  C.Box(BOARD_SIDE_X, BOARD_SIDE_Y, BOARD_SIDE_W, BOARD_SIDE_H, BOARD_SIDE_RADIUS, $8BBFC5, 0.14);
  C.BoxEdge(BOARD_SIDE_X, BOARD_SIDE_Y, BOARD_SIDE_W, BOARD_SIDE_H, BOARD_SIDE_RADIUS, 12, $334348);
  C.BoxEdge(BOARD_SIDE_X - 8, BOARD_SIDE_Y - 8, BOARD_SIDE_W + 16, BOARD_SIDE_H + 16,
    BOARD_SIDE_RADIUS + 8, 4, $A3B0AC);
  C.BoxEdge(BOARD_SIDE_X + 6, BOARD_SIDE_Y + 6, BOARD_SIDE_W - 12, BOARD_SIDE_H - 12,
    BOARD_SIDE_RADIUS - 6, 2, $C5D6D0, 0.78);
  if VerticalReflection then
  begin
    C.Box(29, BOARD_SIDE_Y + 13, 40, BOARD_SIDE_H - 26, 1, $DFEFEA, 0.19);
    C.Box(80, BOARD_SIDE_Y + 13, 8, BOARD_SIDE_H - 26, 1, $DFEFEA, 0.10);
  end
  else
    C.Polygon([Pt(47, BOARD_SIDE_Y + 13), Pt(94, BOARD_SIDE_Y + 13),
      Pt(33, BOARD_SIDE_Y + BOARD_SIDE_H - 13), Pt(10, BOARD_SIDE_Y + BOARD_SIDE_H - 21)],
      $DFEFEA, 0.19);
  C.Line(3, BOARD_SIDE_Y + BOARD_SIDE_H + 7, 240, BOARD_SIDE_Y + BOARD_SIDE_H + 7,
    4, $E0E5DA);
end;

procedure DrawBoardSide(C: TTrainCanvas; Seat: Cardinal);
const
  PARTITION_X = 358;
  PARTITION_TOP = 350;
  PARTITION_W = 44;
  PARTITION_H = BOARD_B - 5 - PARTITION_TOP;
  POLE_X = 225;
  HANDLE_X = 429;
begin
  DrawBoardSideGlass(C, True);
  C.Panel(269, 221, 132, 96, 4, $DCE2DD, $A2B4AC, $819790);
  C.BoxEdge(269, 221, 132, 96, 4, 3, $7F908A);
  C.Box(279, 233, 111, 72, 2, $A7B8AF);
  C.Box(287, 236, 25, 64, 1, $D9E3D7, 0.54);
  C.Box(328, 250, 49, 4, 1, $D4DFD5);
  C.Box(328, 262, 35, 3, 1, $D4DFD5);

  // ロングシートと足元の金属板。
  C.Metal(-16, 600, 384, 50, 4, $869592);
  C.Panel(-22, 444, 385, 131, 18, Shade(Seat, 1.27), Seat, Shade(Seat, 0.51));
  C.Line(0, 453, 310, 453, 2, Shade(Seat, 1.19));
  C.Line(111, 460, 111, 558, 2, Shade(Seat, 0.72));
  C.Line(228, 460, 228, 558, 2, Shade(Seat, 0.72));
  C.Panel(-23, 553, 387, 79, 21, Shade(Seat, 1.38), Seat, Shade(Seat, 0.58));
  C.Line(0, 614, 290, 614, 2, Shade(Seat, 0.63));
  // 細長い袖仕切りと、取付部まで同じ位置で伸びる手すり。
  C.Box(PARTITION_X, PARTITION_TOP, PARTITION_W, PARTITION_H, 0, $344248);
  C.Panel(PARTITION_X + 5, PARTITION_TOP + 5, PARTITION_W - 10, PARTITION_H - 10,
    0, $F2F0E4, $D3DCD7, $A6B2AC);
  C.Box(PARTITION_X + 7, PARTITION_TOP + 7, 2, PARTITION_H - 14, 0, $EBEDE4);

  C.Box(POLE_X, BOARD_T, 16, BOARD_H, 0, $607675);
  C.Box(POLE_X + 3, BOARD_T + 8, 10, BOARD_H - 16, 0, $C4D0CB);
  C.Box(POLE_X + 1, BOARD_T + 15, 14, 328, 0, $C99440);
  C.Box(POLE_X + 3, BOARD_T + 15, 3, 328, 0, $F9CA6E);

  C.Box(HANDLE_X, 329, 12, 172, 0, $A6783D);
  C.Box(HANDLE_X + 2, 333, 8, 164, 0, $E0AC53);
  C.Box(HANDLE_X + 3, 333, 2, 164, 0, $FFD57C);
end;

procedure DrawBoardExpressSide(C: TTrainCanvas);
begin
  DrawBoardSideGlass(C, False);
  C.PushClip(BOARD_SIDE_X + 7, BOARD_SIDE_Y + 6, BOARD_SIDE_W - 14, BOARD_SIDE_H - 12);
  try
    DrawWindowCurtains(C, BOARD_SIDE_X + 8, BOARD_SIDE_Y + 8,
      BOARD_SIDE_W - 16, BOARD_SIDE_H - 16, 59);
  finally
    C.PopClip;
  end;
  DrawLuggageRack(C, -22, 100, 418, 36);
  C.Line(67, 93, 67, 104, 3.5, $81918E);
  C.Line(315, 93, 315, 104, 3.5, $81918E);
  C.Metal(-14, BOARD_B - 24, 398, 23, 3, $919D98);
  C.StrokePath([Pt(BOARD_L - 38, 341), Pt(BOARD_L - 35, 352),
    Pt(BOARD_L - 35, 456), Pt(BOARD_L - 38, 467)], 8, $7A8C89);
  C.Line(BOARD_L - 36, 359, BOARD_L - 36, 452, 2.2, $E4E5D9);
end;

procedure DrawBoardDisplays(C: TTrainCanvas; Stripe: Cardinal);
var
  I: Integer;
begin
  C.Panel(BOARD_L - 26, 27, BOARD_W + 52, BOARD_T - 30, 8, $5F6F70, $414F53, $2C3B40);
  C.Box(BOARD_L - 7, 48, 155, 70, 5, $162B33);
  C.Box(BOARD_L - 2, 54, 145, 57, 3, $E5ECE3);
  C.Box(BOARD_L - 2, 54, 145, 14, 2, Mix($3B716F, Stripe, 0.40));
  C.Box(BOARD_L + 14, 76, 67, 4, 1.5, $53747B);
  C.Box(BOARD_L + 14, 93, 118, 2, 1, $A0B7B1);
  for I := 0 to 4 do
  begin
    C.Oval(BOARD_L + 17 + I * 27, 94, 3.5, 3.5, $4E7772);
    C.Oval(BOARD_L + 17 + I * 27, 94, 1.8, 1.8, $DAE9DD);
  end;
  C.Box(BOARD_R - 148, 48, 155, 70, 5, $172C35);
  C.Panel(BOARD_R - 143, 53, 145, 59, 3, $769CA7, $456878, $35585E);
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
const
  SEAT_SCALE = 1.26;
  SEAT_SPACING = 68;
  DOOR_CLEARANCE = 46;
  SEAT_WIDTH = RECLINING_SEAT_W * SEAT_SCALE;
  SEAT_PITCH = SEAT_WIDTH + SEAT_SPACING;
  SEAT_TOP = DESIGN_H - 22 - RECLINING_SEAT_H * SEAT_SCALE;
var
  Seat, Wall: Cardinal;
  Holes: array[0..2] of TD2D1RoundedRect;
  Previous: TD2D1Matrix3x2F;
  Commuter: Boolean;
  procedure DrawSide;
  begin
    if Commuter then DrawBoardSide(C, Seat)
    else DrawBoardExpressSide(C);
  end;
begin
  Commuter := IsCommuter(S.Style);
  Seat := CabinSeatColor(S);
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
  DrawSide;
  Previous := C.ApplyTransform(TD2D1Matrix3x2F.Scale(-1, 1, Pt(DESIGN_W / 2, 0)));
  try
    DrawSide;
  finally
    C.RestoreTransform(Previous);
  end;
  C.Box(BOARD_L - 14, BOARD_T, 14, BOARD_H, 1, $475956);
  C.Box(BOARD_R, BOARD_T, 14, BOARD_H, 1, $475956);
  C.Box(BOARD_L - 10, BOARD_T, 6, BOARD_H - 43, 1, $E2B65D);
  C.Box(BOARD_R + 4, BOARD_T, 6, BOARD_H - 43, 1, $E2B65D);
  C.Line(BOARD_L - 16, BOARD_T + 1, BOARD_R + 16, BOARD_T + 1, 5, $304348);
  if Commuter then
  begin
    DrawBoardDisplays(C, S.Colors.Stripe);
    DrawBoardStraps(C);
  end
  else
  begin
    C.Box(BOARD_L + 37, 66, BOARD_W - 74, 6, 3, $FAF2D8);
    DrawRecliningSeatPair(C, BOARD_L - DOOR_CLEARANCE - SEAT_WIDTH - SEAT_PITCH,
      SEAT_TOP, SEAT_PITCH, SEAT_SCALE, Seat);
    DrawRecliningSeatPair(C, BOARD_R + DOOR_CLEARANCE, SEAT_TOP, SEAT_PITCH, SEAT_SCALE, Seat);
  end;
end;


procedure DrawCarDoorInterior(C: TTrainCanvas; DoorX: Single; Reclining: Boolean);
var
  Leaf: Integer;
  X: Single;
begin
  for Leaf := 0 to 1 do
  begin
    X := DoorGlassX(DoorX + Leaf * CAR_DOOR_W * 0.5);
    C.PushClip(X + 1, CAR_GLASS_Y + 1, CAR_GLASS_W - 2, CAR_GLASS_H - 2);
    try
      C.Box(X, CAR_GLASS_Y, CAR_GLASS_W, 8, 0, $C3CBC0);
      C.Box(X + 4, CAR_GLASS_Y + 3, CAR_GLASS_W - 8, 1.5, 0.5, $FFF1C5);
      C.Panel(X, CAR_GLASS_Y + 44, CAR_GLASS_W, 17, 0, $94AAA1, $6E8A83, $476563);
      if Reclining then DrawTiedCurtain(C, X + 1, CAR_GLASS_Y + 1, 7, CAR_GLASS_H - 3)
      else
      begin
        C.Line(X + 4, CAR_GLASS_Y + 9, X + 4, CAR_GLASS_Y + 54, 1.8, $C99A4F);
        C.Line(X + 3.7, CAR_GLASS_Y + 9, X + 3.7, CAR_GLASS_Y + 54, 0.7, $F3D28C);
      end;
      C.Line(X + 7, CAR_GLASS_Y + 44, X + CAR_GLASS_W - 2, CAR_GLASS_Y + 44, 1.3, $B9C8B7);
    finally
      C.PopClip;
    end;
  end;
end;

procedure DrawCarDoorway(C: TTrainCanvas; DoorX: Single; Seat: Cardinal; Reclining: Boolean);
const
  B = CAR_DOOR_B;
var
  R: Single;
begin
  R := DoorX + CAR_DOOR_W;
  // 開いたときにだけ見える床・腰板を扉窓の外に描く。閉扉時の窓は走行と同じ車内を映す。
  C.PushCutouts(D2D1RectF(DoorX, CAR_DOOR_Y, R, B),
    [DoorGlassCutout(DoorX), DoorGlassCutout(DoorX + CAR_DOOR_W * 0.5)]);
  try
    C.Panel(DoorX, CAR_DOOR_Y, CAR_DOOR_W, CAR_DOOR_H, 0, $B9B39B, $BAC8B6, $557475);
    C.Box(DoorX + 7, CAR_DOOR_Y + 3, CAR_DOOR_W - 14, 2, 0.5, $FFF0C3);
    if Reclining then
    begin
      DrawLuggageRack(C, DoorX + 4, CAR_DOOR_Y + 1, CAR_DOOR_W - 8, 5.5);
      C.Box(DoorX, B - 32, CAR_DOOR_W, 32, 0, $617F81);
      C.Line(DoorX + 22, B - 2, DoorX + 22, B - 31, 0.8, $A8B7AA);
      C.Line(R - 22, B - 2, R - 22, B - 31, 0.8, $A8B7AA);
    end
    else
    begin
      C.Panel(DoorX + 2, B - 57, 17, 34, 3, Shade(Seat, 1.23), Seat, Shade(Seat, 0.70));
      C.Panel(R - 19, B - 57, 17, 34, 3, Shade(Seat, 1.23), Seat, Shade(Seat, 0.70));
      C.Polygon([Pt(DoorX, B), Pt(R, B), Pt(R - 13, B - 32), Pt(DoorX + 13, B - 32)], $617F81);
      C.Line(DoorX + 19, B - 2, DoorX + 26, B - 31, 0.8, $A8B7AA);
      C.Line(R - 19, B - 2, R - 26, B - 31, 0.8, $A8B7AA);
    end;
    C.Box(DoorX + 1, B - 2, CAR_DOOR_W - 2, 1, 0, $D3C08A);
  finally
    C.PopShapeClip;
  end;
end;

procedure DrawRunCarInterior(C: TTrainCanvas; const S: TTrainSettings;
  const Side: TRailSideLayout);
const
  TOP = CAR_WINDOW_Y;
  BOTTOM = TOP + CAR_WINDOW_H;
var
  I: Integer;
  X, W, SeatW: Single;
  Seat: Cardinal;
  Reclining: Boolean;
begin
  Seat := CabinSeatColor(S);
  Reclining := not IsCommuter(S.Style);
  for I := 0 to Side.WindowCount - 1 do
  begin
    X := Side.Windows[I].X;
    W := Side.Windows[I].Width;
    if Reclining then
    begin
      DrawExpressWindow(C, X, TOP, W, CAR_WINDOW_H, Seat);
      Continue;
    end;
    SeatW := W * 0.23;
    C.PushClip(X + 2, TOP + 2, W - 4, CAR_WINDOW_H - 4);
    try
      C.Box(X + 2, TOP + 1, W - 4, 7, 1, $AAB3A7);
      C.Box(X + 7, TOP + 3, W - 14, 1.6, 0.5, $FFF1C2, 0.81);
      C.Box(X + 1, BOTTOM - 23, W - 2, 23, 2, $7D9691);
      C.Box(X + 1, BOTTOM - 23, W - 2, 1.8, 0.5, $C5CEB4);
      C.Panel(X + 4, BOTTOM - 15, W - 8, 18, 4, Shade(Seat, 1.27), Seat, Shade(Seat, 0.64));
      C.Panel(X + 5, BOTTOM - 26, SeatW, 28, 4, Shade(Seat, 1.16), Seat, Shade(Seat, 0.68));
      C.Panel(X + W - SeatW - 5, BOTTOM - 26, SeatW, 28, 4,
        Shade(Seat, 1.16), Seat, Shade(Seat, 0.68));
      C.Box(X + 8, BOTTOM - 23, SeatW - 6, 1.2, 0.5, Shade(Seat, 1.38), 0.75);
      C.Box(X + W - SeatW - 2, BOTTOM - 23, SeatW - 6, 1.2, 0.5, Shade(Seat, 1.38), 0.75);
    finally
      C.PopClip;
    end;
  end;
  for I := 0 to Side.DoorCount - 1 do
  begin
    DrawCarDoorway(C, Side.Doors[I], Seat, Reclining);
    DrawCarDoorInterior(C, Side.Doors[I], Reclining);
  end;
end;

procedure DrawTrainSideView(C: TTrainCanvas; const S: TTrainSettings; Layer: TTrainSideLayer;
  Opening: Single = 0);
var
  Side: TRailSideLayout;
  HalfWidth, Left, Right, CarX, DoorX: Single;
  I, Door: Integer;
  View, Previous: TD2D1Matrix3x2F;
begin
  Side := RailSide(S.Style);
  HalfWidth := DESIGN_W * 0.5 / (RUN_CAR_SCALE * (S.Tracks[ttZoom] / 100));
  Left := Side.ViewCenterX - HalfWidth;
  Right := Side.ViewCenterX + HalfWidth;
  View := ApplyTrainSideView(C, S, Side);
  try
    if Layer = tslBody then
    begin
      if Left < 0 then DrawRailCoupling(C, 0, 0);
      if Right > WIDE_CAR_LENGTH then DrawRailCoupling(C, WIDE_CAR_LENGTH, 0);
    end;
    for I := -1 to 1 do
    begin
      CarX := I * WIDE_CAR_LENGTH;
      if (CarX >= Right) or (CarX + WIDE_CAR_LENGTH <= Left) then Continue;
      Previous := C.ApplyTransform(TD2D1Matrix3x2F.Translation(CarX, 0));
      try
        case Layer of
          tslCabin: DrawRunCarInterior(C, S, Side);
          tslBody: DrawRailCar(C, S, ceMiddle, cvSide);
          tslDoors:
            for Door := 0 to Side.DoorCount - 1 do
            begin
              DoorX := Side.Doors[Door];
              if (CarX + DoorX + CAR_DOOR_W > Left) and (CarX + DoorX < Right) then
                DrawExteriorDoor(C, S, DoorX, Opening, IsCommuter(S.Style));
            end;
        end;
      finally
        C.RestoreTransform(Previous);
      end;
    end;
  finally
    C.RestoreTransform(View);
  end;
end;

procedure DrawSlidingDoors(C: TTrainCanvas; const S: TTrainSettings; Opening: Single;
  Inside: Boolean);
var
  Stroke: Single;
begin
  if Opening >= 1 then Exit;
  if not Inside then
  begin
    // 走行では閉扉、降車では同じ進捗を画角に入る全車の客用扉へ渡す。
    DrawTrainSideView(C, S, tslDoors, Opening);
    Exit;
  end;

  Stroke := Opening * (BOARD_W * 0.5 + 1);
  C.PushClip(BOARD_L, BOARD_T, BOARD_W, BOARD_H);
  try
    BoardDoorLeaf(C, S, BOARD_L - Stroke, True);
    BoardDoorLeaf(C, S, BOARD_L + BOARD_W * 0.5 + Stroke, False);
  finally
    C.PopClip;
  end;
end;

procedure DrawRunCabin(C: TTrainCanvas; const S: TTrainSettings);
begin
  DrawTrainSideView(C, S, tslCabin);
end;

procedure DrawRunBody(C: TTrainCanvas; const S: TTrainSettings);
begin
  DrawTrainSideView(C, S, tslBody);
end;

procedure DrawExitRear(C: TTrainCanvas; const S: TTrainSettings);
begin
  DrawRunCabin(C, S);
  DrawRunBody(C, S);
end;

end.

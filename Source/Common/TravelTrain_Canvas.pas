unit TravelTrain_Canvas;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// SYNC_Elevator の共通描画処理を継承する。
// Direct2D の描画先と再利用するブラシを保持し、列車と風景の共通図形を描画する。

interface

uses Winapi.D2D1;

type
  TTrainCanvas = class
  private
    FFactory: ID2D1Factory;
    FTarget: ID2D1RenderTarget;
    FBrush: ID2D1SolidColorBrush;
    FRound: ID2D1StrokeStyle;
    procedure SetColor(Color: Cardinal; Alpha: Single);
    function Gradient(const FromPoint, ToPoint: TD2D1Point2F;
      Color1, Color2, Color3: Cardinal): ID2D1LinearGradientBrush;
    function Outline(const Points: array of TD2D1Point2F; Filled, Closed: Boolean): ID2D1PathGeometry;
    procedure PushGeometryClip(const Bounds: TD2D1RectF; const Geometry: ID2D1Geometry;
      Opacity: Single = 1);
  public
    // 描画先とファクトリを参照保持する。BeginDraw と EndDraw は呼び出し側が管理する。
    constructor Create(const Factory: ID2D1Factory; const Target: ID2D1RenderTarget);
    // 座標は論理ピクセル。PushClip と PopClip は同じ描画先で対応させる。
    procedure PushClip(X, Y, W, H: Single);
    procedure PopClip;
    // Bounds から Holes を除いた領域、または Points で囲む領域へ描画を制限する。
    // どちらも PopShapeClip で元の描画範囲へ戻す。
    procedure PushCutouts(const Bounds: TD2D1RectF; const Holes: array of TD2D1RoundedRect);
    procedure PushShapeClip(const Bounds: TD2D1RectF; const Points: array of TD2D1Point2F);
    procedure PopShapeClip;
    // 変換を合成し、RestoreTransform に渡す直前の行列を返す。
    function ApplyTransform(const Transform: TD2D1Matrix3x2F): TD2D1Matrix3x2F;
    procedure RestoreTransform(const Transform: TD2D1Matrix3x2F);
    // 色は $RRGGBB、Alpha は 0 が透明、1 が不透明。太さも論理ピクセルで指定する。
    procedure Line(X1, Y1, X2, Y2, Stroke: Single; Color: Cardinal; Alpha: Single = 1);
    procedure Oval(X, Y, RX, RY: Single; Color: Cardinal; Alpha: Single = 1);
    procedure Ring(X, Y, RX, RY, Stroke: Single; Color: Cardinal);
    procedure StrokePath(const Points: array of TD2D1Point2F; Stroke: Single; Color: Cardinal;
      Closed: Boolean = False);
    procedure Box(X, Y, W, H, Radius: Single; Color: Cardinal; Alpha: Single = 1);
    procedure BoxEdge(X, Y, W, H, Radius, Stroke: Single; Color: Cardinal; Alpha: Single = 1);
    procedure Metal(X, Y, W, H, Radius: Single; Color: Cardinal);
    procedure Panel(X, Y, W, H, Radius: Single; Color1, Color2, Color3: Cardinal);
    procedure Polygon(const Points: array of TD2D1Point2F; Color: Cardinal; Alpha: Single = 1);
    procedure GradientPolygon(const Points: array of TD2D1Point2F;
      const FromPoint, ToPoint: TD2D1Point2F; Color1, Color2, Color3: Cardinal);
    procedure Glow(X, Y, RX, RY: Single; Color: Cardinal; Alpha: Single);
  end;

// 係数 1 を基準に暗くするか白に近づける。
function Shade(Color: Cardinal; Factor: Single): Cardinal;
// 2色を混ぜる。Weight が 0 なら First、1 なら Second。
function Mix(First, Second: Cardinal; Weight: Single): Cardinal;
// 論理座標を Direct2D の頂点にする。
function Pt(X, Y: Single): TD2D1Point2F; inline;

implementation

uses System.Math, System.Win.ComObj;

function Pt(X, Y: Single): TD2D1Point2F;
begin
  Result := D2D1PointF(X, Y);
end;

function Mix(First, Second: Cardinal; Weight: Single): Cardinal;
var
  Shift: Integer;
  A, B: Cardinal;
begin
  Result := 0;
  for Shift in [0, 8, 16] do
  begin
    A := (First shr Shift) and 255;
    B := (Second shr Shift) and 255;
    Result := Result or (Cardinal(Round(A * (1 - Weight) + B * Weight)) shl Shift);
  end;
end;

function Shade(Color: Cardinal; Factor: Single): Cardinal;
begin
  if Factor <= 1 then Result := Mix(0, Color, Max(0.0, Factor))
  else Result := Mix(Color, $FFFFFF, Min(1.0, Factor - 1));
end;

function RGBA(Color: Cardinal; Alpha: Single): TD2D1ColorF;
begin
  Result := D2D1ColorF(((Color shr 16) and 255) / 255,
    ((Color shr 8) and 255) / 255, (Color and 255) / 255, Alpha);
end;

function Rounded(X, Y, W, H, Radius: Single): TD2D1RoundedRect;
begin
  Radius := Min(Radius, Min(W, H) * 0.5);
  Result := D2D1RoundedRect(D2D1RectF(X, Y, X + W, Y + H), Radius, Radius);
end;

constructor TTrainCanvas.Create(const Factory: ID2D1Factory; const Target: ID2D1RenderTarget);
var
  Properties: TD2D1StrokeStyleProperties;
begin
  inherited Create;
  FFactory := Factory;
  FTarget := Target;
  OleCheck(FTarget.CreateSolidColorBrush(RGBA(0, 1), nil, FBrush));
  Properties := D2D1StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
    D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND);
  OleCheck(FFactory.CreateStrokeStyle(Properties, nil, 0, FRound));
end;

procedure TTrainCanvas.PushClip(X, Y, W, H: Single);
begin
  FTarget.PushAxisAlignedClip(D2D1RectF(X, Y, X + W, Y + H), D2D1_ANTIALIAS_MODE_ALIASED);
end;

procedure TTrainCanvas.PopClip;
begin
  FTarget.PopAxisAlignedClip;
end;

procedure TTrainCanvas.PushGeometryClip(const Bounds: TD2D1RectF; const Geometry: ID2D1Geometry;
  Opacity: Single);
var
  Parameters: TD2D1LayerParameters;
  Layer: ID2D1Layer;
begin
  Parameters := Default(TD2D1LayerParameters);
  Parameters.contentBounds := Bounds;
  Parameters.geometricMask := Geometry;
  Parameters.maskAntialiasMode := D2D1_ANTIALIAS_MODE_PER_PRIMITIVE;
  Parameters.maskTransform := TD2D1Matrix3x2F.Identity;
  Parameters.opacity := Opacity;
  OleCheck(FTarget.CreateLayer(nil, Layer));
  FTarget.PushLayer(Parameters, Layer);
end;

procedure TTrainCanvas.PushCutouts(const Bounds: TD2D1RectF;
  const Holes: array of TD2D1RoundedRect);
var
  Frame: ID2D1RectangleGeometry;
  Hole: ID2D1RoundedRectangleGeometry;
  Parts: TArray<ID2D1Geometry>;
  Mask: ID2D1GeometryGroup;
  I: Integer;
begin
  SetLength(Parts, Length(Holes) + 1);
  OleCheck(FFactory.CreateRectangleGeometry(Bounds, Frame));
  Parts[0] := Frame;
  for I := 0 to High(Holes) do
  begin
    OleCheck(FFactory.CreateRoundedRectangleGeometry(Holes[I], Hole));
    Parts[I + 1] := Hole;
  end;
  OleCheck(FFactory.CreateGeometryGroup(D2D1_FILL_MODE_ALTERNATE, @Parts[0], Length(Parts), Mask));
  PushGeometryClip(Bounds, Mask);
end;

procedure TTrainCanvas.PushShapeClip(const Bounds: TD2D1RectF; const Points: array of TD2D1Point2F);
begin
  PushGeometryClip(Bounds, Outline(Points, True, True));
end;

procedure TTrainCanvas.PopShapeClip;
begin
  FTarget.PopLayer;
end;

function TTrainCanvas.ApplyTransform(const Transform: TD2D1Matrix3x2F): TD2D1Matrix3x2F;
begin
  FTarget.GetTransform(Result);
  FTarget.SetTransform(Transform * Result);
end;

procedure TTrainCanvas.RestoreTransform(const Transform: TD2D1Matrix3x2F);
begin
  FTarget.SetTransform(Transform);
end;

procedure TTrainCanvas.SetColor(Color: Cardinal; Alpha: Single);
begin
  FBrush.SetColor(RGBA(Color, Alpha));
end;

procedure TTrainCanvas.Line(X1, Y1, X2, Y2, Stroke: Single; Color: Cardinal; Alpha: Single);
begin
  SetColor(Color, Alpha);
  FTarget.DrawLine(Pt(X1, Y1), Pt(X2, Y2), FBrush, Stroke, FRound);
end;

procedure TTrainCanvas.Oval(X, Y, RX, RY: Single; Color: Cardinal; Alpha: Single);
begin
  SetColor(Color, Alpha);
  FTarget.FillEllipse(D2D1Ellipse(Pt(X, Y), RX, RY), FBrush);
end;

procedure TTrainCanvas.Ring(X, Y, RX, RY, Stroke: Single; Color: Cardinal);
begin
  SetColor(Color, 1);
  FTarget.DrawEllipse(D2D1Ellipse(Pt(X, Y), RX, RY), FBrush, Stroke, nil);
end;

procedure TTrainCanvas.StrokePath(const Points: array of TD2D1Point2F; Stroke: Single;
  Color: Cardinal; Closed: Boolean);
begin
  if Length(Points) < 2 then Exit;
  SetColor(Color, 1);
  FTarget.DrawGeometry(Outline(Points, False, Closed), FBrush, Stroke, FRound);
end;

procedure TTrainCanvas.Box(X, Y, W, H, Radius: Single; Color: Cardinal; Alpha: Single);
begin
  SetColor(Color, Alpha);
  FTarget.FillRoundedRectangle(Rounded(X, Y, W, H, Radius), FBrush);
end;

procedure TTrainCanvas.BoxEdge(X, Y, W, H, Radius, Stroke: Single; Color: Cardinal; Alpha: Single);
begin
  SetColor(Color, Alpha);
  FTarget.DrawRoundedRectangle(Rounded(X, Y, W, H, Radius), FBrush, Stroke, nil);
end;

function TTrainCanvas.Gradient(const FromPoint, ToPoint: TD2D1Point2F;
  Color1, Color2, Color3: Cardinal): ID2D1LinearGradientBrush;
var
  Stops: array[0..2] of TD2D1GradientStop;
  Collection: ID2D1GradientStopCollection;
begin
  Stops[0] := D2D1GradientStop(0, RGBA(Color1, 1));
  Stops[1] := D2D1GradientStop(0.45, RGBA(Color2, 1));
  Stops[2] := D2D1GradientStop(1, RGBA(Color3, 1));
  OleCheck(FTarget.CreateGradientStopCollection(@Stops[0], Length(Stops), D2D1_GAMMA_2_2,
    D2D1_EXTEND_MODE_CLAMP, Collection));
  OleCheck(FTarget.CreateLinearGradientBrush(D2D1LinearGradientBrushProperties(
    FromPoint, ToPoint), nil, Collection, Result));
end;

procedure TTrainCanvas.Metal(X, Y, W, H, Radius: Single; Color: Cardinal);
var
  Stops: array[0..5] of TD2D1GradientStop;
  Collection: ID2D1GradientStopCollection;
  Brush: ID2D1LinearGradientBrush;
begin
  Stops[0] := D2D1GradientStop(0, RGBA(Shade(Color, 0.62), 1));
  Stops[1] := D2D1GradientStop(0.13, RGBA(Shade(Color, 1.09), 1));
  Stops[2] := D2D1GradientStop(0.35, RGBA(Shade(Color, 0.86), 1));
  Stops[3] := D2D1GradientStop(0.64, RGBA(Shade(Color, 1.31), 1));
  Stops[4] := D2D1GradientStop(0.82, RGBA(Shade(Color, 1.03), 1));
  Stops[5] := D2D1GradientStop(1, RGBA(Shade(Color, 0.58), 1));
  OleCheck(FTarget.CreateGradientStopCollection(@Stops[0], Length(Stops),
    D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP, Collection));
  OleCheck(FTarget.CreateLinearGradientBrush(D2D1LinearGradientBrushProperties(
    Pt(X, Y), Pt(X + W, Y + H * 0.04)), nil, Collection, Brush));
  FTarget.FillRoundedRectangle(Rounded(X, Y, W, H, Radius), Brush);
end;

procedure TTrainCanvas.Panel(X, Y, W, H, Radius: Single; Color1, Color2, Color3: Cardinal);
begin
  FTarget.FillRoundedRectangle(Rounded(X, Y, W, H, Radius),
    Gradient(Pt(X, Y), Pt(X + W * 0.35, Y + H), Color1, Color2, Color3));
end;

function TTrainCanvas.Outline(const Points: array of TD2D1Point2F;
  Filled, Closed: Boolean): ID2D1PathGeometry;
var
  Sink: ID2D1GeometrySink;
  BeginMode: TD2D1FigureBegin;
  EndMode: D2D1_FIGURE_END;
begin
  OleCheck(FFactory.CreatePathGeometry(Result));
  OleCheck(Result.Open(Sink));
  BeginMode := D2D1_FIGURE_BEGIN_HOLLOW;
  if Filled then BeginMode := D2D1_FIGURE_BEGIN_FILLED;
  EndMode := D2D1_FIGURE_END_OPEN;
  if Closed then EndMode := D2D1_FIGURE_END_CLOSED;
  Sink.BeginFigure(Points[0], BeginMode);
  Sink.AddLines(@Points[1], High(Points));
  Sink.EndFigure(EndMode);
  OleCheck(Sink.Close);
end;

procedure TTrainCanvas.Polygon(const Points: array of TD2D1Point2F; Color: Cardinal; Alpha: Single);
begin
  if Length(Points) < 3 then Exit;
  SetColor(Color, Alpha);
  FTarget.FillGeometry(Outline(Points, True, True), FBrush, nil);
end;

procedure TTrainCanvas.GradientPolygon(const Points: array of TD2D1Point2F;
  const FromPoint, ToPoint: TD2D1Point2F; Color1, Color2, Color3: Cardinal);
begin
  if Length(Points) < 3 then Exit;
  FTarget.FillGeometry(Outline(Points, True, True),
    Gradient(FromPoint, ToPoint, Color1, Color2, Color3), nil);
end;

procedure TTrainCanvas.Glow(X, Y, RX, RY: Single; Color: Cardinal; Alpha: Single);
var
  Stops: array[0..1] of TD2D1GradientStop;
  Collection: ID2D1GradientStopCollection;
  Brush: ID2D1RadialGradientBrush;
begin
  Stops[0] := D2D1GradientStop(0, RGBA(Color, Alpha));
  Stops[1] := D2D1GradientStop(1, RGBA(Color, 0));
  OleCheck(FTarget.CreateGradientStopCollection(@Stops[0], Length(Stops), D2D1_GAMMA_2_2,
    D2D1_EXTEND_MODE_CLAMP, Collection));
  OleCheck(FTarget.CreateRadialGradientBrush(D2D1RadialGradientBrushProperties(
    Pt(X, Y), Pt(0, 0), RX, RY), nil, Collection, Brush));
  FTarget.FillEllipse(D2D1Ellipse(Pt(X, Y), RX, RY), Brush);
end;

end.

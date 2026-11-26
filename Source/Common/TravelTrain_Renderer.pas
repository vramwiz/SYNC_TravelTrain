unit TravelTrain_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// シーンのレイヤーを順に合成し、AviUtl2へストレートアルファのRGBAを返す。

interface

uses Winapi.D2D1, Winapi.Wincodec, AviUtl2FilterTypes, TravelTrain_Canvas,
  TravelTrain_Settings, TravelTrain_Timeline;

type
  TTrainImageCache = record
    Bitmap: ID2D1Bitmap;
    Layer: TTrainLayer;
    Colors: TTrainColors;
    Style: TTrainStyle;
    Zoom: Integer;
  end;
  TTrainRenderer = class
  private
    FFactory: ID2D1Factory;
    FWic: IWICImagingFactory;
    FBitmap: IWICBitmap;
    FTarget: ID2D1RenderTarget;
    FCanvas: TTrainCanvas;
    FComCookie: Pointer;
    FCache: array[0..1] of TTrainImageCache;
    FWidth, FHeight: Integer;
    FPixels: TArray<TPIXEL_RGBA>;
    procedure ResetTarget;
    procedure EnsureTarget(Width, Height: Integer);
    procedure PrepareStatic(Slot: Integer; Layer: TTrainLayer; const S: TTrainSettings);
    procedure PaintStatic(Slot: Integer; Layer: TTrainLayer; const S: TTrainSettings);
    procedure PaintFrame(const S: TTrainSettings; const F: TTrainFrame);
    procedure ReadPixels;
  public
    destructor Destroy; override;
    // 呼び出しはインスタンス単位で直列化する。ホストには呼出中だけ画像を渡す。
    procedure Render(Video: PFILTER_PROC_VIDEO; Width, Height: Integer;
      const S: TTrainSettings; Seconds: Double);
  end;

implementation

uses System.Math, System.SysUtils, System.Win.ComObj, Winapi.Windows, Winapi.ActiveX,
  Winapi.DxgiFormat, TravelTrain_Scenery, TravelTrain_Art;

const
  MAX_CACHED_PIXELS = 3840 * 2160;

function CoIncrementMTAUsage(out Cookie: Pointer): HRESULT; stdcall;
  external 'ole32.dll' name 'CoIncrementMTAUsage';
function CoDecrementMTAUsage(Cookie: Pointer): HRESULT; stdcall;
  external 'ole32.dll' name 'CoDecrementMTAUsage';

procedure DrawStatic(C: TTrainCanvas; Layer: TTrainLayer; const S: TTrainSettings);
var
  Transform: TD2D1Matrix3x2F;
  Zoom: Single;
begin
  case Layer of
    lyArrivalPlatform, lyDeparture: DrawStation(C, S.Scene);
    lyBoardPlatform:
      begin
        DrawStation(C, S.Scene);
        DrawBoardFloor(C);
      end;
    lyBoardCabin: DrawBoardCabin(C, S);
    lyExitRear: DrawExitRear(C, S);
    lyRunRear, lyRunFront:
      begin
        Zoom := S.Tracks[ttZoom] / 100;
        // 窓と座席を同じ位置へ移す。線路面は移動量を含まず、同じ基準点で拡大する。
        Transform := C.ApplyTransform(TD2D1Matrix3x2F.Translation(0, -RUN_TRAIN_RISE) *
          TD2D1Matrix3x2F.Scale(Zoom, Zoom, Pt(DESIGN_W / 2, DESIGN_H / 2)));
        try
          if Layer = lyRunRear then DrawRunCabin(C, S)
          else DrawRunBody(C, S);
        finally
          C.RestoreTransform(Transform);
        end;
      end;
  end;
end;

destructor TTrainRenderer.Destroy;
begin
  ResetTarget;
  FFactory := nil;
  FWic := nil;
  if FComCookie <> nil then CoDecrementMTAUsage(FComCookie);
  inherited;
end;

procedure TTrainRenderer.ResetTarget;
begin
  FCache[0] := Default(TTrainImageCache);
  FCache[1] := Default(TTrainImageCache);
  FreeAndNil(FCanvas);
  FTarget := nil;
  FBitmap := nil;
  FWidth := 0;
  FHeight := 0;
end;

procedure TTrainRenderer.EnsureTarget(Width, Height: Integer);
var
  Properties: TD2D1RenderTargetProperties;
  Scale, OffsetX, OffsetY: Single;
begin
  if (FWidth = Width) and (FHeight = Height) then Exit;
  if FComCookie = nil then OleCheck(CoIncrementMTAUsage(FComCookie));
  if FFactory = nil then
    OleCheck(D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED, ID2D1Factory, nil, FFactory));
  if FWic = nil then
    OleCheck(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
      IID_IWICImagingFactory, FWic));
  ResetTarget;
  OleCheck(FWic.CreateBitmap(Width, Height, @GUID_WICPixelFormat32bppPBGRA,
    WICBitmapCacheOnLoad, FBitmap));
  Properties := D2D1RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,
    D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
  OleCheck(FFactory.CreateWicBitmapRenderTarget(FBitmap, Properties, FTarget));
  FCanvas := TTrainCanvas.Create(FFactory, FTarget);
  // 横長・縦長でも車体の比率を保ち、全レイヤーを同じ中心で切り出す。
  Scale := Max(Width / DESIGN_W, Height / DESIGN_H);
  OffsetX := (Width - DESIGN_W * Scale) * 0.5;
  OffsetY := (Height - DESIGN_H * Scale) * 0.5;
  FTarget.SetTransform(TD2D1Matrix3x2F.Scale(Scale, Scale, Pt(0, 0)) *
    TD2D1Matrix3x2F.Translation(OffsetX, OffsetY));
  SetLength(FPixels, Width * Height);
  FWidth := Width;
  FHeight := Height;
end;

procedure TTrainRenderer.PrepareStatic(Slot: Integer; Layer: TTrainLayer; const S: TTrainSettings);
var
  Entry: TTrainImageCache;
  Target: ID2D1BitmapRenderTarget;
  Canvas: TTrainCanvas;
  Transform: TD2D1Matrix3x2F;
begin
  if not (Layer in S.Layers) or (FWidth * FHeight > MAX_CACHED_PIXELS) then
  begin
    FCache[Slot].Bitmap := nil;
    Exit;
  end;
  Entry := Default(TTrainImageCache);
  Entry.Layer := Layer;
  if Layer in [lyBoardCabin, lyExitRear, lyRunRear, lyRunFront] then
  begin
    Entry.Style := S.Style;
    Entry.Colors := S.Colors;
  end;
  if Layer in [lyRunRear, lyRunFront] then Entry.Zoom := Round(S.Tracks[ttZoom] * 10000);
  if (FCache[Slot].Bitmap <> nil) and (FCache[Slot].Layer = Entry.Layer) and
    (FCache[Slot].Style = Entry.Style) and (FCache[Slot].Zoom = Entry.Zoom) and
    (FCache[Slot].Colors.Body = Entry.Colors.Body) and
    (FCache[Slot].Colors.Stripe = Entry.Colors.Stripe) then Exit;

  FCache[Slot].Bitmap := nil;
  OleCheck(FTarget.CreateCompatibleRenderTarget(nil, nil, nil,
    D2D1_COMPATIBLE_RENDER_TARGET_OPTIONS_NONE, Target));
  FTarget.GetTransform(Transform);
  Target.SetTransform(Transform);
  Canvas := TTrainCanvas.Create(FFactory, Target);
  try
    Target.BeginDraw;
    try
      Target.Clear(D2D1ColorF(0, 0, 0, 0));
      DrawStatic(Canvas, Layer, S);
    finally
      OleCheck(Target.EndDraw);
    end;
    OleCheck(Target.GetBitmap(Entry.Bitmap));
    FCache[Slot] := Entry;
  finally
    Canvas.Free;
  end;
end;

procedure TTrainRenderer.PaintStatic(Slot: Integer; Layer: TTrainLayer; const S: TTrainSettings);
var
  Destination: TD2D1RectF;
  Transform: TD2D1Matrix3x2F;
begin
  if FCache[Slot].Bitmap = nil then
  begin
    DrawStatic(FCanvas, Layer, S);
    Exit;
  end;
  Destination := D2D1RectF(0, 0, FWidth, FHeight);
  FTarget.GetTransform(Transform);
  FTarget.SetTransform(TD2D1Matrix3x2F.Identity);
  try
    FTarget.DrawBitmap(FCache[Slot].Bitmap, @Destination, 1, D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR, nil);
  finally
    FTarget.SetTransform(Transform);
  end;
end;

procedure TTrainRenderer.PaintFrame(const S: TTrainSettings; const F: TTrainFrame);
begin
  case S.Scene of
    tsArrival:
      begin
        if lyArrivalPlatform in S.Layers then PaintStatic(0, lyArrivalPlatform, S);
        if (lyArrivalTrain in S.Layers) and F.TrainVisible then DrawWideTrain(FCanvas, S, F.TrainX, False);
      end;
    tsBoard:
      begin
        if lyBoardPlatform in S.Layers then PaintStatic(0, lyBoardPlatform, S);
        if lyBoardDoors in S.Layers then DrawSlidingDoors(FCanvas, S, F.DoorOpen, True);
        if lyBoardCabin in S.Layers then PaintStatic(1, lyBoardCabin, S);
      end;
    tsRun:
      begin
        if lyRunRear in S.Layers then
        begin
          DrawLandscape(FCanvas, S, F.Distance);
          DrawRunningTrack(FCanvas, S.Tracks[ttElevation], F.Distance, S.Tracks[ttZoom]);
          PaintStatic(0, lyRunRear, S);
        end;
        if lyRunFront in S.Layers then
        begin
          PaintStatic(1, lyRunFront, S);
          if S.ForegroundPoles then DrawPassingPoles(FCanvas, S.Tracks[ttElevation], F.Distance);
        end;
      end;
    tsExit:
      begin
        if lyExitRear in S.Layers then PaintStatic(0, lyExitRear, S);
        if lyExitDoors in S.Layers then DrawSlidingDoors(FCanvas, S, F.DoorOpen, False);
      end;
    tsDeparture:
      if lyDeparture in S.Layers then
      begin
        PaintStatic(0, lyDeparture, S);
        if F.TrainVisible then DrawWideTrain(FCanvas, S, F.TrainX, True);
      end;
  end;
end;

procedure TTrainRenderer.ReadPixels;
var
  Locked: IWICBitmapLock;
  Rect: WICRect;
  Buffer: WICInProcPointer;
  Stride, ByteCount: Cardinal;
  Y, X, A: Integer;
  Src, Dest: PPIXEL_RGBA;
begin
  Rect.X := 0;
  Rect.Y := 0;
  Rect.Width := FWidth;
  Rect.Height := FHeight;
  OleCheck(FBitmap.Lock(Rect, WICBitmapLockRead, Locked));
  OleCheck(Locked.GetStride(Stride));
  OleCheck(Locked.GetDataPointer(ByteCount, Buffer));
  if (Buffer = nil) or (Stride < Cardinal(FWidth * 4)) or
    (ByteCount < UInt64(FHeight - 1) * Stride + Cardinal(FWidth * 4)) then
    raise EInvalidOp.Create('Invalid WIC pixel buffer');
  Dest := @FPixels[0];
  for Y := 0 to FHeight - 1 do
  begin
    Src := PPIXEL_RGBA(PByte(Buffer) + NativeInt(Stride) * Y);
    for X := 0 to FWidth - 1 do
    begin
      A := Src^.A;
      Dest^.A := A;
      case A of
        0: Dest^ := Default(TPIXEL_RGBA);
        255:
          begin
            Dest^.R := Src^.B;
            Dest^.G := Src^.G;
            Dest^.B := Src^.R;
          end;
      else
        Dest^.R := (Src^.B * 255 + A div 2) div A;
        Dest^.G := (Src^.G * 255 + A div 2) div A;
        Dest^.B := (Src^.R * 255 + A div 2) div A;
      end;
      Inc(Src);
      Inc(Dest);
    end;
  end;
end;

procedure TTrainRenderer.Render(Video: PFILTER_PROC_VIDEO; Width, Height: Integer;
  const S: TTrainSettings; Seconds: Double);
var
  Frame: TTrainFrame;
begin
  Frame := EvaluateTrainFrame(S, Seconds);
  try
    EnsureTarget(Width, Height);
    if not (S.Scene in [tsBoard, tsRun]) then FCache[1].Bitmap := nil;
    case S.Scene of
      tsArrival: PrepareStatic(0, lyArrivalPlatform, S);
      tsBoard:
        begin
          PrepareStatic(0, lyBoardPlatform, S);
          PrepareStatic(1, lyBoardCabin, S);
        end;
      tsRun:
        begin
          PrepareStatic(0, lyRunRear, S);
          PrepareStatic(1, lyRunFront, S);
        end;
      tsExit: PrepareStatic(0, lyExitRear, S);
      tsDeparture: PrepareStatic(0, lyDeparture, S);
    end;
    FTarget.BeginDraw;
    try
      FTarget.Clear(D2D1ColorF(0, 0, 0, 0));
      PaintFrame(S, Frame);
    finally
      OleCheck(FTarget.EndDraw);
    end;
    ReadPixels;
    Video^.SetImageData(@FPixels[0], Width, Height);
  except
    ResetTarget;
    raise;
  end;
end;

end.

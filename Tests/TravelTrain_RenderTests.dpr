program TravelTrain_RenderTests;

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  System.SysUtils, System.Classes, System.Math, System.Diagnostics, System.IOUtils, Winapi.Windows,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  TravelTrain_Settings in '..\Source\Common\TravelTrain_Settings.pas',
  TravelTrain_Timeline in '..\Source\Common\TravelTrain_Timeline.pas';

type
  TPixels = TArray<TPIXEL_RGBA>;
  TRequired = function: Cardinal; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;

var
  Table: PFILTER_PLUGIN_TABLE;
  Capture: TPixels;
  ExpectedWidth, ExpectedHeight: Integer;
  Selected: UTF8String;
  Changes: TStringList;
  ImageDir: string;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

function FindItem(const Name: string; const ItemType: string = ''): Pointer;
var
  P: PPointer;
  Header: PFILTER_ITEM_STRING;
begin
  P := PPointer(Table^.Items);
  while P^ <> nil do
  begin
    Header := P^;
    if (string(Header^.Name) = Name) and
      ((ItemType = '') or (string(Header^.ItemType) = ItemType)) then Exit(P^);
    Inc(P);
  end;
  raise Exception.Create('Missing item: ' + Name);
end;

procedure SetTrack(Track: TTrainTrack; Value: Double);
begin
  PFILTER_ITEM_TRACK(FindItem(TRAIN_TRACKS[Track].Name, 'track'))^.Value := Value;
end;

procedure SetScenery(Scenery: TTrainScenery);
begin
  PFILTER_ITEM_SELECT(FindItem('背景の種類', 'select'))^.Value := Ord(Scenery);
end;

procedure SelectScene(Scene: TTrainScene);
begin
  PFILTER_ITEM_SELECT(FindItem('シーンプリセット', 'select'))^.Value := Ord(Scene);
end;

procedure SelectLayers(Layers: TTrainLayers);
var
  Layer: TTrainLayer;
begin
  for Layer := Low(TTrainLayer) to High(TTrainLayer) do
    PFILTER_ITEM_CHECK(FindItem(LAYER_NAMES[Layer], 'check'))^.Value := Ord(Layer in Layers);
end;

procedure SetPalette(Style: TTrainStyle);
  procedure SetColor(const Name: string; Color: Cardinal);
  var
    Item: PFILTER_ITEM_COLOR;
  begin
    Item := FindItem(Name, 'color');
    Item^.R := Color shr 16;
    Item^.G := (Color shr 8) and 255;
    Item^.B := Color and 255;
  end;
begin
  PFILTER_ITEM_SELECT(FindItem('列車プリセット', 'select'))^.Value := Ord(Style);
  SetColor('車体色', TRAIN_PALETTES[Style].Body);
  SetColor('帯色', TRAIN_PALETTES[Style].Stripe);
end;

procedure ReceiveImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  if (Width <> ExpectedWidth) or (Height <> ExpectedHeight) or (Buffer = nil) then Exit;
  SetLength(Capture, Width * Height);
  Move(Buffer^, Capture[0], Length(Capture) * SizeOf(TPIXEL_RGBA));
end;

function Render(Session: Pointer; Seconds: Double; Width: Integer = 640;
  Height: Integer = 360; SceneWidth: Integer = 0; SceneHeight: Integer = 0): TPixels;
var
  V: TFILTER_PROC_VIDEO;
  O: TOBJECT_INFO;
  S: TSCENE_INFO;
begin
  V := Default(TFILTER_PROC_VIDEO);
  O := Default(TOBJECT_INFO);
  S := Default(TSCENE_INFO);
  if SceneWidth = 0 then SceneWidth := Width;
  if SceneHeight = 0 then SceneHeight := Height;
  S.Width := SceneWidth;
  S.Height := SceneHeight;
  O.Time := Seconds;
  V.Scene := @S;
  V.Object_ := @O;
  V.UserData := Session;
  V.SetImageData := ReceiveImage;
  ExpectedWidth := Width;
  ExpectedHeight := Height;
  Capture := nil;
  Check(Table^.Func_Proc_Video(@V) = 1, Format('Video callback failed at %.2f', [Seconds]));
  Check(Length(Capture) = Width * Height, 'Invalid RGBA output size');
  Result := Capture;
end;

function Same(const A, B: TPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and CompareMem(@A[0], @B[0], Length(A) * SizeOf(A[0]));
end;

procedure CheckAlpha(const Pixels: TPixels; Expected: Byte);
var
  Pixel: TPIXEL_RGBA;
begin
  for Pixel in Pixels do Check(Pixel.A = Expected, 'Unexpected alpha');
end;

procedure Overlay(var Base: TPixels; const Front: TPixels);
var
  I, A, B: Integer;
begin
  for I := 0 to High(Base) do
  begin
    A := Front[I].A;
    B := 255 - A;
    Base[I].R := (Base[I].R * B + Front[I].R * A + 127) div 255;
    Base[I].G := (Base[I].G * B + Front[I].G * A + 127) div 255;
    Base[I].B := (Base[I].B * B + Front[I].B * A + 127) div 255;
  end;
end;

procedure CheckComposite(const A, B: TPixels);
var
  I, MaxDelta: Integer;
begin
  MaxDelta := 0;
  for I := 0 to High(A) do
  begin
    MaxDelta := Max(MaxDelta, Abs(A[I].R - B[I].R));
    MaxDelta := Max(MaxDelta, Abs(A[I].G - B[I].G));
    MaxDelta := Max(MaxDelta, Abs(A[I].B - B[I].B));
  end;
  Check(MaxDelta <= 3, Format('Layer composite differs by %d levels', [MaxDelta]));
end;

procedure PaintStandee(var Pixels: TPixels; Center, Feet, Height: Integer);
var
  X, Y: Integer;
  U, V: Double;
  Color: Cardinal;
  Pixel: PPIXEL_RGBA;
begin
  for Y := Feet - Height to Feet do
    for X := Center - Height div 2 to Center + Height div 2 do
    begin
      U := (X - Center) / Height;
      V := (Y - Feet + Height) / Height;
      if Sqr(U / 0.145) + Sqr((V - 0.155) / 0.15) < 1 then
      begin
        Color := $493B48;
        if Sqr(U / 0.108) + Sqr((V - 0.172) / 0.103) < 1 then Color := $EEC4A0;
        if (V > 0.157) and (V < 0.18) and (Abs(Abs(U) - 0.048) < 0.012) then Color := $453A48;
      end
      else if Sqr(U / 0.235) + Sqr((V - 0.50) / 0.26) < 1 then
      begin
        Color := $A55361;
        if Abs(U) < (0.65 - V) * 0.27 then Color := $E7D4AC;
      end
      else if (V > 0.64) and (Abs(U) < 0.13) and (Abs(U) > 0.023) then Color := $344952
      else Continue;
      Pixel := @Pixels[Y * 640 + X];
      Pixel^.R := Color shr 16;
      Pixel^.G := (Color shr 8) and 255;
      Pixel^.B := Color and 255;
    end;
end;

procedure SaveFrame(const Name: string; const Pixels: TPixels; Width: Integer = 640;
  Height: Integer = 360);
var
  Header: TBitmapFileHeader;
  Info: TBitmapInfoHeader;
  Stream: TFileStream;
  OutPixels: TPixels;
  I: Integer;
begin
  if ImageDir = '' then Exit;
  Header := Default(TBitmapFileHeader);
  Info := Default(TBitmapInfoHeader);
  Header.bfType := $4D42;
  Header.bfOffBits := SizeOf(Header) + SizeOf(Info);
  Header.bfSize := Header.bfOffBits + Cardinal(Width * Height * 4);
  Info.biSize := SizeOf(Info);
  Info.biWidth := Width;
  Info.biHeight := -Height;
  Info.biPlanes := 1;
  Info.biBitCount := 32;
  SetLength(OutPixels, Length(Pixels));
  for I := 0 to High(OutPixels) do
  begin
    OutPixels[I].R := Pixels[I].B;
    OutPixels[I].G := Pixels[I].G;
    OutPixels[I].B := Pixels[I].R;
    OutPixels[I].A := 255;
  end;
  Stream := TFileStream.Create(TPath.Combine(ImageDir, Name + '.bmp'), fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
    Stream.WriteBuffer(Info, SizeOf(Info));
    Stream.WriteBuffer(OutPixels[0], Length(OutPixels) * SizeOf(OutPixels[0]));
  finally
    Stream.Free;
  end;
end;

function ReadPreset(Obj: OBJECT_HANDLE; Effect, Item: PWideChar): PAnsiChar; cdecl;
begin
  Result := PAnsiChar(Selected);
end;

function RecordPreset(Obj: OBJECT_HANDLE; Effect, Item: PWideChar; Value: PAnsiChar): Boolean; cdecl;
begin
  Result := (Obj = Pointer(1)) and (string(Effect) = '旅行列車:2');
  if Result then Changes.Values[string(Item)] := string(UTF8String(Value));
end;

procedure VerifyPresets;
var
  Edit: TEDIT_SECTION;
  SceneButton, ColorButton: PFILTER_ITEM_BUTTON;
begin
  Edit := Default(TEDIT_SECTION);
  Edit.GetObjectItemValue := ReadPreset;
  Edit.SetObjectItemValue := RecordPreset;
  SceneButton := FindItem('シーン設定を初期値に戻す', 'button');
  ColorButton := FindItem('列車の配色を反映', 'button');
  Changes := TStringList.Create;
  try
    Selected := UTF8String(STYLE_NAMES[trStreamlined]);
    ColorButton^.Callback2(@Edit, Pointer(1), '旅行列車:2', ColorButton^.Name);
    Check(Changes.Values['車体色'] = 'D8E6EA', 'Incorrect vehicle preset color');
    Check(Changes.Values['帯色'] = '365D9B', 'Incorrect vehicle preset stripe');
    Check(Changes.Count = 2, 'Vehicle preset must only set colors');
    Changes.Clear;
    Selected := UTF8String(SCENE_NAMES[tsExit]);
    SceneButton^.Callback2(@Edit, Pointer(1), '旅行列車:2', SceneButton^.Name);
    Check(Changes.Count = 7, 'Incorrect scene reset scope');
    Check(Changes.Values[TRAIN_TRACKS[ttExitHold].Name] = '2.1', 'Incorrect exit hold preset');
    Check(Changes.Values[LAYER_NAMES[lyExitDoors]] = '1', 'Preset did not restore the door layer');
    Changes.Clear;
    Selected := UTF8String(SCENE_NAMES[tsRun]);
    SceneButton^.Callback2(@Edit, Pointer(1), '旅行列車:2', SceneButton^.Name);
    Check(Changes.Values['背景の種類'] = 'ビル街', 'The running reset must restore the default scenery');
  finally
    Changes.Free;
  end;
end;

procedure VerifyTimeline;
var
  S: TTrainSettings;
  T: TTrainTrack;
begin
  S := DefaultTrainSettings(tsRun);
  Check(EvaluateTrainFrame(S, 0.5).Distance = 0, 'Run starts during wait');
  Check(SameValue(EvaluateTrainFrame(S, 1.5).Distance, 127.5), 'Incorrect acceleration distance');
  Check(SameValue(EvaluateTrainFrame(S, 2.5).Distance, 510.0), 'Acceleration boundary');
  Check(SameValue(EvaluateTrainFrame(S, 7.5).Distance, 3060.0), 'Cruise boundary');
  Check(SameValue(EvaluateTrainFrame(S, 20).Distance, 3621.0), 'Brake boundary');
  Check(EvaluateTrainFrame(S, 7).ArrivalProgress = 0, 'The arrival platform starts too soon');
  Check((EvaluateTrainFrame(S, 8).ArrivalProgress > 0) and
    (EvaluateTrainFrame(S, 8).ArrivalProgress < 1), 'The platform should enter during braking');
  Check(SameValue(EvaluateTrainFrame(S, 20).ArrivalProgress, 1.0), 'The arrival platform must finish at the stop');
  for T := ttRunBefore to ttRunAfter do S.Tracks[T] := 0;
  Check(EvaluateTrainFrame(S, 20).Distance = 0, 'Zero stages must have no displacement');
  Check(EvaluateTrainFrame(S, 20).ArrivalProgress = 0, 'A stationary train does not enter a second platform');
  S.Tracks[ttRunCruise] := 0.1;
  Check(SameValue(EvaluateTrainFrame(S, 1).ArrivalProgress, 1.0), 'Short runs must arrive without braking');
end;

procedure VerifyImages(Session, SplitSession: Pointer);
const
  Times: array[TTrainScene] of Double = (2.1, 0.77, 5.7, 0.67, 2.1);
  Names: array[TTrainScene] of string = ('arrival', 'boarding', 'running', 'exit', 'departure');
var
  Scene: TTrainScene;
  Layer: TTrainLayer;
  Full, Base, Part, Ref: TPixels;
  Style: TTrainStyle;
  Scenery: TTrainScenery;
  I: Integer;
  SW: TStopwatch;
  WheelBaseX, TailTime: Double;
begin
  Check(PFILTER_ITEM_SELECT(FindItem('背景の種類', 'select'))^.Value = Ord(scTown),
    'New objects must default to the city skyline');
  SetScenery(scCountryside);
  for Scene := Low(TTrainScene) to High(TTrainScene) do
  begin
    SelectScene(Scene);
    SelectLayers(SCENE_LAYERS[Scene]);
    Full := Render(Session, Times[Scene]);
    CheckAlpha(Full, 255);
    SaveFrame(Names[Scene], Full);
    Check(not Same(Full, Render(Session, 0)), 'Scene did not move: ' + Names[Scene]);
    Check(Same(Full, Render(Session, Times[Scene])), 'Seek changed scene: ' + Names[Scene]);
    Base := nil;
    for Layer := Low(TTrainLayer) to High(TTrainLayer) do
      if Layer in SCENE_LAYERS[Scene] then
      begin
        SelectLayers([Layer]);
        Part := Render(SplitSession, Times[Scene]);
        if Base = nil then
        begin
          Base := Part;
          CheckAlpha(Base, 255);
        end
        else Overlay(Base, Part);
      end;
    CheckComposite(Full, Base);
    SelectLayers([]);
    CheckAlpha(Render(Session, Times[Scene]), 0);
    Writeln('Scene, seek, layer split and alpha passed: ', Names[Scene]);
  end;

  SelectScene(tsBoard);
  SelectLayers([lyBoardCabin]);
  Part := Render(Session, 0);
  Check((Part[140 * 640 + 60].A < 100) and (Part[140 * 640 + 580].A < 100) and
    (Part[140 * 640 + 320].A = 0), 'The cabin must leave the side windows and doorway open');
  SelectLayers([lyBoardDoors]);
  Ref := Render(Session, 0);
  Check((Ref[148 * 640 + 271].A < 120) and (Ref[148 * 640 + 369].A < 120) and
    (Ref[148 * 640 + 320].A = 255), 'Closed doors must have two see-through windows and a solid seam');
  CheckAlpha(Render(Session, 2), 0);
  Check(Same(Ref, Render(Session, 6)), 'Boarding door does not close');
  SetTrack(ttDoorOpen, 0);
  Check(Same(Ref, Render(Session, 2)), 'Zero opening does not disable the pair');
  SetTrack(ttDoorOpen, TRAIN_TRACKS[ttDoorOpen].Initial);
  SetTrack(ttDoorClose, 0);
  Check(Same(Ref, Render(Session, 2)), 'Zero closing does not disable the pair');
  SetTrack(ttDoorClose, TRAIN_TRACKS[ttDoorClose].Initial);
  SelectLayers(SCENE_LAYERS[tsBoard]);
  SaveFrame('boarding_closed', Render(Session, 0));
  SaveFrame('boarding_open', Render(Session, 2));
  SelectScene(tsExit);
  SelectLayers([lyExitDoors]);
  CheckAlpha(Render(Session, 2), 0);
  SelectLayers(SCENE_LAYERS[tsExit]);
  SaveFrame('exit_open', Render(Session, 2));

  SelectScene(tsArrival);
  SelectLayers([lyArrivalTrain]);
  CheckAlpha(Render(Session, 0), 0);
  CheckAlpha(Render(Session, TRAIN_TRACKS[ttArrivalBefore].Initial), 0);
  Ref := Render(Session, 8);
  // レール直上には左右の車輪があり、車軸間には線路が見える。
  I := ((WIDE_ARRIVAL_RAIL_Y - 8) div 2) * 640;
  WheelBaseX := WIDE_TRAIN_NOSE - (WIDE_CAR_LENGTH - 157) * WIDE_TRAIN_SCALE;
  Check((Ref[I + Round((WheelBaseX - 29 * WIDE_TRAIN_SCALE) / 2)].A = 255) and
    (Ref[I + Round((WheelBaseX + 29 * WIDE_TRAIN_SCALE) / 2)].A = 255) and
    (Ref[I + Round(WheelBaseX / 2)].A = 0),
    'The wheels and the gap between them must be visible at rail height');
  SetTrack(ttArrivalMove, 0);
  Check(Same(Ref, Render(Session, 0.65)), 'Zero arrival did not skip to stopped train');
  SetTrack(ttArrivalMove, TRAIN_TRACKS[ttArrivalMove].Initial);
  SelectLayers(SCENE_LAYERS[tsArrival]);
  for Style := Low(TTrainStyle) to High(TTrainStyle) do
  begin
    SetPalette(Style);
    SaveFrame('style_' + IntToStr(Ord(Style)), Render(Session, 8));
  end;
  SetPalette(trStainless);
  SelectScene(tsDeparture);
  SelectLayers(SCENE_LAYERS[tsDeparture]);
  Ref := Render(Session, 8);
  TailTime := TRAIN_TRACKS[ttDepartBefore].Initial + TRAIN_TRACKS[ttDepartMove].Initial *
    Sqrt((WIDE_CAR_COUNT * WIDE_CAR_LENGTH * WIDE_TRAIN_SCALE - WIDE_TRAIN_NOSE + 144) /
      WIDE_DEPART_DISTANCE);
  Part := Render(Session, TailTime);
  Check(not Same(Ref, Part), 'The last car is missing during departure');
  SaveFrame('departure_last_car', Part);
  Check(Same(Ref, Render(Session, TRAIN_TRACKS[ttDepartBefore].Initial +
    TRAIN_TRACKS[ttDepartMove].Initial * 0.995)), 'The tail must leave before the departure ends');
  SetTrack(ttDepartMove, 0);
  Check(Same(Ref, Render(Session, 0.85)), 'Zero departure did not skip to clear platform');
  SetTrack(ttDepartMove, TRAIN_TRACKS[ttDepartMove].Initial);

  SelectScene(tsRun);
  SelectLayers(SCENE_LAYERS[tsRun]);
  Ref := Render(Session, 4);
  for Scenery := Low(TTrainScenery) to High(TTrainScenery) do
  begin
    SetScenery(Scenery);
    Full := Render(Session, 4);
    if Scenery <> scCountryside then Check(not Same(Ref, Full), 'Scenery did not change');
    CheckAlpha(Full, 255);
    SaveFrame('scenery_' + IntToStr(Ord(Scenery)), Full);
  end;
  SetTrack(ttElevation, -1);
  Full := Render(Session, 4);
  Check(not Same(Ref, Full), 'Tunnel height did not change landscape');
  CheckAlpha(Full, 255);
  SaveFrame('tunnel', Full);
  SetTrack(ttElevation, -0.5);
  SaveFrame('tunnel_transition', Render(Session, 4));
  SetTrack(ttElevation, 2.5);
  SetTrack(ttZoom, 55);
  Full := Render(Session, 4);
  CheckAlpha(Full, 255);
  SaveFrame('elevated_zoom_out', Full);
  SetTrack(ttZoom, 145);
  SaveFrame('elevated_zoom_in', Render(Session, 4));
  SetTrack(ttWidth, 360);
  SetTrack(ttHeight, 640);
  Full := Render(Session, 4, 360, 640, 1280, 720);
  CheckAlpha(Full, 255);
  SaveFrame('portrait', Full, 360, 640);
  SetTrack(ttWidth, 0);
  SetTrack(ttHeight, 0);
  SetTrack(ttZoom, 100);
  SetTrack(ttElevation, 0);
  SetScenery(scTown);
  Render(Session, 3, 1920, 1080);
  SW := TStopwatch.StartNew;
  for I := 0 to 59 do Render(Session, 3 + I / 60, 1920, 1080);
  Writeln(Format('Running, 1080p, 60 frames: %.2f ms/frame', [SW.Elapsed.TotalMilliseconds / 60]));
end;

procedure VerifyStandeePlacement(Session: Pointer);
var
  Base, Front: TPixels;
  Scene: TTrainScene;
  procedure CaptureStandee(Rear, Fore: TTrainLayer; Time: Double; Feet, Height: Integer;
    const Name: string);
  begin
    SelectScene(Scene);
    SelectLayers([Rear]);
    Base := Render(Session, Time);
    PaintStandee(Base, 320, Feet, Height);
    SelectLayers([Fore]);
    Front := Render(Session, Time);
    Overlay(Base, Front);
    SaveFrame(Name, Base);
  end;
begin
  Scene := tsBoard;
  CaptureStandee(lyBoardPlatform, lyBoardCabin, 2, 336, 231, 'boarding_standee');
  Check(Base[329 * 640 + 310].R = $34, 'Cabin hides the boarded standee at its feet');
  Scene := tsRun;
  CaptureStandee(lyRunRear, lyRunFront, 3, 276, 146, 'running_standee');
  Check((Front[143 * 640 + 320].A < 70) and (Front[268 * 640 + 320].A = 255),
    'Running window did not preserve the passenger opening');
  Check((Front[143 * 640 + 220].A = 255) and (Front[(111 - RUN_TRAIN_RISE div 2) * 640 + 320].A = 255),
    'Running window extends beyond the revised side or top edge');
  Check(Front[121 * 640 + 320].A < 70, 'The central window must open at its raised position');
  Check((Front[(333 - RUN_TRAIN_RISE div 2) * 640 + 210].A = 255) and (Front[(RUN_RAIL_Y div 2) * 640 + 320].A = 0),
    'Running equipment must be visible under the body and clear of the rail');
  Check(Base[(RUN_RAIL_Y div 2) * 640 + 320].R >= 170,
    'The visible rail must be at the lower running position');
end;

procedure VerifySharedCarViews(Session: Pointer);
var
  Style: TTrainStyle;
  Frame, Stopped: TPixels;
  Suffix: string;
  Zoom: Integer;
begin
  for Style := Low(TTrainStyle) to High(TTrainStyle) do
  begin
    SetPalette(Style);
    Suffix := IntToStr(Ord(Style));

    SelectScene(tsRun);
    SelectLayers([lyRunFront]);
    Frame := Render(Session, 3);
    Check((Frame[141 * 640 + 320].A < 70) and (Frame[251 * 640 + 320].A = 255),
      'Passenger window is misaligned for train style ' + Suffix);
    if Style in [trStainless, trPainted] then
      Check((Frame[141 * 640 + 120].A < 110) and (Frame[141 * 640 + 175].A < 110) and
        (Frame[201 * 640 + 120].A = 255), 'Commuter door windows must show the cabin');
    SelectLayers(SCENE_LAYERS[tsRun]);
    Frame := Render(Session, 3);
    CheckAlpha(Frame, 255);
    SaveFrame('shared_running_' + Suffix, Frame);
    Stopped := Render(Session, 11);
    SaveFrame('shared_stopped_' + Suffix, Stopped);

    SelectScene(tsExit);
    SelectLayers([lyExitDoors]);
    Frame := Render(Session, 0);
    Check((Frame[222 * 640 + 484].A = 255) and (Frame[222 * 640 + 320].A = 0),
      'Exterior door leaves are misaligned for train style ' + Suffix);
    if Style in [trStainless, trPainted] then
      Check(Frame[140 * 640 + 456].A < 110, 'The same door window must remain transparent at arrival');
    CheckAlpha(Render(Session, 2), 0);
    SelectLayers(SCENE_LAYERS[tsExit]);
    Frame := Render(Session, 0);
    CheckAlpha(Frame, 255);
    SaveFrame('shared_exit_' + Suffix, Frame);
    CheckComposite(Stopped, Frame);

    for Zoom in [55, 145] do
    begin
      SetTrack(ttZoom, Zoom);
      SelectScene(tsRun);
      SelectLayers(SCENE_LAYERS[tsRun]);
      Stopped := Render(Session, 11);
      SelectScene(tsExit);
      SelectLayers(SCENE_LAYERS[tsExit]);
      CheckComposite(Stopped, Render(Session, 0));
    end;
    SetTrack(ttZoom, TRAIN_TRACKS[ttZoom].Initial);
  end;
end;

procedure VerifyPlatformViews(Session: Pointer);
var
  StartFrame, MovingFrame: TPixels;
  Tactile: TPIXEL_RGBA;
begin
  SetPalette(trStainless);
  SelectScene(tsRun);
  SelectLayers([lyRunRear]);
  StartFrame := Render(Session, 0);
  Tactile := StartFrame[154 * 640 + 320];
  Check((Tactile.R > 175) and (Tactile.G > 150) and (Tactile.B < 130),
    'The running scene must start beside a station platform');
  Check(StartFrame[4 * 640 + 320].B + 25 < StartFrame[23 * 640 + 320].B,
    'The canopy must reach the upper edge with a gap below it');
  MovingFrame := Render(Session, 6);
  Check(not Same(StartFrame, MovingFrame), 'The opening platform must pass out of view');
  Check(Same(StartFrame, Render(Session, 0)), 'Seeking must restore the opening platform');

  SelectLayers([lyRunFront]);
  StartFrame := Render(Session, 0);
  Check((StartFrame[559].A > 150) and (StartFrame[574].A > 150) and
    (StartFrame[359 * 640 + 559].A > 150) and (StartFrame[359 * 640 + 574].A > 150),
    'The foreground pole must be wide and extend through both frame edges');

  SelectLayers(SCENE_LAYERS[tsRun]);
  SaveFrame('running_platform_start', Render(Session, 0));
  SaveFrame('running_platform_leaving', Render(Session, 2.9));
  SelectScene(tsArrival);
  SelectLayers([lyArrivalPlatform]);
  StartFrame := Render(Session, 5);
  Tactile := StartFrame[338 * 640 + 320];
  Check((Tactile.R > 170) and (Tactile.G > 140) and (Tactile.B < 145),
    'The arrival platform must have a visible edge in front of the rail');
  SelectLayers(SCENE_LAYERS[tsArrival]);
  SaveFrame('arrival_near_platform', Render(Session, 5));
end;

procedure VerifyRunningArrival(Session: Pointer);
const
  LOWER_ROW = 348 * 640;
var
  Approach, Stopped, Full, Rear: TPixels;
begin
  SetPalette(trStainless);
  SelectScene(tsRun);
  SelectLayers([lyRunFront]);
  Check(Render(Session, 6)[LOWER_ROW + 320].A = 0, 'The destination platform must be clear in mid-run');
  Approach := Render(Session, 8);
  Check((Approach[LOWER_ROW + 200].A = 0) and (Approach[LOWER_ROW + 550].A = 255),
    'The destination platform must enter from the right in front of the rails');
  Check((Abs(Integer(Approach[305 * 640 + 396].R) - Approach[305 * 640 + 396].B) < 35) and
    (Approach[305 * 640 + 530].R > 175) and (Approach[305 * 640 + 530].B < 125),
    'Tactile paving must start inside the platform boundary');
  Stopped := Render(Session, 11);
  Check((Stopped[LOWER_ROW + 80].A = 255) and (Stopped[LOWER_ROW + 570].A = 255),
    'The foreground platform must span the frame at the stop');
  Check(Same(Approach, Render(Session, 8)), 'Seeking must restore the approaching platform');

  SelectLayers(SCENE_LAYERS[tsRun]);
  SaveFrame('running_arrival_entering', Render(Session, 8));
  Full := Render(Session, 11);
  Check(Same(Full, Render(Session, 20)), 'The destination platform must remain at the stop');
  SaveFrame('running_arrival_stopped', Full);
  SelectLayers([lyRunRear]);
  Rear := Render(Session, 11);
  Overlay(Rear, Stopped);
  CheckComposite(Full, Rear);
end;

procedure VerifySynchronizedDoors(Session: Pointer);
const
  LOWER_DOOR_ROW = 222 * 640;
var
  Closed, HalfOpen, HalfClosed, Wide: TPixels;
  OpeningMiddle, ClosingMiddle: Double;
begin
  SetPalette(trStainless);
  SelectScene(tsExit);
  SelectLayers([lyExitDoors]);
  OpeningMiddle := TRAIN_TRACKS[ttExitBefore].Initial + TRAIN_TRACKS[ttExitOpen].Initial * 0.5;
  ClosingMiddle := TRAIN_TRACKS[ttExitBefore].Initial + TRAIN_TRACKS[ttExitOpen].Initial +
    TRAIN_TRACKS[ttExitHold].Initial + TRAIN_TRACKS[ttExitClose].Initial * 0.5;
  Closed := Render(Session, 0);
  Check((Closed[LOWER_DOOR_ROW + 148].A = 255) and (Closed[LOWER_DOOR_ROW + 470].A = 255),
    'Both visible doors must start closed on the door layer');
  HalfOpen := Render(Session, OpeningMiddle);
  Check((HalfOpen[LOWER_DOOR_ROW + 148].A = 0) and (HalfOpen[LOWER_DOOR_ROW + 483].A = 0) and
    (HalfOpen[LOWER_DOOR_ROW + 100].A = 255) and (HalfOpen[LOWER_DOOR_ROW + 437].A = 255),
    'Both doors must open in sync and keep visible leaves during the slide');
  CheckAlpha(Render(Session, 2), 0);
  HalfClosed := Render(Session, ClosingMiddle);
  Check(Same(HalfOpen, HalfClosed), 'Both doors must close in sync');
  Check(Same(Closed, Render(Session, 8)), 'All doors must return to the closed frame');
  SelectLayers(SCENE_LAYERS[tsExit]);
  SaveFrame('exit_doors_half', Render(Session, OpeningMiddle));

  SetTrack(ttZoom, 55);
  SelectLayers([lyExitDoors]);
  Wide := Render(Session, 0);
  Check((Wide[LOWER_DOOR_ROW + 35].A = 255) and (Wide[LOWER_DOOR_ROW + 220].A = 255) and
    (Wide[LOWER_DOOR_ROW + 410].A = 255) and (Wide[LOWER_DOOR_ROW + 632].A = 255),
    'Every visible door, including the adjacent car, must have moving leaves');
  CheckAlpha(Render(Session, 2), 0);
  SelectLayers(SCENE_LAYERS[tsExit]);
  SaveFrame('exit_wide_open', Render(Session, 2));
  SetTrack(ttZoom, TRAIN_TRACKS[ttZoom].Initial);
end;

procedure VerifyExpressWindows(Session: Pointer);
const
  DOOR_ROW = 212 * 640;
  WINDOW_ROW = 160 * 640;
  CORNER_ROW = 136 * 640;
var
  Style: TTrainStyle;
  Frame: TPixels;
  LeftDoor, RightDoor, Count, X, Y, I, Width, Gap, OuterWindow: Integer;
  FirstPixel, LastPixel: array[0..2] of Integer;
  SeatTop, SeatPixels: array[0..1] of Integer;
  SeatX: array[0..1] of Integer;
  P: TPIXEL_RGBA;
begin
  SetTrack(ttZoom, 65);
  for Style := trExpress to trStreamlined do
  begin
    SetPalette(Style);
    SelectScene(tsExit);
    SelectLayers([lyExitDoors]);
    Frame := Render(Session, 0);
    LeftDoor := 320;
    while (LeftDoor > 0) and (Frame[DOOR_ROW + LeftDoor].A < 200) do Dec(LeftDoor);
    RightDoor := 320;
    while (RightDoor < 639) and (Frame[DOOR_ROW + RightDoor].A < 200) do Inc(RightDoor);
    Check((LeftDoor > 0) and (RightDoor < 639), 'The express window test must see both doors');

    SelectScene(tsRun);
    SelectLayers([lyRunFront]);
    Frame := Render(Session, 3);
    Count := 0;
    X := LeftDoor + 1;
    while X < RightDoor do
    begin
      if Frame[WINDOW_ROW + X].A >= 140 then
      begin
        Inc(X);
        Continue;
      end;
      Check(Count < Length(FirstPixel), 'Too many express windows between the doors');
      FirstPixel[Count] := X;
      repeat
        Inc(X);
      until (X >= RightDoor) or (Frame[WINDOW_ROW + X].A >= 140);
      LastPixel[Count] := X - 1;
      Inc(Count);
    end;
    Check(Count = Length(FirstPixel), 'The two express doors must enclose three windows');
    Width := LastPixel[0] - FirstPixel[0] + 1;
    Gap := FirstPixel[1] - LastPixel[0] - 1;
    for I := Low(FirstPixel) to High(FirstPixel) do
    begin
      Check(Abs(LastPixel[I] - FirstPixel[I] + 1 - Width) <= 1,
        'The express windows must have equal widths');
      Check((Frame[CORNER_ROW + FirstPixel[I]].A < 110) and
        (Frame[CORNER_ROW + LastPixel[I]].A < 110), 'The express windows must have square corners');
    end;
    Check((Abs(FirstPixel[2] - LastPixel[1] - 1 - Gap) <= 1) and
      (Abs(FirstPixel[0] - LeftDoor - 1 - Gap) <= 3) and
      (Abs(RightDoor - LastPixel[2] - 1 - Gap) <= 3),
      'The express window gaps must match each other and the margins at both doors');

    OuterWindow := RightDoor + 1;
    while (OuterWindow < 639) and (Frame[WINDOW_ROW + OuterWindow].A >= 140) do Inc(OuterWindow);
    X := OuterWindow;
    while (X < 639) and (Frame[WINDOW_ROW + X].A < 140) do Inc(X);
    Check(Abs(X - OuterWindow - Width) <= 1,
      'The passenger window beyond the right door must use the full window width');

    SelectLayers(SCENE_LAYERS[tsRun]);
    Frame := Render(Session, 3);
    SaveFrame('express_' + IntToStr(Ord(Style)) + '_window_layout', Frame);
    SeatX[0] := FirstPixel[0] - 1;
    SeatX[1] := OuterWindow - 1;
    for I := Low(SeatX) to High(SeatX) do
    begin
      SeatTop[I] := 360;
      SeatPixels[I] := 0;
      for Y := 148 to 176 do
        for X := SeatX[I] to SeatX[I] + 18 do
        begin
          P := Frame[Y * 640 + X];
          if (P.R > P.G + 27) and (P.B > P.G + 6) then
          begin
            SeatTop[I] := Min(SeatTop[I], Y);
            Inc(SeatPixels[I]);
          end;
        end;
    end;
    Check((SeatTop[0] >= 162) and (Abs(SeatTop[0] - SeatTop[1]) <= 1) and
      (SeatPixels[0] > 75) and (Abs(SeatPixels[0] - SeatPixels[1]) <= 12),
      'The outer and central express seats must have the same size and lowered height');

    SetTrack(ttZoom, TRAIN_TRACKS[ttZoom].Initial);
    SelectLayers([lyRunFront]);
    Frame := Render(Session, 3);
    Check(Frame[143 * 640 + 638].A < 140, 'The right window must extend beyond the default view');
    SetTrack(ttZoom, 65);
  end;
  SetTrack(ttZoom, TRAIN_TRACKS[ttZoom].Initial);
end;

procedure VerifyStationScenery(Session, SplitSession: Pointer);
const
  StationLayers: array[TTrainScene] of TTrainLayer =
    (lyArrivalPlatform, lyBoardPlatform, lyRunRear, lyExitRear, lyDeparture);
  SceneryOrder: array[0..3] of TTrainScenery = (scTown, scResidential, scCountryside, scCoast);
  SceneryLabels: array[0..3] of string = ('ビル街', '住宅街', '田園', '海岸');
  ARRIVAL_TIME = 8;
var
  Scene: TTrainScene;
  Scenery: TTrainScenery;
  Selector: PFILTER_ITEM_SELECT;
  Base, Background, Earlier, Foreground, Full: TPixels;
  I: Integer;
begin
  Selector := PFILTER_ITEM_SELECT(FindItem('背景の種類', 'select'));
  for I := Low(SceneryOrder) to High(SceneryOrder) do
  begin
    Check(string(Selector^.List[I].Name) = SceneryLabels[I], 'Incorrect scenery menu order');
    Check(Selector^.List[I].Value = Ord(SceneryOrder[I]), 'Scenery IDs must remain stable');
  end;
  Check(Selector^.List[Length(SceneryOrder)].Name = nil, 'Scenery options must be terminated');

  SetPalette(trStainless);
  for Scene in [tsArrival, tsBoard, tsDeparture] do
  begin
    SelectScene(Scene);
    SelectLayers([StationLayers[Scene]]);
    SetScenery(scCountryside);
    Base := Render(Session, ARRIVAL_TIME);
    Earlier := Base;
    for Scenery in [scTown, scCoast, scResidential] do
    begin
      SetScenery(Scenery);
      SetTrack(ttSeed, TRAIN_TRACKS[ttSeed].Initial);
      Background := Render(Session, ARRIVAL_TIME);
      CheckAlpha(Background, 255);
      Check(not Same(Background, Base) and not Same(Background, Earlier),
        'The station backdrop must change when scenery is selected');

      SetTrack(ttSeed, 92);
      Check(not Same(Background, Render(Session, ARRIVAL_TIME)),
        'Changing the scenery seed must refresh the station backdrop');
      SetTrack(ttSeed, TRAIN_TRACKS[ttSeed].Initial);
      Check(Same(Background, Render(Session, ARRIVAL_TIME)), 'Station scenery must be reproducible');
      Earlier := Background;

      if (Scene = tsArrival) and (Scenery in [scTown, scResidential]) then
      begin
        SelectLayers([lyArrivalTrain]);
        Foreground := Render(SplitSession, ARRIVAL_TIME);
        SelectLayers(SCENE_LAYERS[tsArrival]);
        Full := Render(Session, ARRIVAL_TIME);
        SaveFrame('arrival_scenery_' + IntToStr(Ord(Scenery)), Full);
        Background := Copy(Background);
        Overlay(Background, Foreground);
        CheckComposite(Full, Background);
        SelectLayers([lyArrivalPlatform]);
      end;
    end;
    SetScenery(scCountryside);
    Check(Same(Base, Render(Session, ARRIVAL_TIME)), 'Returning to countryside must restore its backdrop');
  end;

  SetScenery(scResidential);
  SelectScene(tsRun);
  SelectLayers(SCENE_LAYERS[tsRun]);
  Full := Render(Session, 11);
  SelectScene(tsExit);
  SelectLayers(SCENE_LAYERS[tsExit]);
  CheckComposite(Full, Render(Session, 0));
  SetScenery(scCountryside);
end;

procedure VerifyStationHeight(Session: Pointer);
const
  Times: array[TTrainScene] of Double = (8, 2, 11, 2, 1.55);
  Names: array[TTrainScene] of string = ('arrival', 'boarding', 'running', 'exit', 'departure');
var
  Scene: TTrainScene;
  Ground, Elevated, Transition, Underground, Stopped, Tunnel, Start: TPixels;
begin
  SetPalette(trStainless);
  for Scene := Low(TTrainScene) to High(TTrainScene) do
  begin
    SelectScene(Scene);
    SelectLayers(SCENE_LAYERS[Scene]);
    SetScenery(scTown);
    SetTrack(ttElevation, 0);
    Ground := Render(Session, Times[Scene]);
    SetTrack(ttElevation, 2.5);
    Elevated := Render(Session, Times[Scene]);
    CheckAlpha(Elevated, 255);
    Check(not Same(Ground, Elevated), 'Elevated scenery must affect ' + Names[Scene]);

    SetTrack(ttElevation, -0.5);
    Transition := Render(Session, Times[Scene]);
    CheckAlpha(Transition, 255);
    SetTrack(ttElevation, -1);
    Underground := Render(Session, Times[Scene]);
    CheckAlpha(Underground, 255);
    Check(not Same(Ground, Transition) and not Same(Transition, Underground),
      'Station height must support a transition to underground in ' + Names[Scene]);
    SetScenery(scCoast);
    Check(Same(Underground, Render(Session, Times[Scene])),
      'Outdoor scenery must be hidden in the underground station');
    SaveFrame('underground_' + Names[Scene], Underground);

    if Scene = tsRun then
    begin
      Stopped := Underground;
      SaveFrame('underground_tunnel', Render(Session, 4));
      SelectLayers([lyRunRear]);
      Tunnel := Render(Session, 4);
      Start := Render(Session, 0);
      Check(Start[100 * 640 + 100].R > Tunnel[100 * 640 + 100].R + 60,
        'The underground starting platform must show a station wall before the tunnel');
      SelectLayers(SCENE_LAYERS[Scene]);
    end;
    if Scene = tsExit then
      CheckComposite(Stopped, Render(Session, 0));

    SetScenery(scTown);
    SetTrack(ttElevation, 0);
    Check(Same(Ground, Render(Session, Times[Scene])), 'Restoring height must restore station scenery');
  end;
end;

procedure VerifyCommuterBoarding(Session: Pointer);
var
  Platform, Cabin: TPixels;
  Style: TTrainStyle;
  Y: Integer;
  function IsGold(const P: TPIXEL_RGBA): Boolean;
  begin
    Result := (P.R > P.G) and (P.G > P.B + 38);
  end;
begin
  SelectScene(tsBoard);
  SetTrack(ttElevation, -1);
  SelectLayers([lyBoardPlatform]);
  SetPalette(trStainless);
  Platform := Render(Session, 2);
  for Y in [337, 352] do
  begin
    Check(Platform[Y * 640 + 237].R > Platform[Y * 640 + 225].R + 25,
      'The left edge of the boarding mat must stay vertical');
    Check(Platform[Y * 640 + 403].R > Platform[Y * 640 + 415].R + 25,
      'The right edge of the boarding mat must stay vertical');
  end;
  SetPalette(trExpress);
  Check(Same(Platform, Render(Session, 2)), 'Boarding floor geometry must be shared');

  for Style in [trStainless, trPainted] do
  begin
    SetPalette(Style);
    SelectLayers([lyBoardCabin]);
    Cabin := Render(Session, 2);
    for Y in [179, 226, 318] do
    begin
      Check((Cabin[Y * 640 + 180].R < 100) and (Cabin[Y * 640 + 186].R > 140) and
        (Cabin[Y * 640 + 200].R < 100), 'The left seat partition must be a straight upright');
      Check((Cabin[Y * 640 + 459].R < 100) and (Cabin[Y * 640 + 453].R > 140) and
        (Cabin[Y * 640 + 439].R < 100), 'The right seat partition must be a straight upright');
    end;

    for Y := 82 to 241 do
      Check(IsGold(Cabin[Y * 640 + 116]) and IsGold(Cabin[Y * 640 + 523]),
        'The tall yellow poles must follow the same axis');
    for Y in [257, 290, 321] do
      Check((Cabin[Y * 640 + 116].R > 150) and (Cabin[Y * 640 + 523].R > 150),
        'The tall pole bases must continue vertically to the floor');
    for Y := 167 to 247 do
      Check(IsGold(Cabin[Y * 640 + 217]) and IsGold(Cabin[Y * 640 + 422]),
        'The short yellow handles must stay straight up to their mounts');
    Check(Cabin[249 * 640 + 320].A = 0, 'The cabin must leave the doorway clear');
  end;

  SetPalette(trStainless);
  SelectLayers(SCENE_LAYERS[tsBoard]);
  SaveFrame('underground_boarding_closed', Render(Session, 0));
  SetTrack(ttElevation, TRAIN_TRACKS[ttElevation].Initial);
end;

procedure VerifyExpressInterior(Session: Pointer);
const
  Times: array[TTrainScene] of Double = (8, 2, 3, 2, 1.55);
  Names: array[TTrainScene] of string = ('arrival', 'boarding', 'running', 'exit', 'departure');
  SidePanelCenters: array[0..3] of Integer = (12, 172, 502, 636);
var
  Style: TTrainStyle;
  Scene: TTrainScene;
  Frame, Cabin: TPixels;
  SeatPixels, X, Y: Integer;
  P, Shelf: TPIXEL_RGBA;
begin

  for Style := trExpress to trStreamlined do
  begin
    SetPalette(Style);
    for Scene := Low(TTrainScene) to High(TTrainScene) do
    begin
      SelectScene(Scene);
      SelectLayers(SCENE_LAYERS[Scene]);
      Frame := Render(Session, Times[Scene]);
      CheckAlpha(Frame, 255);
      if Scene = tsDeparture then
        Check(not Same(Frame, Render(Session, 8)), 'The express must be visible during departure');
      SaveFrame('express_' + IntToStr(Ord(Style)) + '_' + Names[Scene], Frame);
      if Scene <> tsBoard then Continue;
      Check((Frame[34 * 640 + 22].B > 170) and (Frame[43 * 640 + 319].B > 170),
        'Express boarding must omit hand straps and the overhead display');
      Check(Frame[65 * 640 + 100].R < 145, 'The express luggage shelf must show a front edge');
      for Y := 53 to 66 do
      begin
        Shelf := Frame[Y * 640 + 100];
        for X := 22 to 180 do
          Check((Abs(Frame[Y * 640 + X].B - Shelf.B) <= 1) and
            (Abs(Frame[Y * 640 + 639 - X].B - Shelf.B) <= 1),
            'The two express luggage shelves must have continuous horizontal faces');
      end;
      SeatPixels := 0;
      for Y := 206 to 302 do
        for X := 68 to 150 do
        begin
          P := Frame[Y * 640 + X];
          if P.B > P.R + 24 then Inc(SeatPixels);
        end;
      Check(SeatPixels > 900, 'The express cabin must show upholstered reclining seats');
      for X in SidePanelCenters do
      begin
        P := Frame[331 * 640 + X];
        Check((P.B > P.R + 45) and (P.R < 100), 'Each express seat must have a side panel below the armrest');
      end;

      SelectLayers([lyBoardCabin]);
      Cabin := Render(Session, Times[Scene]);
      for Y := 82 to 348 do
        for X := 244 to 395 do
          Check(Cabin[Y * 640 + X].A = 0, 'Express seating must leave the boarding doorway clear');
    end;
  end;
end;

procedure Run;
var
  Module: HMODULE;
  Required: TRequired;
  Initialize: TInitialize;
  Uninitialize: TUninitialize;
  GetTable: TGetTable;
  Session, SplitSession: Pointer;
begin
  Check(ParamCount > 0, 'Pass the built AUF2 path.');
  if ParamCount > 1 then
  begin
    ImageDir := ParamStr(2);
    ForceDirectories(ImageDir);
  end;
  Module := LoadLibrary(PWideChar(ExpandFileName(ParamStr(1))));
  if Module = 0 then RaiseLastOSError;
  try
    Required := GetProcAddress(Module, 'RequiredVersion');
    Initialize := GetProcAddress(Module, 'InitializePlugin');
    Uninitialize := GetProcAddress(Module, 'UninitializePlugin');
    GetTable := GetProcAddress(Module, 'GetFilterPluginTable');
    Check(Assigned(Required) and Assigned(Initialize) and Assigned(Uninitialize) and
      Assigned(GetTable), 'Required export missing');
    Check((Required() = 2011600) and (Initialize(2011599) = 0) and
      (Initialize(2011600) = 1), 'Minimum host version mismatch');
    Table := GetTable();
    Check((Table <> nil) and (string(Table^.Name) = '旅行列車') and
      (string(Table^.Label_) = 'SYNC'), 'Registration name mismatch');
    Check(Table^.Flag = (FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA),
      'Media object flags mismatch');
    VerifyPresets;
    VerifyTimeline;
    Session := Table^.Func_Create(1);
    SplitSession := Table^.Func_Create(2);
    try
      Check((Session <> nil) and (SplitSession <> nil), 'Could not allocate instances');
      VerifyImages(Session, SplitSession);
      VerifyStandeePlacement(Session);
      VerifySharedCarViews(Session);
      VerifySynchronizedDoors(Session);
      VerifyExpressWindows(Session);
      VerifyExpressInterior(Session);
      VerifyPlatformViews(Session);
      VerifyRunningArrival(Session);
      VerifyStationScenery(Session, SplitSession);
      VerifyStationHeight(Session);
      VerifyCommuterBoarding(Session);
    finally
      Table^.Func_Destroy(2, SplitSession);
      Table^.Func_Destroy(1, Session);
    end;
    Uninitialize;
  finally
    FreeLibrary(Module);
  end;
end;

begin
  SetConsoleOutputCP(CP_UTF8);
  try
    Run;
    Writeln('All TravelTrain checks passed.');
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

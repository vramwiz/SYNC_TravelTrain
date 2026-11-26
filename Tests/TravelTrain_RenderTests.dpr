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
  for T := ttRunBefore to ttRunAfter do S.Tracks[T] := 0;
  Check(EvaluateTrainFrame(S, 20).Distance = 0, 'Zero stages must have no displacement');
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

  SelectScene(tsRun);
  SelectLayers(SCENE_LAYERS[tsRun]);
  Ref := Render(Session, 4);
  for Scenery := Low(TTrainScenery) to High(TTrainScenery) do
  begin
    PFILTER_ITEM_SELECT(FindItem('背景の種類', 'select'))^.Value := Ord(Scenery);
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
  PFILTER_ITEM_SELECT(FindItem('背景の種類', 'select'))^.Value := Ord(scTown);
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
  Check(Front[115 * 640 + 320].A < 70, 'The central window must open at its raised position');
  Check((Front[(333 - RUN_TRAIN_RISE div 2) * 640 + 210].A = 255) and (Front[(RUN_RAIL_Y div 2) * 640 + 320].A = 0),
    'Running equipment must be visible under the body and clear of the rail');
  Check(Base[(RUN_RAIL_Y div 2) * 640 + 320].R >= 170,
    'The visible rail must be at the lower running position');
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

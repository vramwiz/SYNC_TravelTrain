unit TravelTrain_Timeline;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// オブジェクト内の秒位置から列車・扉・走行風景の状態を直接計算する。

interface

uses TravelTrain_Settings;

type
  TTrainFrame = record
    TrainVisible: Boolean;
    TrainX: Single;
    DoorOpen: Single;
    Distance: Double;
  end;

// レイヤーや前フレームに依存しない。工程完了後は終端の構図を保持する。
function EvaluateTrainFrame(const S: TTrainSettings; Seconds: Double): TTrainFrame;

implementation

uses System.Math;

function Progress(Elapsed, Duration: Double): Double;
begin
  if Duration = 0 then Exit(1);
  Result := EnsureRange(Elapsed / Duration, 0.0, 1.0);
end;

function Ease(Value: Double): Double;
begin
  Result := Sqr(Value) * (3 - 2 * Value);
end;

function DoorAt(Seconds, Before, Opening, Holding, Closing, After: Double): Single;
var
  Elapsed: Double;
begin
  Result := 0;
  if (Opening = 0) or (Closing = 0) then Exit;
  Elapsed := EnsureRange(Seconds - Before, 0.0, Opening + Holding + Closing + After);
  if Elapsed < Opening then Exit(Ease(Progress(Elapsed, Opening)));
  if Elapsed < Opening + Holding then Exit(1);
  Result := 1 - Ease(Progress(Elapsed - Opening - Holding, Closing));
end;

function DistanceAt(const T: TTrainTracks; Seconds: Double): Double;
var
  Elapsed, Accel, Cruise, Brake, Part, Distance: Double;
begin
  Accel := T[ttRunAccelerate];
  Cruise := T[ttRunCruise];
  Brake := T[ttRunBrake];
  Elapsed := EnsureRange(Seconds - T[ttRunBefore], 0.0, Accel + Cruise + Brake + T[ttRunAfter]);
  Distance := 0;
  if Accel > 0 then
  begin
    Part := Min(Elapsed, Accel);
    Distance := 0.5 * Part * (Part / Accel);
  end;
  Elapsed := Max(0.0, Elapsed - Accel);
  Distance := Distance + Min(Elapsed, Cruise);
  if Brake > 0 then
  begin
    Part := EnsureRange(Elapsed - Cruise, 0.0, Brake);
    Distance := Distance + Part * (1 - 0.5 * Part / Brake);
  end;
  Result := Distance * T[ttSpeed];
end;

function EvaluateTrainFrame(const S: TTrainSettings; Seconds: Double): TTrainFrame;
var
  Elapsed, P: Double;
begin
  Result := Default(TTrainFrame);
  if IsNan(Seconds) or IsInfinite(Seconds) or (Seconds < 0) then Seconds := 0;
  case S.Scene of
    tsArrival:
      begin
        Elapsed := Min(Seconds - S.Tracks[ttArrivalBefore],
          S.Tracks[ttArrivalMove] + S.Tracks[ttArrivalAfter]);
        Result.TrainVisible := Elapsed >= 0;
        P := Progress(Elapsed, S.Tracks[ttArrivalMove]);
        Result.TrainX := -(WIDE_TRAIN_NOSE + 48) * Sqr(1 - P);
      end;
    tsBoard: Result.DoorOpen := DoorAt(Seconds, S.Tracks[ttDoorBefore], S.Tracks[ttDoorOpen],
      S.Tracks[ttDoorHold], S.Tracks[ttDoorClose], S.Tracks[ttDoorAfter]);
    tsExit: Result.DoorOpen := DoorAt(Seconds, S.Tracks[ttExitBefore], S.Tracks[ttExitOpen],
      S.Tracks[ttExitHold], S.Tracks[ttExitClose], S.Tracks[ttExitAfter]);
    tsRun: Result.Distance := DistanceAt(S.Tracks, Seconds);
    tsDeparture:
      begin
        Elapsed := Min(Seconds - S.Tracks[ttDepartBefore],
          S.Tracks[ttDepartMove] + S.Tracks[ttDepartAfter]);
        P := Progress(Elapsed, S.Tracks[ttDepartMove]);
        Result.TrainVisible := (Elapsed < 0) or (P < 1);
        if Elapsed >= 0 then
          Result.TrainX := WIDE_DEPART_DISTANCE * Sqr(P);
      end;
  end;
end;

end.

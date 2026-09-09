// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speed_test_result.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SpeedTestResultAdapter extends TypeAdapter<SpeedTestResult> {
  @override
  final int typeId = 0;

  @override
  SpeedTestResult read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SpeedTestResult(
      id: fields[0] as String?,
      timestamp: fields[1] as DateTime?,
      downloadSpeed: fields[2] as double,
      uploadSpeed: fields[3] as double,
      ping: fields[4] as double,
      jitter: fields[5] as double,
      server: fields[6] as String,
      clientIp: fields[7] as String?,
      networkType: fields[8] as String?,
      operator: fields[9] as String?,
      latitude: fields[10] as double?,
      longitude: fields[11] as double?,
      location: fields[12] as String?,
      deviceModel: fields[13] as String?,
      osVersion: fields[14] as String?,
      imagePath: fields[16] as String?,
      testLog: fields[17] as String?,
      isUploaded: fields[18] as bool,
      qoeRating: fields[19] as int?,
      qoeUsage: fields[20] as String?,
      qoeSatisfaction: fields[21] as String?,
      streamingStartupMs: fields[22] as int?,
      streamingRebufferCount: fields[23] as int?,
      streamingRebufferRatio: fields[24] as double?,
      streamingMaxResolution: fields[25] as String?,
      streamingScore: fields[26] as double?,
      browsingAvgLoadMs: fields[27] as double?,
      browsingSuccessRate: fields[28] as double?,
      browsingPagesTested: fields[29] as int?,
      browsingScore: fields[30] as double?,
      simOperator: fields[31] as String?,
      cellularTech: fields[32] as String?,
      streamingQualitiesJson: fields[33] as String?,
      dataUsedKiB: fields[34] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, SpeedTestResult obj) {
    writer
      ..writeByte(34)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.downloadSpeed)
      ..writeByte(3)
      ..write(obj.uploadSpeed)
      ..writeByte(4)
      ..write(obj.ping)
      ..writeByte(5)
      ..write(obj.jitter)
      ..writeByte(6)
      ..write(obj.server)
      ..writeByte(7)
      ..write(obj.clientIp)
      ..writeByte(8)
      ..write(obj.networkType)
      ..writeByte(9)
      ..write(obj.operator)
      ..writeByte(10)
      ..write(obj.latitude)
      ..writeByte(11)
      ..write(obj.longitude)
      ..writeByte(12)
      ..write(obj.location)
      ..writeByte(13)
      ..write(obj.deviceModel)
      ..writeByte(14)
      ..write(obj.osVersion)
      ..writeByte(16)
      ..write(obj.imagePath)
      ..writeByte(17)
      ..write(obj.testLog)
      ..writeByte(18)
      ..write(obj.isUploaded)
      ..writeByte(19)
      ..write(obj.qoeRating)
      ..writeByte(20)
      ..write(obj.qoeUsage)
      ..writeByte(21)
      ..write(obj.qoeSatisfaction)
      ..writeByte(22)
      ..write(obj.streamingStartupMs)
      ..writeByte(23)
      ..write(obj.streamingRebufferCount)
      ..writeByte(24)
      ..write(obj.streamingRebufferRatio)
      ..writeByte(25)
      ..write(obj.streamingMaxResolution)
      ..writeByte(26)
      ..write(obj.streamingScore)
      ..writeByte(27)
      ..write(obj.browsingAvgLoadMs)
      ..writeByte(28)
      ..write(obj.browsingSuccessRate)
      ..writeByte(29)
      ..write(obj.browsingPagesTested)
      ..writeByte(30)
      ..write(obj.browsingScore)
      ..writeByte(31)
      ..write(obj.simOperator)
      ..writeByte(32)
      ..write(obj.cellularTech)
      ..writeByte(33)
      ..write(obj.streamingQualitiesJson)
      ..writeByte(34)
      ..write(obj.dataUsedKiB);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedTestResultAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

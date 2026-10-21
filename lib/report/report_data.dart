import '../core/models.dart';

/// One table cell of the report; [swatch] draws the colour key of that IMU in front of the text.
class Cell {
  const Cell(this.text, [this.tone = Tone.none, this.swatch]);
  final String text;
  final Tone tone;
  final int? swatch;
}

class ReportTable {
  const ReportTable(this.title, this.headers, this.rows, {this.note = '', this.empty = 'No data.', this.flex});
  final String title;
  final List<String> headers;
  final List<List<Cell>> rows;
  final String note;

  /// Shown instead of the table when there are no rows.
  final String empty;

  /// Relative column widths; equal to the content when null.
  final List<double>? flex;
}

enum Verdict { pass, fail, incomplete }

class ImuSeries {
  const ImuSeries(this.label, this.accel, this.gyro);
  final String label;
  final List<ImuSample> accel;
  final List<ImuSample> gyro;
}

/// Snapshot of everything the PDF report shows, taken when the IMU recording ends.
class ReportData {
  const ReportData({
    required this.operator,
    required this.boardId,
    required this.notes,
    required this.when,
    required this.firmware,
    required this.uid,
    required this.passed,
    required this.failed,
    required this.total,
    required this.sensorCount,
    required this.imuCount,
    required this.boardInfo,
    required this.resources,
    required this.sensors,
    required this.imuSeries,
    required this.imuStats,
    required this.serialPorts,
    required this.onboard,
    required this.tests,
    required this.changedParams,
    required this.errors,
    required this.log,
  });

  final String operator;
  final String boardId;
  final String notes;
  final DateTime when;
  final String firmware;
  final String uid;
  final int passed;
  final int failed;
  final int total;
  final int sensorCount;
  final int imuCount;
  final List<(String, String)> boardInfo;
  final ReportTable resources;
  final ReportTable sensors;
  final List<ImuSeries> imuSeries;
  final ReportTable imuStats;
  final ReportTable serialPorts;
  final ReportTable onboard;
  final ReportTable tests;
  final ReportTable changedParams;
  final ReportTable errors;
  final ReportTable log;

  Verdict get verdict => failed > 0 ? Verdict.fail : (passed == total ? Verdict.pass : Verdict.incomplete);
  int get notTested => total - passed - failed;
}

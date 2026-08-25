import '../models/activity_model.dart';

import '../core/services/log_service.dart';



class LogRepository {

  final LogService _logService =
      LogService();



  Future<void> createLog(

    ActivityModel activity,

  ) async {


    await _logService.createLog(

      activity,

    );

  }



  Stream<List<ActivityModel>> getLogs() {

    return _logService.getLogs();

  }



  Future<void> deleteLog(

    String id,

  ) async {


    await _logService.deleteLog(

      id,

    );

  }

}
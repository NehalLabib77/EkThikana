import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';

@immutable
class PlannedCommuteTrip {
  const PlannedCommuteTrip({
    required this.id,
    required this.ownerId,
    required this.originName,
    required this.destinationName,
    this.originLat,
    this.originLon,
    this.destinationLat,
    this.destinationLon,
    required this.departureTime,
    required this.reminderMinutes,
    this.createdAt,
  });

  final String id;
  final String ownerId;
  final String originName;
  final String destinationName;
  final double? originLat;
  final double? originLon;
  final double? destinationLat;
  final double? destinationLon;
  final DateTime departureTime;

  /// Reminder in minutes before departure: e.g. 10, 30, 60. 0 means no reminder.
  final int reminderMinutes;
  final DateTime? createdAt;

  DateTime? get reminderTime {
    if (reminderMinutes <= 0) return null;
    return departureTime.subtract(Duration(minutes: reminderMinutes));
  }

  bool get isUpcoming => departureTime.isAfter(DateTime.now());

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'originName': originName,
      'destinationName': destinationName,
      'originLat': originLat,
      'originLon': originLon,
      'destinationLat': destinationLat,
      'destinationLon': destinationLon,
      'departureTime': Timestamp.fromDate(departureTime),
      'reminderMinutes': reminderMinutes,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  static PlannedCommuteTrip fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final departureTimestamp = data['departureTime'] as Timestamp?;
    final createdTimestamp = data['createdAt'] as Timestamp?;

    return PlannedCommuteTrip(
      id: doc.id,
      ownerId: data['ownerId']?.toString() ?? '',
      originName: data['originName']?.toString() ?? '',
      destinationName: data['destinationName']?.toString() ?? '',
      originLat: (data['originLat'] as num?)?.toDouble(),
      originLon: (data['originLon'] as num?)?.toDouble(),
      destinationLat: (data['destinationLat'] as num?)?.toDouble(),
      destinationLon: (data['destinationLon'] as num?)?.toDouble(),
      departureTime: departureTimestamp?.toDate() ?? DateTime.now(),
      reminderMinutes: (data['reminderMinutes'] as num?)?.toInt() ?? 0,
      createdAt: createdTimestamp?.toDate(),
    );
  }
}

class CommuteTripService {
  CommuteTripService._();

  static const String collection = 'planned_commute_trips';

  static Stream<List<PlannedCommuteTrip>> streamPlannedTrips() {
    return FirestoreService.ownerStream(collection).map((snapshot) {
      final trips = snapshot.docs
          .map((doc) => PlannedCommuteTrip.fromDoc(doc))
          .toList();
      trips.sort((a, b) => a.departureTime.compareTo(b.departureTime));
      return trips;
    });
  }

  static Future<String> createTrip({
    required String originName,
    required String destinationName,
    double? originLat,
    double? originLon,
    double? destinationLat,
    double? destinationLon,
    required DateTime departureTime,
    required int reminderMinutes,
  }) async {
    final ref = await FirestoreService.addOwnerRecord(collection, {
      'originName': originName,
      'destinationName': destinationName,
      'originLat': originLat,
      'originLon': originLon,
      'destinationLat': destinationLat,
      'destinationLon': destinationLon,
      'departureTime': Timestamp.fromDate(departureTime),
      'reminderMinutes': reminderMinutes,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (reminderMinutes > 0) {
      final notifyAt = departureTime.subtract(Duration(minutes: reminderMinutes));
      if (notifyAt.isAfter(DateTime.now())) {
        await NotificationService.scheduleCommuteTripReminder(
          tripId: ref.id,
          title: 'Trip to $destinationName in $reminderMinutes mins',
          when: notifyAt,
        );
      }
    }

    return ref.id;
  }

  static Future<void> updateTrip({
    required String tripId,
    required String originName,
    required String destinationName,
    double? originLat,
    double? originLon,
    double? destinationLat,
    double? destinationLon,
    required DateTime departureTime,
    required int reminderMinutes,
  }) async {
    await FirestoreService.db.collection(collection).doc(tripId).update({
      'originName': originName,
      'destinationName': destinationName,
      'originLat': originLat,
      'originLon': originLon,
      'destinationLat': destinationLat,
      'destinationLon': destinationLon,
      'departureTime': Timestamp.fromDate(departureTime),
      'reminderMinutes': reminderMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final notifyAt = reminderMinutes > 0
        ? departureTime.subtract(Duration(minutes: reminderMinutes))
        : null;

    await NotificationService.rescheduleCommuteTripReminder(
      tripId: tripId,
      title: 'Trip to $destinationName in $reminderMinutes mins',
      when: notifyAt,
    );
  }

  static Future<void> deleteTrip(PlannedCommuteTrip trip) async {
    await NotificationService.cancelCommuteTripReminder(trip.id);
    await FirestoreService.deleteOwnerDocument(collection, trip.id);
  }

  static Future<void> deleteTripById(String tripId) async {
    await NotificationService.cancelCommuteTripReminder(tripId);
    await FirestoreService.deleteOwnerDocument(collection, tripId);
  }
}

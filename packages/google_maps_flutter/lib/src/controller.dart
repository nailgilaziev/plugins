// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of google_maps_flutter;

/// Controller for a single GoogleMap instance running on the host platform.
///
/// Change listeners are notified upon changes to any of
///
/// * the [options] property
/// * the collection of [Marker]s added to this map
/// * the [isCameraMoving] property
/// * the [cameraPosition] property
///
/// Listeners are notified after changes have been applied on the platform side.
///
/// Marker tap events can be received by adding callbacks to [onMarkerTapped].
class GoogleMapController extends ChangeNotifier {
  GoogleMapController._(
      this._id, GoogleMapOptions options, MethodChannel channel)
      : assert(_id != null),
        assert(options != null),
        assert(options.cameraPosition != null),
        assert(channel != null),
        _channel = channel {
    if (options.trackCameraPosition) {
      _cameraPosition = options.cameraPosition;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    _options = GoogleMapOptions.defaultOptions.copyWith(options);
  }

  static Future<GoogleMapController> init(
      int id, GoogleMapOptions options) async {
    assert(id != null);
    assert(options != null);
    assert(options.cameraPosition != null);
    final MethodChannel channel =
        MethodChannel('plugins.flutter.io/google_maps_$id');
    await channel.invokeMethod('map#waitForMap');
    return GoogleMapController._(id, options, channel);
  }

  final MethodChannel _channel;

  /// Callbacks to receive tap events for markers placed on this map.
  final ArgumentCallbacks<Marker> onMarkerTapped = ArgumentCallbacks<Marker>();

  /// Callbacks to receive tap events for info windows on markers
  final ArgumentCallbacks<Marker> onInfoWindowTapped =
      ArgumentCallbacks<Marker>();

  /// The configuration options most recently applied via controller
  /// initialization or [updateMapOptions].
  GoogleMapOptions get options => _options;
  GoogleMapOptions _options;

  /// The current set of markers on this map.
  ///
  /// The returned set will be a detached snapshot of the markers collection.
  Set<Marker> get markers => Set<Marker>.from(_markers.values);
  final Map<String, Marker> _markers = <String, Marker>{};

  /// True if the map camera is currently moving.
  bool get isCameraMoving => _isCameraMoving;
  bool _isCameraMoving = false;

  /// Returns the most recent camera position reported by the platform side.
  /// Will be null, if camera position tracking is not enabled via
  /// [GoogleMapOptions].
  CameraPosition get cameraPosition => _cameraPosition;
  CameraPosition _cameraPosition;

  final int _id;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'infoWindow#onTap':
        final String markerId = call.arguments['marker'];
        final Marker marker = _markers[markerId];
        if (marker != null) {
          onInfoWindowTapped(marker);
        }
        break;

      case 'marker#onTap':
        final String markerId = call.arguments['marker'];
        final Marker marker = _markers[markerId];
        if (marker != null) {
          onMarkerTapped(marker);
        }
        break;
      case 'camera#onMoveStarted':
        _isCameraMoving = true;
        notifyListeners();
        break;
      case 'camera#onMove':
        _cameraPosition = CameraPosition._fromJson(call.arguments['position']);
        notifyListeners();
        break;
      case 'camera#onIdle':
        _isCameraMoving = false;
        notifyListeners();
        break;
      default:
        throw MissingPluginException();
    }
  }

  /// Updates configuration options of the map user interface.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> updateMapOptions(GoogleMapOptions changes) async {
    assert(changes != null);
    final dynamic json = await _channel.invokeMethod(
      'map#update',
      <String, dynamic>{
        'options': changes._toJson(),
      },
    );
    _options = _options.copyWith(changes);
    _cameraPosition = CameraPosition._fromJson(json);
    notifyListeners();
  }

  /// Starts an animated change of the map camera position.
  ///
  /// The returned [Future] completes after the change has been started on the
  /// platform side.
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    await _channel.invokeMethod('camera#animate', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
    });
  }

  /// Changes the map camera position.
  ///
  /// The returned [Future] completes after the change has been made on the
  /// platform side.
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    await _channel.invokeMethod('camera#move', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
    });
  }

  /// Adds a marker to the map, configured using the specified custom [options].
  ///
  /// Change listeners are notified once the marker has been added on the
  /// platform side.
  ///
  /// The returned [Future] completes with the added marker once listeners have
  /// been notified.
  Future<Marker> addMarker(MarkerOptions options) async {
    final MarkerOptions effectiveOptions =
        MarkerOptions.defaultOptions.copyWith(options);
    final String markerId = await _channel.invokeMethod(
      'marker#add',
      <String, dynamic>{
        'options': effectiveOptions._toJson(),
      },
    );
    final Marker marker = Marker(markerId, effectiveOptions);
    _markers[markerId] = marker;
    notifyListeners();
    return marker;
  }

  /// Updates the specified [marker] with the given [changes]. The marker must
  /// be a current member of the [markers] set.
  ///
  /// Change listeners are notified once the marker has been updated on the
  /// platform side.
  ///
  /// The returned [Future] completes once listeners have been notified.
  Future<void> updateMarker(Marker marker, MarkerOptions changes) async {
    assert(marker != null);
    assert(_markers[marker._id] == marker);
    assert(changes != null);
    await _channel.invokeMethod('marker#update', <String, dynamic>{
      'marker': marker._id,
      'options': changes._toJson(),
    });
    marker._options = marker._options.copyWith(changes);
    notifyListeners();
  }

  /// Removes the specified [marker] from the map. The marker must be a current
  /// member of the [markers] set.
  ///
  /// Change listeners are notified once the marker has been removed on the
  /// platform side.
  ///
  /// The returned [Future] completes once listeners have been notified.
  Future<void> removeMarker(Marker marker) async {
    assert(marker != null);
    assert(_markers[marker._id] == marker);
    await _removeMarker(marker._id);
    notifyListeners();
  }

  /// Removes all [markers] from the map.
  ///
  /// Change listeners are notified once all markers have been removed on the
  /// platform side.
  ///
  /// The returned [Future] completes once listeners have been notified.
  Future<void> clearMarkers() async {
    assert(_markers != null);
    final List<String> markerIds = List<String>.from(_markers.keys);
    for (String id in markerIds) {
      await _removeMarker(id);
    }
    notifyListeners();
  }

  /// Helper method to remove a single marker from the map. Consumed by
  /// [removeMarker] and [clearMarkers].
  ///
  /// The returned [Future] completes once the marker has been removed from
  /// [_markers].
  Future<void> _removeMarker(String id) async {
    await _channel.invokeMethod('marker#remove', <String, dynamic>{
      'marker': id,
    });
    _markers.remove(id);
  }

  Future<void> injectBackendWmsUrl(String url) async {
    await _channel.invokeMethod('layers#url', <String, dynamic>{
      'url': url,
    });
  }

  Future<void> injectToken(String token) async {
    await _channel.invokeMethod('layers#token', <String, dynamic>{
      'token': token,
    });
  }

  Future<void> newLayersState(Map<String, bool> map) async {
    await _channel.invokeMethod('layers#state', map);
  }

  Future<void> invalidateLayersState() async {
    await _channel.invokeMethod('layers#invalidate', <String, dynamic>{});
  }

  Future<void> clear() async {
    await _channel.invokeMethod('map#clear', <String, dynamic>{});
  }
}

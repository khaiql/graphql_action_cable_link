import 'dart:async';

import 'package:action_cable/action_cable.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

enum ConnectionState {
  New,
  Connected,
  Subscribed,
  Disconnected,
  CannotConnect,
  ConnectionLost,
}

/// A function that returns the token for authentication
typedef GetAuthToken = FutureOr<String> Function();

class _ActionCableEvent {
  _ActionCableEvent({
    required this.state,
    required this.request,
  });

  final Request request;
  final ConnectionState state;
}

/// Create a new Link for Graphql subscription that is backed by Rails ActionCable websocket
/// Example:
/// ```dart
/// final cableLink = ActionCableLink(
///    webSocketUri,
///    getAuthHeaderFunc: getAuthHeader,
/// );
///
/// final httpLink = HttpLink(uri);
///
/// final link = Link.split(
///    (request) => request.issubscription,
///    cableLink,
///    httpLink,
/// );
///
/// final graphqlClient = GraphQLClient(
///    cache: GraphQLCache(),
///    link: link,
/// );
/// ```
class ActionCableLink extends Link {
  ActionCableLink(
    this.url, {
    this.channelName = 'GraphqlChannel',
    this.authHeaderKey = 'Authorization',
    this.action = 'execute',
    this.defaultHeaders = const {},
    this.getAuthTokenFunc,
    this.retryDuration = const Duration(seconds: 2),
  });

  /// name of the action
  final String action;

  /// name of the ActionCable channel
  final String channelName;

  /// name of the authentication header
  final String authHeaderKey;

  /// default headers to be sent to the Rails server
  final Map<String, String> defaultHeaders;

  /// The duration to retry connecting to the ActionCable server in case of connection failure
  final Duration retryDuration;

  final ResponseParser parser = const ResponseParser();
  final RequestSerializer serializer = const RequestSerializer();

  /// destination url of the ActionCable server
  final String url;

  /// A function that returns authentication header.
  /// If not null, this method will be invoked before sending the request,
  /// Then merge with [defaultHeaders] to send to the server
  final GetAuthToken? getAuthTokenFunc;

  ActionCable? _cable;
  Timer? _retryTimer;

  @override
  Stream<Response> request(Request request, [forward]) async* {
    final connectionStateController = StreamController<_ActionCableEvent>();
    final response = StreamController<Response>();

    connectionStateController.stream.listen((event) {
      switch (event.state) {
        case ConnectionState.Connected:
          _subscribed(event.request, response);
          break;
        case ConnectionState.Disconnected:
        case ConnectionState.CannotConnect:
        case ConnectionState.ConnectionLost:
          print('connection lost, attempting to reconnection in 2 second');

          _retryTimer ??= Timer(
            retryDuration,
            () {
              _connect(event.request, connectionStateController);
              _retryTimer!.cancel();
              _retryTimer = null;
            },
          );

          break;
        default:
      }
    });

    _connect(request, connectionStateController);

    response.onCancel = () {
      print('unsubscribe and disconnect from $channelName');
      _cable?.disconnect();
      _retryTimer?.cancel();
      connectionStateController.close();
    };

    yield* response.stream;
  }

  void _subscribed(Request request, StreamController<Response> response) {
    _cable!.subscribe(
      channelName,
      onSubscribed: () {
        _cable!.performAction(
          channelName,
          action: action,
          actionParams: serializer.serializeRequest(request),
        );
      },
      onMessage: (message) {
        response.add(parser.parseResponse(message['result']));
      },
    );
  }

  void _connect(Request request,
      StreamController<_ActionCableEvent> connectStateController) async {
    _cable = ActionCable.Connect(
      url,
      headers: await _getHeaders(),
      onConnected: () {
        print('Connected to websocket');

        connectStateController.add(
          _ActionCableEvent(request: request, state: ConnectionState.Connected),
        );
      },
      onCannotConnect: () {
        print('Cannot connect to websocket');

        connectStateController.add(
          _ActionCableEvent(
              request: request, state: ConnectionState.CannotConnect),
        );
      },
      onConnectionLost: () {
        print('Connection has been lost');
        connectStateController.add(
          _ActionCableEvent(
              request: request, state: ConnectionState.ConnectionLost),
        );
      },
    );
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = defaultHeaders;
    if (getAuthTokenFunc != null) {
      final token = await getAuthTokenFunc!();
      headers[authHeaderKey] = token;
    }

    return headers;
  }
}

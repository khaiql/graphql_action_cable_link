# graphql_action_cable_link

GraphQL Action Cable Link

---

A Graphql Subscription [Link](https://github.com/zino-app/graphql-flutter/blob/master/packages/graphql/README.md#links).

This only works for Rails server that uses [graphql-ruby](https://graphql-ruby.org/) 
and ActionCable implementation for Subscription.

## Installation

First, depend on this package

```yaml
dependencies:
  graphql_action_cable_link: ^0.0.1
```

## Usage

Make sure your graphql's subscription is backed by ActionCable, see https://graphql-ruby.org/subscriptions/action_cable_implementation.html 
for more details how to implement GraphQL subscription with Action Cable.

Basic usage:
```dart
final graphqlEndpoint = 'http://localhost:3333/graphql';
final webSocketUrl = 'ws://localhost:3333/cable';
final actionCableLink = ActionCableLink(webSocketUrl);
final httpLink = HttpLink(graphqlEndpoint);

// create a split link
final link = Link.split(
  (request) => request.isSubscription,
  actionCableLink,
  httpLink,
);

final graphqlClient = GraphQLClient(
  cache: GraphQLCache(),
  link: link,
);
```

Similar to the `HttpLink`, `ActionCableLink` also supports `defaultHeaders`.
```dart
final actionCableLink = ActionCablelink(webSocketUrl, defaultHeaders: { 'x-time-zone': 'Australia/Sydney' });
```

ActionCableLink also supports authentication header by providing a function that returns the token:

```dart
String getAuthToken() {
  return 'Bearer auth-token'; 
}

final actionCableLink = ActionCableLink(
  webSocketUrl, 
  getAuthTokenFunc: getAuthToken,
);

final httpLink = HttpLink(graphqlEndpoint);
final authLink = AuthLink(getToken: getAuthToken);
final link = Link.split(
  (request) => request.isSubscription,
  actionCableLink,
  authLink.concat(httpLink),
);
```
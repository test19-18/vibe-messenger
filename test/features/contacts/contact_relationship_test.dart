import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/contacts/domain/contact_relationship.dart';

void main() {
  test('maps an incoming pending request and resolves the peer id', () {
    final relationship = ContactRelationship.fromMap({
      'id': 'request-id',
      'requester_id': 'alice',
      'addressee_id': 'bob',
      'status': 'pending',
      'created_at': '2026-07-01T10:00:00Z',
    });

    expect(relationship.status, ContactStatus.pending);
    expect(relationship.isIncomingFor('bob'), isTrue);
    expect(relationship.otherUserId('bob'), 'alice');
  });
}

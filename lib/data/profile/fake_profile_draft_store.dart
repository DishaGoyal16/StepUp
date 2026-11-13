import '../../domain/profile_draft.dart';
import 'profile_draft_store.dart';

class InMemoryProfileDraftStore implements ProfileDraftStore {
  final Map<String, ProfileDraft> _drafts = {};

  @override
  Future<ProfileDraft?> load(String uid) async => _drafts[uid];

  @override
  Future<void> save(String uid, ProfileDraft draft) async => _drafts[uid] = draft;

  @override
  Future<void> clear(String uid) async => _drafts.remove(uid);
}

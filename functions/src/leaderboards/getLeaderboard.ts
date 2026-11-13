import { COL, PERIODS, Period } from '../config';
import { Req, requireEligibleUser } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { db } from '../lib/firebase';
import { periodKeyForNow, boardIdFor } from '../lib/time';
import { asRecord, limitParam, oneOf, optOneOf } from '../lib/validate';
import { rankDescending } from './aggregate';

const SCOPES = ['CAMPUS', 'MY_HOSTEL', 'HOSTELS', 'BUDDIES'] as const;

export interface LeaderboardResult {
  entries: Array<Record<string, unknown>>;
  me: { rank: number | null; value: number };
  metricLabel: string;
  periodKey: string;
  updatedAt: number | null;
}

function tieOrder(a: { verifiedSteps: number; name?: unknown; uid: string }, b: { verifiedSteps: number; name?: unknown; uid: string }): number {
  return b.verifiedSteps - a.verifiedSteps || String(a.name ?? '').localeCompare(String(b.name ?? '')) || a.uid.localeCompare(b.uid);
}

export async function handleGetLeaderboard(req: Req): Promise<LeaderboardResult> {
  const caller = await requireEligibleUser(req, { allowDeletionRequested: true });
  const d = asRecord(req.data);
  const scope = oneOf(d, 'scope', SCOPES);
  const period = oneOf(d, 'period', PERIODS as readonly Period[]);
  const hostelMetric = optOneOf(d, 'hostelMetric', ['AVERAGE', 'TOTAL'] as const) ?? 'AVERAGE';
  const limit = limitParam(d, 50, 100);
  const periodKey = periodKeyForNow(period, nowMs());
  const firestore = db();

  const boardSnap = await firestore.collection(COL.leaderboards).doc(boardIdFor('CAMPUS', periodKey)).get();
  const updatedAt = (boardSnap.data()?.updatedAt?.toMillis?.() as number | undefined) ?? null;
  const campusEntries = firestore.collection(COL.leaderboards).doc(boardIdFor('CAMPUS', periodKey)).collection(COL.entries);

  if (scope === 'HOSTELS') {
    const [hostelsSnap, entriesSnap] = await Promise.all([
      firestore.collection(COL.hostels).where('active', '==', true).get(),
      firestore.collection(COL.leaderboards).doc(boardIdFor('HOSTELS', periodKey)).collection(COL.entries).get(),
    ]);
    const byId = new Map(entriesSnap.docs.map((e) => [e.id, e.data()]));
    const rows = hostelsSnap.docs.map((h) => {
      const e = byId.get(h.id);
      return {
        hostelId: h.id,
        name: String(h.data().displayName ?? h.id),
        total: Number(e?.totalVerifiedSteps ?? 0),
        participants: Number(e?.participants ?? 0),
        average: Number(e?.averagePerParticipant ?? 0),
      };
    });
    const metric = (r: (typeof rows)[number]) => (hostelMetric === 'AVERAGE' ? r.average : r.total);
    rows.sort((a, b) => metric(b) - metric(a) || b.total - a.total || a.name.localeCompare(b.name));
    // rows: {rank, hostelId, name, value, participants, total, average}; value = the ranking metric (average or total)
    const ranked = rankDescending(rows, metric).map((r) => ({ rank: r.rank, hostelId: r.hostelId, name: r.name, value: r.value, participants: r.participants, total: r.total, average: r.average }));
    const myHostel = (caller.user.hostelId as string | null) ?? null;
    const mine = ranked.find((r) => r.hostelId === myHostel);
    return {
      entries: ranked.slice(0, limit),
      me: { rank: mine ? mine.rank : null, value: mine ? mine.value : 0 },
      metricLabel: hostelMetric === 'AVERAGE' ? 'Average verified steps per participant' : 'Total verified steps',
      periodKey,
      updatedAt,
    };
  }

  const myEntrySnap = await campusEntries.doc(caller.uid).get();
  const myEntry = myEntrySnap.data();
  const myValue = Number(myEntry?.verifiedSteps ?? 0);
  const myVisible = myEntry?.showOnLeaderboards === true;
  const shape = (id: string, e: FirebaseFirestore.DocumentData) => ({
    uid: id,
    name: e.displayName,
    photoUrl: e.photoUrl ?? null,
    hostelId: e.showHostel === false ? null : (e.hostelId ?? null),
    verifiedSteps: Number(e.verifiedSteps ?? 0),
  });

  if (scope === 'BUDDIES') {
    const conns = await firestore
      .collection(COL.buddyConnections)
      .where('uids', 'array-contains', caller.uid)
      .where('active', '==', true)
      .limit(300)
      .get();
    const buddyUids = conns.docs.map((c) => (c.data().uids as string[]).find((u) => u !== caller.uid)).filter((u): u is string => !!u);
    const snaps = buddyUids.length ? await firestore.getAll(...buddyUids.map((u) => campusEntries.doc(u))) : [];
    const rows = snaps.filter((s) => s.exists && s.data()?.showOnLeaderboards === true).map((s) => shape(s.id, s.data() as FirebaseFirestore.DocumentData));
    rows.push(shape(caller.uid, myEntry ?? { displayName: caller.user.displayName, photoUrl: caller.user.photoUrl ?? null, hostelId: caller.user.hostelId ?? null, verifiedSteps: 0 }));
    const ranked = rankDescending(rows, (r) => r.verifiedSteps);
    const mine = ranked.find((r) => r.uid === caller.uid);
    return {
      entries: ranked.slice(0, limit).map(({ verifiedSteps: _v, ...r }) => r),
      me: { rank: mine ? mine.rank : null, value: myValue },
      metricLabel: 'Verified steps',
      periodKey,
      updatedAt,
    };
  }

  let q: FirebaseFirestore.Query = campusEntries.where('showOnLeaderboards', '==', true);
  let countQ: FirebaseFirestore.Query = campusEntries.where('showOnLeaderboards', '==', true);
  if (scope === 'MY_HOSTEL') {
    const myHostel = (caller.user.hostelId as string | null) ?? '';
    q = q.where('hostelId', '==', myHostel);
    countQ = countQ.where('hostelId', '==', myHostel);
  }
  const snap = await q.where('verifiedSteps', '>', 0).orderBy('verifiedSteps', 'desc').limit(limit).get();
  // Firestore breaks ties by document id (descending); make the order explicit and stable: name, then uid.
  const rows = snap.docs.map((s) => shape(s.id, s.data())).sort(tieOrder);
  const ranked = rankDescending(rows, (r) => r.verifiedSteps);
  let myRank: number | null = null;
  if (myVisible && myValue > 0 && (scope !== 'MY_HOSTEL' || myEntry?.hostelId === caller.user.hostelId)) {
    const higher = await countQ.where('verifiedSteps', '>', myValue).count().get();
    myRank = higher.data().count + 1;
  }
  return {
    entries: ranked.map(({ verifiedSteps: _v, ...r }) => r),
    me: { rank: myRank, value: myValue },
    metricLabel: 'Verified steps',
    periodKey,
    updatedAt,
  };
}

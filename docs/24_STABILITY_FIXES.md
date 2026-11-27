# 24 — Play Console stability fixes (1.0.25 / build 26)

Evidence: Play Console → Crashes and ANRs, window 2026-10-31 → 2026-11-28.
Three issues, each **1 affected user / 1 event / 33.3 % user-perceived**, all on
low-RAM Redmi devices. The 28-day volume is tiny, but two of the three are the
same bug and both paths are reachable on every build.

## 1. `dart::ScavengerVisitor::VisitPointers` ANR (Redmi A2, Android 13)

Main thread of the ANR dump:

```text
HiveService.cacheGet → cacheGetList
→ QuizRepository.getChapterQuestions
→ BattleQuestionGenerator._poolQuestions.worker  (microtask)
→ jsonDecode → _ChunkedJsonParser.parseString → String.substring
→ dart::Object::Allocate → Heap::CollectNewSpaceGarbage
→ ScavengerVisitor::VisitPointers   ← input dispatch blocked here
```

`_poolQuestions` pools **every chapter** with six workers. Each worker decoded
its cached chapter bank synchronously on the UI isolate; the short-lived strings
from `jsonDecode` filled new-space and the resulting GC pause blocked input.

## 2. `stub CallBootstrapNative` ANR (Redmi 8A Dual, Android 10)

The frame addresses match issue 1 exactly (`Object::Allocate`,
`_StringBase.substringUnchecked`, `CallBootstrapNative`) — same root cause. The
Play title is just the stub where the GC was entered, not a broken native
symbol.

## 3. `FlutterFirebaseFirestorePlugin.queryGet` OOM (Redmi 6A, Android 9)

```text
java.lang.OutOfMemoryError: pthread_create (1040KB stack) failed: Try again
  at java.lang.Thread.start
  at java.util.concurrent.ThreadPoolExecutor.addWorker / execute
  at FlutterFirebaseFirestorePlugin.queryGet (…:785)
```

The device could not create another ~1 MB thread stack. It is thread/memory
exhaustion in the Firestore plugin, not a failed query. A battle that pools
every stale chapter used to fire one unawaited Firestore revalidation **per
chapter**; each read asks the plugin's executor for a worker.

## What changed

- `HiveService.cacheGet` memoises decoded values by key + raw JSON (bounded LRU
  of 24) and invalidates on `cachePut`, `cacheRemove`, `clearCache` and
  `clearAll`. A bank is decoded once per process instead of once per tap.
- `HiveService.cacheGetListAsync` decodes a cold payload in a background
  isolate through a serialised queue, so pooling cannot spawn one isolate per
  chapter on a 2 GB phone. `QuizRepository.getChapterQuestions` and
  `getCategoriesAndChapters` use it.
- `QuizRepository._revalidateIfStale` now queues refreshes and runs at most two
  at a time (`_maxConcurrentRevalidations`). Stale data is still served
  immediately and refreshed in the background — only the Firestore fan-out is
  bounded.

`test/offline_cache_test.dart` pins async read/invalidation and the two-at-a-time
refresh bound. These fixes land with the next version bump; the ANR/OOM events
above were from 1.0.25 and are not expected to disappear from already-shipped
builds.
